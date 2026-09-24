{#-
    ABI decoding helpers - pure SQL, no UDFs, no external JS libraries.

    The reference implementation at p2p-env-build decodes with a BigQuery JS
    UDF that pulls ethjs-abi from a GCS bucket. That works, but it adds a
    runtime dependency we cannot pin or review, so the sample decodes inline
    instead. Everything here is deterministic BigQuery SQL.

    Event layout (EVM):
      topics[0]            = keccak256(event signature)
      topics[1..3]         = indexed params, 32-byte words
      data                 = concatenated 32-byte words, one per non-indexed
                             param, in declaration order

    Number handling: CAST('0x..' AS INT64) works but overflows silently
    (SAFE_CAST -> NULL) above 2^63-1, and token amounts are uint112
    (1e6 of an 18-decimal token is 1e24). So hex_to_uint falls back to
    splitting the word into two 15-hex-digit (60-bit) halves and rebuilding
    it in BIGNUMERIC, which is exact up to 2^120 - far past uint112.
-#}

{#-
    Word `i` (0-based) of an event's non-indexed data payload.

    +3, not +1: in this dataset `logs.data` KEEPS the 0x prefix, so the
    payload is 2 + 64*N characters. Off by two here silently shifts every
    parameter and produces plausible-looking garbage (found the hard way:
    a WETH/USDT price came out as 1.97e96 instead of ~4e-9).
-#}
{% macro abi_word(data_expr, i) -%}
    substr({{ data_expr }}, {{ i * 64 + 3 }}, 64)
{%- endmacro %}

{#- An indexed `address` param: last 20 bytes (40 hex chars) of the topic. -#}
{% macro abi_address_from_topic(topics_expr, i) -%}
    lower(concat('0x', substr({{ topics_expr }}[safe_offset({{ i }})], 27, 40)))
{%- endmacro %}

{#- A non-indexed `address` param: last 20 bytes of its 32-byte word. -#}
{% macro abi_address_from_word(data_expr, i) -%}
    lower(concat('0x', substr({{ abi_word(data_expr, i) }}, 25, 40)))
{%- endmacro %}

{#-
    uintN (N <= 120) param -> BIGNUMERIC.
    Fast path for values that fit in INT64; chunked fallback otherwise.
-#}
{% macro hex_to_uint(word_expr) -%}
    coalesce(
        cast(safe_cast(concat('0x', {{ word_expr }}) as int64) as bignumeric),
        cast(
            safe_cast(concat('0x', substr({{ word_expr }}, -30, 15)) as int64
        ) as bignumeric) * cast('1152921504606846976' as bignumeric)
        + cast(
            safe_cast(concat('0x', substr({{ word_expr }}, -15, 15)) as int64
        ) as bignumeric)
    )
{%- endmacro %}

{#-
    Low 128 bits of a word -> BIGNUMERIC (exact to 2^128).

    Needed because Uniswap V3 amounts are int256: the low 128 bits of a
    two's complement value are enough to recover the magnitude of anything
    a token amount can hold (token amounts are way below 2^128).
-#}
{% macro hex_to_uint128(word_expr) -%}
    cast(safe_cast(concat('0x', substr({{ word_expr }}, 1, 2)) as int64)
        as bignumeric)
        * cast('1329227995784915872903807060280344576' as bignumeric)
    + cast(safe_cast(concat('0x', substr({{ word_expr }}, 3, 15)) as int64)
        as bignumeric)
        * cast('1152921504606846976' as bignumeric)
    + cast(safe_cast(concat('0x', substr({{ word_expr }}, 18, 15)) as int64)
        as bignumeric)
{%- endmacro %}

{#-
    int256 param -> BIGNUMERIC (signed).

    BigQuery has no hex->int for >64 bits, and two's complement cannot be
    done by truncation. So: the top nibble tells us the sign, and for a
    negative value the magnitude is 2^128 - (low 128 bits).
-#}
{% macro hex_to_int256(word_expr) -%}
    {%- set low128 = hex_to_uint128('substr(' ~ word_expr ~ ', -32)') -%}
    if(
        lower(substr({{ word_expr }}, 1, 1))
            in ('8', '9', 'a', 'b', 'c', 'd', 'e', 'f'),
        -- NB: the parentheses around the magnitude are load bearing.
        -- `2^128 - a*2^120 + b*2^60 + c` binds as
        -- `(2^128 - a*2^120) + b*2^60 + c`, which double counts the low
        -- terms and returns something 1e17 times too large - and still
        -- looks like a plausible number, so it fails silently.
        -(
            cast('340282366920938463463374607431768211456' as bignumeric)
            - ( {{ low128 }} )
        ),
        {{ low128 }}
    )
{%- endmacro %}
