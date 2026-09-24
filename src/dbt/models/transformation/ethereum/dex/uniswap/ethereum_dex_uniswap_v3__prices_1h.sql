{{
    config(
        incremental_predicates=[overwrite_from_start('block_timestamp')]
    )
}}

{#-
    Hourly bars per pool, rolled up from the minute bars.

    Needed because the gold layer works on a 1h grid (logreturns, 24h
    rolling windows), and joining minute bars into it would multiply the
    grain for no reason.
-#}

with prices as (

    select *
    from {{ ref('ethereum_dex_uniswap_v3__prices') }}
    where true
    {{ source_date_filter('block_timestamp') }}

),

hourly as (

    select
        timestamp_trunc(block_timestamp, hour) as block_timestamp,
        pool_address,
        pool_name,
        fee_tier,
        token0_address,
        token0_symbol,
        token1_address,
        token1_symbol,

        count(*) as n_swaps,
        count(distinct trader) as n_traders,

        -- OHLC of token0 quoted in token1
        array_agg(
            token1_per_token0 order by block_timestamp limit 1
        )[safe_offset(0)] as open,
        max(token1_per_token0) as high,
        min(token1_per_token0) as low,
        array_agg(
            token1_per_token0 order by block_timestamp desc limit 1
        )[safe_offset(0)] as close,
        avg(token1_per_token0) as avg_price,

        sum(amount_in) as volume_leg_in,
        sum(amount_out) as volume_leg_out

    from prices
    group by 1, 2, 3, 4, 5, 6, 7, 8

)

select
    concat(
        pool_address, '-', format_timestamp('%Y-%m-%dT%H', block_timestamp)
    ) as bar_id,
    block_timestamp,
    pool_address,
    pool_name,
    fee_tier,
    token0_address,
    token0_symbol,
    token1_address,
    token1_symbol,
    n_swaps,
    n_traders,
    open,
    high,
    low,
    close,
    avg_price,
    -- USD view: our pools quote against USDT, so the stable leg is the quote
    case when token1_symbol = 'USDT' then close end as token0_price_usd,
    case when token0_symbol = 'USDT' then close end as token1_price_usd,
    volume_leg_in,
    volume_leg_out,
    current_timestamp() as inserted_at

from hourly
