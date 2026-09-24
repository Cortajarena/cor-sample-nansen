{{
    config(
        incremental_predicates=[overwrite_from_start('block_timestamp')],
        partition_by={
            'field': 'block_timestamp',
            'data_type': 'timestamp',
            'granularity': 'day',
        },
        cluster_by=['address']
    )
}}

{#-
    Smart traders: one row per (address, hour) with performance metrics.

    Portfolio value = sum of mark-to-market balances across all tokens,
    on the forward-filled hourly grid from the silver `balances` model.
    Returns are logreturns of that value; every metric is computed on a
    trailing 24-hour window.

    BTC benchmark: the WBTC/USDT pool price. It is on-chain and already
    in our pool set, so the benchmark needs no external source - but it
    is a PROXY (WBTC is not BTC).

    Statistical honesty: `n_obs` is exposed on every row. The sample
    window is ~30h, so a 24h trailing metric rests on very few
    observations - the definitions are the point, not the numbers. See
    docs/draft.md 3.1.1.
-#}

with balances as (

    select *
    from {{ ref('ethereum_dex_uniswap_v3__balances') }}
    where true
    {{ source_date_filter('block_timestamp') }}

),

portfolio as (

    select
        block_timestamp,
        address,
        sum(balance_usd) as value_usd,
        sum(flow_usd) as net_flow_usd,
        sum(turnover_usd) as turnover_usd,
        count(distinct token_address) as n_tokens

    from balances
    group by 1, 2

),

benchmark as (

    select
        block_timestamp,
        price_usd as btc_usd

    from {{ ref('ethereum_dex_uniswap_v3__token_prices_1h') }}
    where symbol = 'WBTC'

),

joined as (

    select
        p.block_timestamp,
        p.address,
        p.value_usd,
        p.net_flow_usd,
        p.turnover_usd,
        p.n_tokens,
        b.btc_usd

    from portfolio as p
    left join benchmark as b
        on p.block_timestamp = b.block_timestamp

),

lagged as (

    select
        *,
        lag(value_usd) over w as prev_value_usd,
        lag(btc_usd) over w as prev_btc_usd

    from joined
    window w as (partition by address order by block_timestamp)

),

returns as (

    select
        *,
        -- TIME-WEIGHTED return: strip this hour's external flows out of
        -- the end value, otherwise a deposit shows up as performance.
        --   r_t = (V_t - F_t) / V_(t-1) - 1, with F_t the signed net flow.
        -- The sample's truncated history also produces negative
        -- "balances", which cannot have a return, so those stay null
        -- rather than wrong.
        value_usd - net_flow_usd as value_ex_flows_usd,
        case
            when prev_value_usd > 0 and (value_usd - net_flow_usd) > 0
                then ln((value_usd - net_flow_usd) / prev_value_usd)
        end as logret,
        case
            when prev_btc_usd > 0 and btc_usd > 0
                then ln(btc_usd / prev_btc_usd)
        end as btc_logret

    from lagged

),

windowed as (

    select
        *,
        count(logret) over w24 as n_obs,
        sum(logret) over w24 as sum_x,
        sum(btc_logret) over w24 as sum_y,
        sum(logret * btc_logret) over w24 as sum_xy,
        sum(btc_logret * btc_logret) over w24 as sum_y2,
        sum(logret * logret) over w24 as sum_x2,
        sum(case when logret < 0 then logret * logret else 0 end) over w24
            as sum_x2_down,
        sum(turnover_usd) over w24 as turnover_24

    from returns
    window w24 as (
        partition by address
        order by block_timestamp
        rows between 23 preceding and current row
    )

)

select
    concat(address, '-', format_timestamp('%Y-%m-%dT%H', block_timestamp))
        as trader_hour_id,
    block_timestamp,
    address,

    value_usd,
    n_tokens,
    btc_usd,

    -- single period
    logret,
    btc_logret,

    -- trailing 24h
    n_obs,
    exp(sum_x) - 1 as geometric_return_24,
    exp(sum_y) - 1 as btc_return_24,

    -- beta = cov(x, y) / var(y), expanded into window sums
    safe_divide(
        n_obs * sum_xy - sum_x * sum_y,
        nullif(n_obs * sum_y2 - sum_y * sum_y, 0)
    ) as beta_24,

    -- alpha = our return minus the benchmark's, net of beta
    (exp(sum_x) - 1)
        - coalesce(
            safe_divide(
                n_obs * sum_xy - sum_x * sum_y,
                nullif(n_obs * sum_y2 - sum_y * sum_y, 0)
            ),
            0
        ) * (exp(sum_y) - 1) as alpha_24,

    -- sharpe: mean / stdev of logreturns, scaled to a daily equivalent
    safe_divide(
        sum_x / nullif(n_obs, 0),
        sqrt(
            safe_divide(sum_x2 - sum_x * sum_x / nullif(n_obs, 0),
                        nullif(n_obs - 1, 0))
        )
    ) * sqrt(24) as sharpe_24,

    -- sortino: same, but only downside deviation in the denominator
    safe_divide(
        sum_x / nullif(n_obs, 0),
        sqrt(safe_divide(sum_x2_down, nullif(n_obs, 0)))
    ) * sqrt(24) as sortino_24,

    -- activity: trailing turnover relative to current portfolio size
    safe_divide(turnover_24, nullif(abs(value_usd), 0)) as turnover_ratio_24,

    turnover_usd,
    turnover_24,

    current_timestamp() as inserted_at

from windowed
