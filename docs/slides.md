---
theme: seriph
title: 'Nansen: on-chain pipeline design'
info: |
  Nansen take-home assignment — Senior Data Engineer.<br/>
  Designing the foundations of a pipeline that produces valuable labels for blockchain addresses.
class: text-center
highlighter: shiki
drawings:
  persist: false
transition: slide-left
mdc: true
---

---
layout: cover
---

# Nansen: on-chain pipeline design

Foundations of a pipeline that produces **valuable labels for blockchain addresses**

Nansen — Senior Data Engineer take-home

<!--
Opening: the assignment is deliberately open-ended ("produce valuable labels"). Say up front that the interesting part is not the code, it is deciding what "valuable" means — and that this deck is the argument for that decision, with a working slice as proof.
-->

---

# The assignment

> *"Create a pipeline that produces valuable labels for blockchain addresses. These labels should be useful to an investor who wants to better understand interesting addresses on chain, and help them make smarter decisions."*

- Deliberately open-ended — it is a problem-space exercise, not a coding exercise
- Four things being assessed: architecture, user-centric design, project management, execution

<!--
Emphasise that "valuable" is undefined on purpose. Everything that follows is an attempt to define it from the user backwards. Mention the 4h timebox: the deliverable is the reasoning + one working slice.
-->

---

# What is a label?

> *The process of adding a qualitative descriptor that provides information regarding the behaviour, nature or origin of an address or address operator.*

Extends naturally to soft scores and quantiles — anything that summarises an address.

Three properties a label must have:

- **Timely** — aligned to a snapshot in time, dynamic and mutable; time is part of the data model and the grain decision
- **Actionable** — adds information you can act upon
- **Trustworthy** — inferred on-chain, or from external sources with high confidence

<!--
Timeliness is the one people forget: a label without a timestamp is a fact about "now" that silently rots. This is why every table in the sample is partitioned and every label row carries a label_date.
-->

---

# The three questions a label answers

- ***WHO is this entity?*** — exchange, treasury, protocol builder, whale, market maker, smart contract
- ***WHAT does this entity do?*** — liquidity provider, speculator, MEV-style bot, deployer, staker, router
- ***WHY should users care?*** — what makes this address worth watching

Value is defined **bottom-up**, by the consumer.

<!--
The bottom-up point is the thesis of section 1. Ask the room: who is the customer? The same address is interesting or irrelevant depending on who is looking.
-->

---

# Different users, different value

A **staking infrastructure provider** selling to funds and banks cares about:

- exchanges, treasuries, node operators, protocol deployers

…and cares very little about smart traders or spoofers. The labels are a *sales tool*.

Whereas a Nansen user is typically looking for:

- **Alpha** — risk-adjusted returns better than a traditional weighted portfolio
- **Beta** — exposure to the next move, or deliberately market-neutral
- **Sigma** — raw exposure or hedging against future volatility

<!--
Concrete illustration of the bottom-up argument. The same pipeline, different label sets, different customers. This is why the taxonomy has to be a decision, not a default.
-->

---

# Example: a dynamic label in CLOB chains

Where there is leverage and margin, we can label an address dynamically as:

```
at_risk[bool]
```

- Proxy for potential liquidations
- Combined with other labels, a leading indicator of price moves
  (whale liquidations → squeezes, cascades)
- Aggregates naturally into an API-level metric: *liquidations by price level*

<!--
Good example of "actionable" and "timely" at once: at_risk is only meaningful at a timestamp. Note this is more powerful in CLOB systems than AMMs — foreshadows the big caveat later.
-->

---

# A generic pipeline recipe

- **Research first** — validate the data source is worth it (market research, user research, stakeholders as consumers)
- **Design bottom-up** against requirements: simplicity, robustness, monitoring, scalability, data quality, backfill/DR, API fit
- **Occam's razor** — fewer components is usually more reliable; but requirements dictate architecture (event-driven backend → you add a queue; low-latency source → you adapt)
- **Then lock it**: reliable, scalable, measurable, with backfill and DR

<!--
This is section 1.2. The point to land: the pipeline design is a consequence of requirements, not of fashion.
-->

---

# Approaches: (1) entity labels from external sources

Providers like Glassnode, Arkham or Dune compile web2 information:

- reports, websites, data vendors, API aggregators
- tag addresses as exchanges, treasuries, node operators, deployers
- plus graph algorithms (UTXO chains) or heuristics (EVM) to label new addresses faster

Typical shape: `poll → normalize → transform`, with bronze + SCD-style validity
(`timestamp_from` / `timestamp_to`).

<!--
Cheap to build, high trust cost: you inherit someone else's ontology and their errors. Worth saying that external labels are a join, not a source of truth.
-->

---

# Approaches: (2) behavioural labels in EVMs

EVM chains expose behaviour directly:

- **Balances and transfers** — player size per token, long-term holder cohorts, active vs inactive
- **Contract interaction** — logs, traces; LP positioning, floating PnL, double-sided liquidity, MM patterns, staking, lending

This is where the interesting *derived* labels live — and where our sample sits.

<!--
Note the two data families: token transfers (who holds what) and logs/traces (what they did with contracts). Our sample uses both, plus transactions for the signer.
-->

---

# Approaches: (3) CLOB chains

Central limit order books (HyperCore, Jupiter) expose:

- age, spoofing, cancel rates
- double-sided liquidity, tranching
- soft labelling from order-book behaviour

**Far richer signal than an AMM** — fees are minimal, both long and short are cheap, so the universe of relevant traders is much larger.

<!--
Land the punchline: more statistical significance → more discoverable alpha. This is the honest caveat on our own sample.
-->

---

# Approaches: (4) smart money

- Rolling weighted portfolio, decoupling
- Rebalancing activity as a proxy for statistical significance
- Proxy it via rebalance / volume against nominal value
- Beta, market neutrality, VaR and vol vs BTC vol
- History

Plus insider-style signals from on-chain protocol data.

<!--
This is the section our sample actually implements a version of: portfolio-level metrics rather than per-trade heuristics.
-->

---

# Approaches: (5) ML based labelling

*Open item in the draft (todo_3).*

Candidate directions once the feature tables exist:

- clustering addresses by behaviour
- supervised labels where we have trusted examples (external entity tags)
- anomaly detection for bots / wash activity

<!--
Be honest: not implemented, and deliberately so within the timebox. Frame it as the natural next step once the silver feature layer exists.
-->

---

# The sample: motivation

A batch, partition-based incremental pipeline that labels active Uniswap traders as
**smart traders** — but not in the conventional way.

Instead of "who bought early", we use measures from quant finance / MPT:

- **Activity** — turnover in the top X%; swaps, positions, traded assets
- **Size** — whale / quantile characterisation; skin in the game
- **Pure returns** — PnL over time as alpha
- **Beta to BTC** — exposure and market neutrality
- **Sharpe / Sortino** — risk-adjusted returns with frequent turnover

<!--
Key line: all of these are ROLLING, timestamped features at the chosen grain. The datamart computes them and leaves "what is a smart trader" as a discussion — we expose the inputs, we do not hardcode the verdict.
-->

---

# Why this is useful

Users can build **synthetic (virtual) portfolios**:

- a `$NANSEN500` index: a dynamically weighted sum of traders, rebalanced
- tunable appetite for market neutrality, long/shortness
- a rebalancing engine / agent keeps users following the synthetic portfolio

Backend shape: `on_request` service for dynamic needs, or periodic pre-computed jobs.

<!--
This is the product payoff, and the reason the metrics are per-address and timestamped rather than a single score.
-->

---

# The honest caveat

> This kind of labelling is **much more powerful in limit order book systems** than in an AMM pool protocol.

- CLOB: tiny fees, cheap long *and* short (shorting on Uniswap is complex)
- → far larger universe of relevant traders
- → more statistical significance → more discoverable alpha

Our sample is an AMM, so treat the numbers as **illustrative**.

<!--
Do not skip this slide. Volunteering the weakness is the strongest credibility move in the deck, and it is true: ~30h of data on 10 pools.
-->

---

# System design: the components

- **Cluster** (Kubernetes) + IaC (Terraform) + Helm; artifact registry
- **Services** — polling, scrapers, stream listeners, RPC nodes; orchestrated by Airflow/Prefect, with sync backups for backfill
- **Cold storage** (S3/GCS) — data as raw as possible, Parquet + Apache Iceberg catalog
- **Query engine + semantic layer** (dbt, Spark) + data quality (dbt tests, Great Expectations)
- **API layer** — cache (Redis); engine choice decides whether it can serve directly
- **Monitoring** — Grafana/Prometheus, standardised JSONL logs

<!--
Note the coupling decision: BigQuery/Snowflake/ClickHouse couple storage+engine; Trino/Databricks run on Iceberg/Delta in your own storage. That choice propagates into the API layer.
-->

---

# System design (visual)

![platform-architecture](/diagrams/platform-architecture.svg)

<!--
Walk it left to right: everything lands in cold storage raw, dbt is the only thing that models it, and the orchestrator sits ABOVE both ingestion and transformation. Monitoring is dashed because it is cross-cutting, not a stage.
-->

---

# Orchestration in the sample

![orchestration-pools](/diagrams/orchestration-pools.svg)

<!--
The key edge is run_deployment: the orchestrator never shells out, never mounts a docker socket, and holds no credentials. It just asks for a deployment by name and waits. Show the two pool names.
-->

---

# What the sample actually runs

- **Docker Compose**, two Prefect work pools:
  - `labels-local` — the orchestrator (no dbt, no credentials, no docker socket)
  - `dbt-local` — dbt in its own image, holding the BigQuery credentials
- The orchestrator triggers dbt by **deployment name** and waits (`run_deployment`)
- Code is **copied into images**, not bind-mounted — what runs is what is in git
- Bounded by a single env var: `START_DATE`

<!--
Explain why two images: dependency trees clash, and only the dbt container should hold credentials. The alternative (docker socket / sibling containers) is fragile — mention you tried and rejected it.
-->

---

# Transformation: medallion

Implemented in dbt as a **semantic layer**:

| Layer | Role |
| --- | --- |
| **Bronze** (staging) | low level entity creation / normalization, 1:1 with source |
| **Silver** | abstraction and grain that favour later metrics; unified schemas |
| **Gold** (datamart) | metrics and direct product value, tightly coupled to the API layer |

<!--
Silver is where the "unified schema" idea lives: one trades schema across exchanges/chains. In our sample that shows up as token-grain prices unpivoted out of pool-grain bars.
-->

---

# The graph we built

![model-dag](/diagrams/model-dag.svg)

<!--
Point out the two non-obvious edges: transactions feeds the signer (that is the router fix), and swaps feed the balance watchlist (we only track balances for addresses we saw trade). Everything else is a straight bronze→silver→gold chain.
-->

---

# Bronze

- **`stg_ethereum__logs_uniswap_v3_swaps`**
  - decode Uniswap V3 `Swap` events straight from raw logs
  - join `transactions` to resolve the **signer**
- **`stg_ethereum__token_balance_deltas`**
  - per (address, token, day) signed deltas
  - for every address that interacted with the protocol

Ideally also LP positions (V3 positions are NFTs) — **not built**.

<!--
Two decoding facts worth mentioning if asked: logs.data keeps the 0x prefix (offset by 2 silently corrupts every parameter), and V3 amounts are signed int256 needing two's complement — both failed silently and were caught by comparing against a Python decode of the raw payload.
-->

---

# Silver

- **`_v3__trades`** — one row per swap, direction resolved from the amount sign
- **`_v3__prices`** — one price observation per swap, from `sqrtPriceX96`
- **`_v3__prices_1min` / `_v3__prices_1h`** — minute and hourly bars
- **`_v3__token_prices_1h`** — one USD price per token per hour (the MTM target)
- **`_v3__balances`** — running balance per (address, token) on an hourly grid, with `balance_usd`, `flow_usd`, `turnover_usd`

<!--
Token prices are unpivoted from pool bars because you cannot mark a portfolio with pool-grain prices. Stablecoins are pinned at 1.0 — USDT is always the quote leg so no swap ever prices it.
-->

---

# Gold: smart traders

One row per **(address, hour)**:

- portfolio value = sum of MTM balances across tokens
- logreturns, and a trailing **24h** window:
  - geometric return
  - **beta** and **alpha** vs the benchmark
  - **Sharpe** and **Sortino**
  - turnover ratio (trailing turnover / portfolio value)
- `n_obs` exposed on every row — read it before trusting anything

<!--
n_obs is the honesty valve: with ~30h of sample data most rows are partial windows. Say plainly that the definitions are the deliverable, not the numbers.
-->

---

# Deposits are not alpha

- A portfolio moves for two unrelated reasons: **performance** and **flows**
  (`V_end - V_start = PnL + net_flows`)
- An address holding 100 USDT that receives 10,000 shows **+10,000%** for doing nothing
- In our data this is not hypothetical: computing returns on raw value gave
  **+28%** average 24h return — pure artifact
- Fix: **time-weighted return**, `r_t = (V_t - F_t) / V_(t-1) - 1`
- After the correction: **−1.5%**, with BTC at −2.4%

<!--
This is the slide to linger on. It is the single most common way on-chain "smart money" leaderboards are wrong, and our own first run was wrong in exactly this way.
-->

---

# Pricing: why V3

- V3 emits the pool price in the event itself: `sqrtPriceX96` → `(sqrtPriceX96 / 2^96)^2`
- On V2, the only price in `Swap` is `amountOut / amountIn` — an **execution** price, carrying fee and that trade's own price impact
- V2 needs `Sync(reserve0, reserve1)` to get a proper mid; V3 gives it away
- We still keep `amount_out_per_amount_in` — that is what the trader *paid*, which is what realised PnL needs

<!--
Sanity check we actually ran: the sqrtPriceX96 mid (2694.16) sits just inside the execution price from the amounts (2702.23). The gap is the pool fee.
-->

---

# Scope: what we deliberately narrowed

- **10 whitelisted pools**, not every V3 pool — keeps scan and storage bounded
- **All quoted against USDT** — the pool price *is* USD, no oracle, no second hop
- Balances only for addresses that **swapped** (a watchlist), not every holder
- `START_DATE` bounds everything; a backfill start is **clamped up** to it

Production would read the deepest pool per token and normalise through a
`WETH/USDT` leg, and would derive pools from `PoolCreated` instead of seeding them.

<!--
The USDT-quote choice is a trade-off: SHIB/WSOL/PEPE have far deeper WETH pools (10-50x more swaps) that we do not read. Say it — it is in the appendix.
-->

---

# Balances: deltas, not snapshots

- Store **per-day deltas**; `insert_overwrite` replaces whole partitions, so a cumulative balance would have to be recomputed from all history every run
- Production would go further: a true **delta (change-data) table**, event-sourced, storage ∝ activity
- Known limitation: balances start at `START_DATE`, not genesis
  - pre-window holders show **negative** balances (≈ −60M USD total in the sample)
  - those rows return **null**, never a fabricated number
  - fixing it = a **~601 GB** full replay (measured)

<!--
The 601 GB figure is because token_transfers is a VIEW with no clustering: neither a token nor an address filter prunes. We chose to document rather than pay it.
-->

---

# What is still missing

- **LP positions** — V3 liquidity is an ERC-721 position NFT; needs `Mint`/`Burn`/`Collect` plus position ownership, a different model entirely
- **A pools model** — derive pools from the factory's `PoolCreated` events instead of a hand-maintained seed
- **Real BTC benchmark** — we use the WBTC/USDT pool price as a proxy (WBTC ≠ BTC)
- **Realised PnL** from round trips — exact without opening balances; the natural primary metric
- **Serving layer** — no API/promotion in the sample; the datamart *is* the surface

<!--
Frame these as deliberate scope cuts with a known shape, not as unknowns. "I know what the next three models are" is a stronger close than "we ran out of time".
-->

---

# Cost discipline on public datasets

- These tables are **huge and partitioned** — filter the partition column, always
- Same query over `accounts_state`:
  - **0.28 GB** with a `block_timestamp` filter
  - **456.73 GB** without it → **1,642×**
- `--dry_run` first (free), every time
- Downstream models only touch our own tables (~70k rows, single-digit MiB)
- Total spend for the whole sample: **~11 GiB**

<!--
Nice operational detail: one careless query burns half the free tier. The rule lives in ONE macro (source_date_filter), which is why it holds.
-->

---

# The label: signer, not sender

- `Swap.sender` is the **pool caller** — for ~99.9% of swaps that is a router (SwapRouter02, Universal Router…)
- `Swap.recipient` is who received the tokens
- The **signer** (`transactions.from_address`) is the trader

Measured on 7,184 swaps:

| | Addresses |
| --- | --- |
| pool callers (`sender`) | 187 |
| signers (real traders) | 2,376 |

Label rows went from 413 → 2,900 once fixed.

<!--
This was the biggest correctness bug in the sample and it was invisible: the labels looked fine, they were just about routers. Worth telling as a story.
-->

---

# By the numbers

| | |
| --- | --- |
| Models | 9 (2 bronze, 5 silver, 1 gold, +2 seeds) |
| Tests | 47 passing |
| Swaps decoded | 7.2k |
| Traders labelled | 2,653 |
| Data scanned | ~11 GiB (all inside the free tier) |
| Full graph run | ~30s end to end |

Everything runs with two commands: start the stack, trigger the deployment.

<!--
Keep this short. The numbers are evidence the design works, not the point of the exercise.
-->

---

# Backlog

- Explore and debug tables; sample charts (`pnl_1m`)
- Proper data quality and freshness tests
- Customisable backfill tasks in Prefect (full refresh vs batched)
- Realised PnL, LP positions, pools model, serving layer

<!--
Close the loop with section 3.1's backlog so the deck and the document agree.
-->

---
layout: end
---

# Thank you

Walkthrough & discussion

<!--
Close on the thesis: labels are only valuable relative to a user, so the pipeline is designed backwards from the question "is this trader any good?" — and every modelling decision (signer, time-weighted returns, hourly grid, USDT quote) falls out of that.
-->
