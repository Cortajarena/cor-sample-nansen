"""
Daily address-label pipeline - MOCKUP.

Runnable skeleton: every stage executes in mock mode (default) and logs
what it *would* do, plus plausible fake stats. Set mock=False to enforce
real implementations later - stages then raise NotImplementedError.

Stages:
  1. extract   - incrementally pull new blocks / transactions / token
                 transfers from bigquery-public-data into our dataset
  2. transform - dbt run: staging -> balances -> MTM / PnL series
  3. label     - apply labeling rules (confidence + provenance + history)
  4. test      - dbt test: freshness, uniqueness, coverage assertions
  5. publish   - promote labels to the serving tables
"""

from prefect import flow, get_run_logger, task


def _log(msg: str) -> None:
    get_run_logger().info(msg)


@task(retries=2, retry_delay_seconds=30)
def extract(mock: bool) -> dict:
    """Incremental extract from the public dataset (by block range)."""
    if not mock:
        raise NotImplementedError("extract: real implementation pending")
    _log("MOCK extract: pulling new blocks from bigquery-public-data ...")
    _log("MOCK extract: 1_842 blocks, 121_533 txs, 305_417 token transfers")
    return {"blocks": 1_842, "txs": 121_533, "transfers": 305_417}


@task
def transform(mock: bool) -> dict:
    """Trigger `dbt run`: staging -> balances -> MTM / PnL series."""
    if not mock:
        raise NotImplementedError("transform: real implementation pending")
    _log("MOCK transform: dbt run - stg_* -> balances -> mtm_series -> pnl_series")
    _log("MOCK transform: 14 models built, 3_112 wallets marked to market")
    return {"models": 14, "wallets": 3_112}


@task
def label(mock: bool) -> dict:
    """Labeling rules -> labels + labels_history tables."""
    if not mock:
        raise NotImplementedError("label: real implementation pending")
    _log("MOCK label: smart_money -> 37 new, 4 downgraded (last_seen aging)")
    _log("MOCK label: whale -> 211, mev_bot -> 89")
    _log("MOCK label: confidence + provenance + history written")
    return {"smart_money": 37, "whale": 211, "mev_bot": 89}


@task
def test(mock: bool) -> dict:
    """Trigger `dbt test` - pipeline fails loudly, never quietly."""
    if not mock:
        raise NotImplementedError("test: real implementation pending")
    _log("MOCK test: 42 tests - uniqueness, confidence bounds, freshness, coverage")
    _log("MOCK test: all green")
    return {"tests": 42, "failed": 0}


@task
def publish(mock: bool) -> dict:
    """Promote labels to the serving layer (swap/alias pattern)."""
    if not mock:
        raise NotImplementedError("publish: real implementation pending")
    _log("MOCK publish: labels promoted to serving tables, API cache warm")
    return {"promoted": True}


@flow(name="daily-label-pipeline", log_prints=True)
def label_pipeline(mock: bool = True) -> dict:
    """One orchestrated run of the label pipeline (mock by default)."""
    _log(f"daily-label-pipeline starting (mock={mock})")
    stats = {
        "extract": extract(mock),
        "transform": transform(mock),
        "label": label(mock),
        "test": test(mock),
        "publish": publish(mock),
    }
    _log(f"daily-label-pipeline done: {stats}")
    return stats


if __name__ == "__main__":
    label_pipeline()