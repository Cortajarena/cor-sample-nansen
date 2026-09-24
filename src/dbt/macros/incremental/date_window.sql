{#-
    Incremental windowing.

    Two knobs, both passed as dbt vars so Prefect can drive them:

      start_date / end_date - an explicit, CLOSED-OPEN range
        [start_date, end_date) for a bounded backfill.

    START_DATE is a floor, never a dial: a backfill start is clamped UP to
    it, so no run can read before it no matter what the caller asks for.
    The window is deliberately narrow - the public dataset is petabyte
    scale and partition-pruned, so the difference between filtering and
    not filtering is ~1,600x on these tables.
-#}

{#- START_DATE floor from the environment (the thing we never go below). -#}
{% macro start_date_floor() -%}
    {{ env_var('START_DATE', '2026-09-23') }}
{%- endmacro %}

{#-
    Effective start: max(floor, requested). ISO dates sort lexicographically,
    so max() is a correct date comparison.
-#}
{% macro start_date() -%}
    {{ [start_date_floor() | trim, var('start_date', start_date_floor() | trim) | string | trim] | max }}
{%- endmacro %}

{% macro start_ts() -%}
    timestamp('{{ start_date() }}')
{%- endmacro %}

{#- Optional upper bound: empty means "up to now". -#}
{% macro end_date() -%}
    {{ var('end_date', '') }}
{%- endmacro %}

{#-
    WHERE-clause fragment bounding the source scan.

    Full refresh -> [start_ts, end_ts) if set, else [start_ts, now).
    Incremental  -> the lookback, also clamped to the floor.
-#}
{% macro source_date_filter(timestamp_column, lookback_days=3) -%}
    {% if is_incremental() %}
        and {{ timestamp_column }} >= greatest(
            {{ start_ts() }},
            timestamp_sub(current_timestamp(), interval {{ lookback_days }} day)
        )
    {% else %}
        and {{ timestamp_column }} >= {{ start_ts() }}
    {% endif %}
    {% if end_date() | trim | length > 0 %}
        and {{ timestamp_column }} < timestamp('{{ end_date() | trim }}')
    {% endif %}
{%- endmacro %}

{#-
    incremental_predicates entry: restricts the partitions insert_overwrite
    is allowed to replace, so a bad run cannot wipe history before the
    effective start.
-#}
{% macro overwrite_from_start(timestamp_column) -%}
    DBT_INTERNAL_DEST.{{ timestamp_column }} >= {{ start_ts() }}
{%- endmacro %}
