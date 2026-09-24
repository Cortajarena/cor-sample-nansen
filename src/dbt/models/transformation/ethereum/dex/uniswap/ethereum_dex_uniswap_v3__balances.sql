{{
    config(
        materialized='table',
        partition_by={
            'field': 'block_timestamp',
            'data_type': 'timestamp',
            'granularity': 'day',
        },
        cluster_by=['address']
    )
}}

{#-
    Running balances per (address, token) on a forward-filled hourly grid.

    Why `table` and not incremental: a balance is CUMULATIVE, and
    insert_overwrite replaces whole partitions. On an incremental run the
    window only covers the lookback, so the running sum would be derived
    from truncated history and every balance would silently reset. The
    honest options are (a) carry the previous balance forward explicitly,
    or (b) rebuild from the deltas. Our delta table is ~4k rows, so (b)
    is cheap and cannot be wrong. A production version with real history
    would do (a) - see docs/draft.md 3.1.1.

    Forward-filled on purpose: the gold layer takes logreturns, and a
    sparse grid makes lag() jump irregular intervals, which corrupts
    every downstream metric.
-#}

with deltas as (

    select *
    from {{ ref('stg_ethereum__token_balance_deltas') }}
    where true
    {{ source_date_filter('block_timestamp') }}

),

whitelist as (

    select
        lower(token_address) as token_address,
        symbol,
        decimals

    from {{ ref('token_whitelist') }}

),

bounds as (

    select
        timestamp_trunc(min(block_timestamp), hour) as h0,
        timestamp_trunc(max(block_timestamp), hour) as h1

    from deltas

),

hours as (

    select h as block_timestamp
    from bounds, unnest(generate_timestamp_array(h0, h1, interval 1 hour)) as h

),

pairs as (

    select distinct address, token_address
    from deltas

),

grid as (

    select
        p.address,
        p.token_address,
        h.block_timestamp

    from pairs as p
    cross join hours as h

),

deltas_hourly as (

    select
        timestamp_trunc(block_timestamp, hour) as block_timestamp,
        address,
        token_address,
        sum(delta_raw) as delta_raw,
        sum(n_transfers) as n_transfers

    from deltas
    group by 1, 2, 3

),

filled as (

    select
        g.block_timestamp,
        g.address,
        g.token_address,
        coalesce(d.delta_raw, 0) as delta_raw,
        coalesce(d.n_transfers, 0) as n_transfers

    from grid as g
    left join deltas_hourly as d
        on g.address = d.address
        and g.token_address = d.token_address
        and g.block_timestamp = d.block_timestamp

),

running as (

    select
        *,
        sum(delta_raw) over (
            partition by address, token_address
            order by block_timestamp
            rows between unbounded preceding and current row
        ) as balance_raw

    from filled

)

select
    concat(
        r.address, '-', r.token_address, '-',
        format_timestamp('%Y-%m-%dT%H', r.block_timestamp)
    ) as balance_id,
    r.block_timestamp,
    r.address,
    r.token_address,
    w.symbol,
    w.decimals,

    r.balance_raw,
    cast(r.balance_raw as float64) / power(10, w.decimals) as balance,

    tp.price_usd,
    cast(r.balance_raw as float64) / power(10, w.decimals)
        * tp.price_usd as balance_usd,

    -- SIGNED flow of the hour, valued at that hour's price. This is what
    -- has to come out of the performance calculation: a deposit is not
    -- alpha (see docs/draft.md 3.1.1).
    cast(r.delta_raw as float64) / power(10, w.decimals)
        * tp.price_usd as flow_usd,

    -- turnover: absolute flow, i.e. how much the address is moving
    -- regardless of direction - a proxy for activity
    abs(cast(r.delta_raw as float64)) / power(10, w.decimals)
        * tp.price_usd as turnover_usd,

    r.delta_raw,
    r.n_transfers,
    current_timestamp() as inserted_at

from running as r
left join whitelist as w
    on r.token_address = w.token_address
left join {{ ref('ethereum_dex_uniswap_v3__token_prices_1h') }} as tp
    on r.token_address = tp.token_address
    and r.block_timestamp = tp.block_timestamp
