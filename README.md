# About

Sample solution for the [Nansen Senior Data Engineer take-home](spec.md):
the foundations of a pipeline that produces **valuable labels for blockchain
addresses**, plus a working sample of one slice: a [Uniswap V3](https://docs.uniswap.org/)
swap pipeline on Ethereum mainnet that ends in a *smart trader* datamart.

Everything runs in containers — **no Node, Python or npm on the host**. The only
host dependencies are Docker and the `gcloud` CLI.

## What's here

| Path | What |
| --- | --- |
| `spec.md` | The assignment (cleaned up) |
| `docs/draft.md` | The design document (source of truth — [published](https://cortajarena.github.io/cor-sample-nansen/draft/)) |
| `docs/slides.md` | The presentation — [Slidev](https://sli.dev), rendered via Docker |
| `docker-compose.yml` | Root compose file |
| `docker/` | Dockerfiles, one per tool |
| `src/dbt/` | dbt project: seeds, models, macros + its own Prefect worker |
| `src/prefect/` | Orchestration: server, worker, and the pipeline flow |

## Running the sample

### 1. Prerequisites

- Docker with the Compose plugin
- [`gcloud` CLI](https://cloud.google.com/sdk/docs/install)
- A GCP project with BigQuery enabled (the sample reads the *public* Ethereum
  dataset and writes to your own dataset)

### 2. Authenticate

The containers pick up Application Default Credentials from your host, so log
in once:

```bash
gcloud auth application-default login
gcloud auth application-default set-quota-project <your-gcp-project-id>
```

The second command matters: without a quota project the client libraries warn
about an undetermined project (dbt itself is fine, the auth layer is not).

### 3. Configure `.env`

```bash
cp .env.example .env
```

| Variable | Meaning |
| --- | --- |
| `DBT_PROJECT` | Your GCP project (owns the output dataset) |
| `DBT_DATASET` | Dataset dbt builds into (created automatically) |
| `DBT_LOCATION` | BigQuery location — must be `US` to match the public dataset |
| `START_DATE` | **Hard floor** for every source scan. No model ever reads before it, including backfills (the start is clamped up to it). |
| `HOST_WORKSPACE` / `HOST_HOME` | Only needed if you run the flow outside Compose |

### 4. Start the stack

Two work pools: the orchestrator (`labels-local`) and dbt (`dbt-local`). dbt
runs in its own image because it holds the BigQuery credentials — the
orchestrator just triggers it by deployment name, no docker socket involved.

```bash
docker compose --profile prefect --profile dbt up -d --build
```

- Prefect UI: <http://localhost:4200>
- Bootstrap (`init`, `dbt-init`) creates the work pools, registers the
  deployments and creates the BigQuery dataset.

### 5. Run the pipeline

```bash
# mock run - no dbt, no BigQuery (useful to check the wiring)
docker compose --profile prefect exec -T worker prefect deployment run \
  daily-label-pipeline/daily-label-pipeline

# real incremental run
docker compose --profile prefect exec -T worker prefect deployment run \
  daily-label-pipeline/daily-label-pipeline --param mock=false

# full refresh (rebuild every model)
docker compose --profile prefect exec -T worker prefect deployment run \
  daily-label-pipeline/daily-label-pipeline --param mock=false --param full_refresh=true

# bounded backfill: [start, end) - start is clamped up to START_DATE
docker compose --profile prefect exec -T worker prefect deployment run \
  daily-label-pipeline/daily-label-pipeline --param mock=false \
  --param backfill_start=2026-09-23 --param backfill_end=2026-09-23T06:00:00
```

Or trigger it from the UI. The flow runs: bronze → silver → gold → `dbt test`
→ publish (a no-op here: there is no serving layer in the sample).

### Running dbt directly

```bash
docker compose --profile dbt run --rm dbt seed      # load the two seeds
docker compose --profile dbt run --rm dbt run       # build everything
docker compose --profile dbt run --rm dbt test      # 47 tests
docker compose --profile dbt run --rm dbt parse     # validate without a warehouse
docker compose --profile dbt run --rm dbt compile   # see the generated SQL
```

> **Cost care:** these tables are huge and partitioned. Always filter the
> partition column — the same query costs **0.28 GB** with a
> `block_timestamp` filter and **456 GB** without it. `START_DATE` keeps every
> model bounded, and `dbt compile`/`parse` are free.

## The data model

```text
seeds        token_whitelist, uniswap_v3_pools
bronze       stg_ethereum__logs_uniswap_v3_swaps      # V3 Swap decoded from logs
             stg_ethereum__token_balance_deltas       # per (address, token, day)
silver       ethereum_dex_uniswap_v3__trades / __prices / __prices_1min
             ethereum_dex_uniswap_v3__prices_1h / __token_prices_1h
             ethereum_dex_uniswap_v3__balances        # MTM, flow, turnover
gold         ethereum_dex_uniswap_v3_labels__smart_traders   # 1h grid + metrics
```

Two details worth knowing before reading the code:

- **The trader is the transaction signer**, not `Swap.sender`. ~99.9% of swaps
  go through a router, so labelling on `sender` would collapse 2,376 traders
  into 187 contract addresses.
- **Returns are time-weighted.** Deposits are not alpha — stripping flows moved
  the average 24h return from +28% (pure artifact) to −1.5%.

## The presentation

The deck is `docs/slides.md`, rendered with Slidev:

```bash
# live deck with presenter notes: http://localhost:3030
docker compose --profile slides up slides

# one-shot PDF export -> docs/dist/slides.pdf
docker compose --profile slides run --rm slides-export

# static SPA build -> docs/dist/site/ (what CI deploys to GitHub Pages)
docker compose --profile slides run --rm slides-build
```

First run builds the Slidev image (Node 22 + headless Chromium for exports).

Everything is published to GitHub Pages on every push to `main`
(`.github/workflows/slides-pages.yml`) — enable it once via
**Settings → Pages → Source: GitHub Actions**:

| Path | What |
| --- | --- |
| `/` | Interactive deck, with a built-in "Download PDF" button |
| `/draft/` | The design document (HTML, with rendered Mermaid diagrams) |
| `/dbt-docs/` | dbt docs: lineage graph + model and column documentation* |

\* dbt docs need warehouse metadata, so CI generates them only when the
`GCP_SA_KEY` secret is set; otherwise that path is skipped.

## Repository layout

```text
cor-sample-nansen/
├── .env.example            # copy to .env before running anything
├── docker-compose.yml      # root compose (includes src/compose.yml)
├── docker/                 # pandoc, slidev
├── docs/
│   ├── draft.md            # design document (source of truth)
│   └── slides.md           # the presentation
├── src/
│   ├── compose.yml         # pipeline services: prefect + dbt
│   ├── dbt/                # models, macros, seeds + dbt worker flow
│   └── prefect/            # server/worker + the orchestrating flow
└── spec.md                 # the assignment
```
