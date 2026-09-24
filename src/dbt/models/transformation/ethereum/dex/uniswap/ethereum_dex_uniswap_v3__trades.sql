{{
    config(
        incremental_predicates=[overwrite_from_start('block_timestamp')]
    )
}}

{#-
    One row per Uniswap V3 swap, in human units, with a direction.

    V3 amounts are signed and written from the POOL's perspective:
      amount0 > 0 -> token0 went INTO the pool, i.e. the user sold token0
      amount0 < 0 -> token0 left the pool, i.e. the user bought token0
    So the sign alone tells us the direction; there is no amount0In /
    amount1Out pair to reconcile like in V2.
-#}

with swaps as (

    select *
    from {{ ref('stg_ethereum__logs_uniswap_v3_swaps') }}
    where true
    {{ source_date_filter('block_timestamp') }}

),

pools as (

    select
        lower(pool_address) as pool_address,
        pool_name,
        fee_tier,
        -- V3 sorts token0 < token1 by address, same as V2. Derive it rather
        -- than trusting column order in the seed.
        if(
            lower(token_a_address) < lower(token_b_address),
            lower(token_a_address),
            lower(token_b_address)
        ) as token0_address,
        if(
            lower(token_a_address) < lower(token_b_address),
            lower(token_b_address),
            lower(token_a_address)
        ) as token1_address

    from {{ ref('uniswap_v3_pools') }}

),

tokens as (

    select
        lower(token_address) as token_address,
        symbol,
        decimals,
        is_stable

    from {{ ref('token_whitelist') }}

),

enriched as (

    select
        s.swap_id,
        s.block_number,
        s.block_timestamp,
        s.transaction_hash,
        s.log_index,

        'uniswap_v3' as dex,
        s.pool_address,
        p.pool_name,
        p.fee_tier,

        p.token0_address,
        t0.symbol as token0_symbol,
        t0.decimals as token0_decimals,
        t0.is_stable as token0_is_stable,

        p.token1_address,
        t1.symbol as token1_symbol,
        t1.decimals as token1_decimals,
        t1.is_stable as token1_is_stable,

        s.sender,
        s.recipient,
        s.initiator,
        s.is_routed,
        s.amount0,
        s.amount1,
        s.price_raw

    from swaps as s
    inner join pools as p
        on s.pool_address = p.pool_address
    left join tokens as t0
        on p.token0_address = t0.token_address
    left join tokens as t1
        on p.token1_address = t1.token_address

),

human_units as (

    select
        *,
        cast(amount0 as float64) / power(10, token0_decimals) as amount0_adj,
        cast(amount1 as float64) / power(10, token1_decimals) as amount1_adj
    from enriched

),

directional as (

    select
        *,
        -- amount0 > 0: token0 in, token1 out
        if(amount0_adj > 0, token0_address, token1_address) as token_in_address,
        if(amount0_adj > 0, token0_symbol, token1_symbol) as token_in_symbol,
        if(amount0_adj > 0, token1_address, token0_address) as token_out_address,
        if(amount0_adj > 0, token1_symbol, token0_symbol) as token_out_symbol,
        if(amount0_adj > 0, amount0_adj, amount1_adj) as amount_in,
        if(amount0_adj > 0, -amount1_adj, -amount0_adj) as amount_out,
        if(amount0_adj > 0, token0_is_stable, token1_is_stable)
            as token_in_is_stable,
        if(amount0_adj > 0, token1_is_stable, token0_is_stable)
            as token_out_is_stable
    from human_units

)

select
    swap_id,
    block_number,
    block_timestamp,
    transaction_hash,
    log_index,

    dex,
    pool_address,
    pool_name,
    fee_tier,

    token0_address,
    token0_symbol,
    token0_is_stable,
    token1_address,
    token1_symbol,
    token1_is_stable,

    -- the trader is the tx signer, not the pool caller: `sender` is the
    -- router for anything routed, and labelling on that collapses retail
    -- flow into a handful of contract addresses
    coalesce(initiator, sender) as trader,
    sender as pool_caller,
    recipient as beneficiary,
    is_routed,

    token_in_address,
    token_in_symbol,
    token_out_address,
    token_out_symbol,
    amount_in,
    amount_out,

    -- effective rate paid, fees and slippage included
    safe_divide(amount_out, amount_in) as amount_out_per_amount_in,

    -- pool price at this swap, from sqrtPriceX96 (V3 gives it to us)
    price_raw * power(10, token0_decimals - token1_decimals)
        as token1_per_token0,

    -- USD proxy: only defined when one leg is a whitelisted stablecoin
    case
        when token_in_is_stable then amount_in
        when token_out_is_stable then amount_out
    end as notional_usd,

    current_timestamp() as inserted_at

from directional
