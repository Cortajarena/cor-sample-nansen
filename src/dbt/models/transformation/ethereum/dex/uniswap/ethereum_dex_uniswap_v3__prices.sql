{{
    config(
        incremental_predicates=[overwrite_from_start('block_timestamp')]
    )
}}

{#-
    One price observation per swap.

    This is the payoff of using V3: the price comes from the pool's
    sqrtPriceX96 emitted in the Swap event itself, not from dividing the
    swap's own amounts. That means:
      * it is not biased by the fee or the price impact of this trade
      * it exists for every swap, in a single orientation
      * no Sync/reserve reconstruction needed (see docs/draft.md 3.1.1)
-#}

with trades as (

    select *
    from {{ ref('ethereum_dex_uniswap_v3__trades') }}
    where true
    {{ source_date_filter('block_timestamp') }}

)

select
    swap_id,
    block_number,
    block_timestamp,
    transaction_hash,
    log_index,

    pool_address,
    pool_name,
    fee_tier,

    token0_address,
    token0_symbol,
    token1_address,
    token1_symbol,

    token1_per_token0,
    safe_divide(1, token1_per_token0) as token0_per_token1,

    -- USD only when one leg is a whitelisted stablecoin: we are quoting
    -- against that leg, not against an oracle.
    case
        when token1_is_stable then token1_per_token0
        when token0_is_stable then safe_divide(1, token1_per_token0)
    end as token0_price_usd,
    case
        when token0_is_stable then token1_per_token0
        when token1_is_stable then safe_divide(1, token1_per_token0)
    end as token1_price_usd,

    trader,
    token_in_symbol,
    token_out_symbol,
    amount_in,
    amount_out,

    current_timestamp() as inserted_at

from trades
