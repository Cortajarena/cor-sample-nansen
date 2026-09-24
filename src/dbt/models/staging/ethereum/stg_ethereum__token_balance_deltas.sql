{{
    config(
        incremental_predicates=[overwrite_from_start('block_timestamp')],
        cluster_by=['address', 'token_address']
    )
}}

{#-
    Daily token balance DELTAS per (address, token).

    Why deltas, not balances: a balance is a running total, and insert_overwrite
    replaces whole partitions, so storing a cumulative number per day would
    have to be recomputed from all history on every run. Storing the per-day
    delta keeps each partition independent; the running balance is a window
    sum over these deltas in the silver layer.

    Scope (both are deliberate, see docs/draft.md 3.1.1):
      * only whitelisted tokens - we cannot price anything else, and an
        unpriceable position is worse than an absent one
      * only addresses that appear in a Uniswap V2 swap (the watchlist) -
        "every address with a balance" is not a tractable set

    Known limitation: balances start at START_DATE, not at genesis, so an
    address holding a token since 2020 shows a balance that is too low.
-#}

with transfers as (

    select
        block_timestamp,
        lower(address) as token_address,
        lower(from_address) as from_address,
        lower(to_address) as to_address,
        -- quantity is STRING (uint256): BIGNUMERIC, never INT64/FLOAT64
        safe_cast(quantity as bignumeric) as quantity_raw

    from {{ source('ethereum_mainnet', 'token_transfers') }}

    where true
        and not coalesce(removed, false)
        and lower(address) in (
            select lower(token_address) from {{ ref('token_whitelist') }}
        )
        {{ source_date_filter('block_timestamp') }}

),

watchlist as (

    -- proxy for "addresses we care about": anyone who swapped on a
    -- whitelisted pair, either as sender or as recipient
    select distinct address
    from (
        select lower(sender) as address
        from {{ ref('stg_ethereum__logs_uniswap_v3_swaps') }}
        union all
        select lower(recipient) as address
        from {{ ref('stg_ethereum__logs_uniswap_v3_swaps') }}
    )
    where address is not null

),

flows as (

    -- money out of the address
    select
        timestamp_trunc(block_timestamp, day) as block_timestamp,
        token_address,
        from_address as address,
        -quantity_raw as delta_raw
    from transfers

    union all

    -- money into the address
    select
        timestamp_trunc(block_timestamp, day) as block_timestamp,
        token_address,
        to_address as address,
        quantity_raw as delta_raw
    from transfers

)

select
    block_timestamp,
    address,
    token_address,
    sum(delta_raw) as delta_raw,
    count(*) as n_transfers,
    current_timestamp() as inserted_at

from flows
where address is not null
    and address in (select address from watchlist)
group by 1, 2, 3
