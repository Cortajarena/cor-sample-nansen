{{
    config(
        incremental_predicates=[overwrite_from_start('block_timestamp')]
    )
}}

{#-
    Uniswap V3 Swap logs, decoded.

    Event:
        Swap(address indexed sender,
             address indexed recipient,
             int256 amount0,
             int256 amount1,
             uint160 sqrtPriceX96,
             uint128 liquidity,
             int24 tick)

    Layout on chain:
        topics[0] = keccak256(signature)   -> the filter that makes this cheap
        topics[1] = sender     (indexed)
        topics[2] = recipient  (indexed)
        data      = amount0 | amount1 | sqrtPriceX96 | liquidity | tick

    Two things differ from V2 and both matter:
      * amounts are SIGNED int256, from the POOL's point of view: positive
        means the token went into the pool (the user sold it), negative
        means it left (the user bought it). Decoding needs two's
        complement - see hex_to_int256.
      * sqrtPriceX96 is the pool price AT THIS SWAP. V2 makes you infer
        price from the amount ratio; V3 gives it to you directly, which is
        why the whole mark-to-market story gets simpler.

    Signature verified with keccak256, not copied by eye.
-#}

{% set swap_signature =
    'Swap(address,address,int256,int256,uint160,uint128,int24)' %}
{% set swap_topic = '0xc42079f94a6350d7e6235f29174924f928cc2ac818eb'
                    ~ '64fed8004e115fbcca67' %}

with raw_logs as (

    select
        block_number,
        block_timestamp,
        block_hash,
        transaction_hash,
        transaction_index,
        log_index,
        lower(address) as pool_address,
        topics,
        data

    from {{ source('ethereum_mainnet', 'logs') }}

    where true
        and topics[safe_offset(0)] = '{{ swap_topic }}'
        and not coalesce(removed, false)
        -- whitelisted pools only: decoding every V3 pool means decoding
        -- thousands of long-tail / scam tokens we do not care about
        and lower(address) in (
            select lower(pool_address) from {{ ref('uniswap_v3_pools') }}
        )
        {{ source_date_filter('block_timestamp') }}

),

{#-
    Resolve WHO actually traded.

    `Swap.sender` is the address that CALLED the pool - for anything routed
    through SwapRouter02 / Universal Router that is the router contract, not
    a person, and labelling on it collapses most retail flow into a handful
    of contract addresses. `Swap.recipient` is just who received the tokens.

    The only field that means "the trader" is the transaction signer, so we
    join `transactions` on transaction_hash. It costs ~0.27 GB for the window
    (partition-pruned) and needs no list of router addresses, so it keeps
    working for routers that do not exist yet.
-#}
signers as (

    select
        transaction_hash,
        -- one row per tx: the table is append-only, but dedupe defensively
        any_value(lower(from_address)) as initiator,
        any_value(lower(to_address)) as tx_to

    from {{ source('ethereum_mainnet', 'transactions') }}

    where true
        {{ source_date_filter('block_timestamp') }}

    group by transaction_hash

),

raw_logs_with_signer as (

    select
        raw_logs.*,
        signers.initiator,
        signers.tx_to

    from raw_logs
    left join signers
        on raw_logs.transaction_hash = signers.transaction_hash

),

decoded as (

    select
        block_number,
        block_timestamp,
        block_hash,
        transaction_hash,
        transaction_index,
        log_index,
        pool_address,

        -- who signed the transaction (the actual trader)
        initiator,
        tx_to,

        -- indexed params: last 20 bytes of each topic
        {{ abi_address_from_topic('topics', 1) }} as sender,
        {{ abi_address_from_topic('topics', 2) }} as recipient,

        -- non-indexed params: 32-byte words, in declaration order
        {{ hex_to_int256(abi_word('data', 0)) }} as amount0,
        {{ hex_to_int256(abi_word('data', 1)) }} as amount1,

        -- sqrtPriceX96 -> token1 per token0, in RAW units.
        -- price = (sqrtPriceX96 / 2^96)^2
        -- FLOAT64 is fine here: the value is a ratio, and 15 significant
        -- digits is far more precision than any price needs. BIGNUMERIC
        -- would overflow (sqrtPriceX96^2 can approach 2^320).
        pow(
            safe_cast(concat('0x', {{ abi_word('data', 2) }}) as float64)
                / pow(2, 96),
            2
        ) as price_raw,

        {{ hex_to_uint(abi_word('data', 3)) }} as liquidity,
        {{ hex_to_uint(abi_word('data', 4)) }} as tick_raw,

        data as raw_data,
        topics as raw_topics,

        current_timestamp() as inserted_at

    from raw_logs_with_signer

)

select
    concat(transaction_hash, '-', cast(log_index as string)) as swap_id,
    decoded.*,
    -- routed == the pool was called by something other than the signer,
    -- i.e. a router/aggregator contract sat in the middle
    (initiator is not null and initiator != sender) as is_routed,
    '{{ swap_signature }}' as event_signature

from decoded
