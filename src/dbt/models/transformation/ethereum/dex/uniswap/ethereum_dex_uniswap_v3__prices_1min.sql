{{
    config(
        incremental_predicates=[overwrite_from_start('block_timestamp')]
    )
}}

{#-
    Minute OHLC bars per pool, built from the sqrtPriceX96 price series.

    `block_timestamp` is truncated to the minute; it stays the partition
    key (day granularity in dbt_project.yml), so bars line up with the rest
    of the silver layer.
-#}

with prices as (

    select *
    from {{ ref('ethereum_dex_uniswap_v3__prices') }}
    where true
    {{ source_date_filter('block_timestamp') }}

),

bars as (

    select
        timestamp_trunc(block_timestamp, minute) as block_timestamp,
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

        sum(if(token_in_symbol = token0_symbol, amount_in, amount_out))
            as volume_token0,
        sum(if(token_in_symbol = token0_symbol, amount_out, amount_in))
            as volume_token1,

        sum(amount_in) as volume_leg_in,
        sum(amount_out) as volume_leg_out

    from prices
    group by 1, 2, 3, 4, 5, 6, 7, 8

)

select
    concat(
        pool_address, '-', format_timestamp('%Y-%m-%dT%H:%M:%S', block_timestamp)
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
    volume_token0,
    volume_token1,
    volume_leg_in,
    volume_leg_out,
    current_timestamp() as inserted_at

from bars
