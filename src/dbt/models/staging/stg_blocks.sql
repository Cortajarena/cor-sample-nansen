-- Minimal staging model: prove the source wiring works.
-- (dbt needs at least one model for `dbt parse`/`dbt compile` to be useful.)

SELECT
    block_number,
    block_timestamp,
    block_hash
FROM {{ source('ethereum_mainnet', 'blocks') }}
LIMIT 0