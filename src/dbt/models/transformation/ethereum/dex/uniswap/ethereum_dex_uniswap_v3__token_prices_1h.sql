{{
    config(
        incremental_predicates=[overwrite_from_start('block_timestamp')],
        cluster_by=['token_address']
    )
}}

{#-
    One USD price per token per hour - the mark-to-market join target.

    This is the "unified price schema" step the draft talks about: pool
    level bars are useless for marking a portfolio, you need one row per
    (token, hour) regardless of which pool it came from. Both legs of
    every pool are unpivoted, so a token keeps its price even when it
    happens to be token0 in one pool and token1 in another.

    Sources are only the whitelisted USDT-quoted pools, so `price_usd`
    exists for the non-stable leg of each pool (and for both legs of the
    stable pairs). Tokens with no price in an hour simply get no row -
    we never fabricate a mark.
-#}

with hourly as (

    select *
    from {{ ref('ethereum_dex_uniswap_v3__prices_1h') }}
    where true
    {{ source_date_filter('block_timestamp') }}

),

hours as (

    select distinct block_timestamp
    from hourly

),

-- USDT is ALWAYS the quote leg in our pool set, so it never gets a price
-- from a swap. It is the numeraire: mark it at 1.0, otherwise every USDT
-- balance silently drops out of the portfolio value.
stables as (

    select
        h.block_timestamp,
        -- lower(): the seed keeps checksummed addresses, everything else
        -- in the pipeline is lowercase, and this join would silently miss
        lower(w.token_address) as token_address,
        w.symbol,
        1.0 as price_usd,
        'numeraire' as pool_address

    from hours as h
    cross join {{ ref('token_whitelist') }} as w
    where w.is_stable

),

unpivoted as (

    select
        block_timestamp,
        token0_address as token_address,
        token0_symbol as symbol,
        token0_price_usd as price_usd,
        pool_address
    from hourly

    union all

    select
        block_timestamp,
        token1_address as token_address,
        token1_symbol as symbol,
        token1_price_usd as price_usd,
        pool_address
    from hourly

    union all

    select block_timestamp, token_address, symbol, price_usd, pool_address
    from stables

)

select
    block_timestamp,
    token_address,
    symbol,
    -- avg across pools if a token is priced by more than one
    avg(price_usd) as price_usd,
    count(distinct pool_address) as n_pools_pricing,
    current_timestamp() as inserted_at

from unpivoted
where price_usd is not null
group by 1, 2, 3
