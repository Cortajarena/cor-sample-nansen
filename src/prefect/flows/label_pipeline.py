"""
Daily address-label pipeline.

Stages:
  1. extract   - bronze: staging models (V3 swap logs, balance deltas)
  2. transform - silver: trades, prices, hourly bars, balances
  3. label     - gold: smart trader metrics
  4. test      - dbt test
  5. publish   - promote to the serving layer (no-op in the sample)

How dbt runs: it does not run here. dbt lives in its own image with its own
Prefect worker on the `dbt-local` pool (src/dbt). This flow hands work over
with `run_deployment` and waits for the result - so the orchestrator needs
neither dbt, nor BigQuery credentials, nor a docker socket.

In an ELT layout there is no separate "copy the data" step: dbt reads the
public Ethereum dataset through `source()`, so the staging models *are* the
extract.

Window control:
  * `full_refresh` rebuilds models from scratch instead of incrementally.
  * `backfill_start` / `backfill_end` bound the run to [start, end).
  * START_DATE is a hard floor set in the environment - a backfill start
    is clamped UP to it, so no run can ever read before it. See
    macros/incremental/date_window.sql.
"""

import json

from prefect import flow, get_run_logger, task
from prefect.deployments.flow_runs import run_deployment

DBT_DEPLOYMENT = "dbt-run/dbt-run"


def _log(msg: str) -> None:
    get_run_logger().info(msg)


def _dbt_args(
    stage: list[str],
    full_refresh: bool,
    backfill_start: str | None,
    backfill_end: str | None,
) -> list[str]:
    """Build the dbt argument list for one stage."""
    args = ["run", "--select", *stage]
    if full_refresh:
        args.append("--full-refresh")

    window = {}
    if backfill_start:
        window["start_date"] = backfill_start
    if backfill_end:
        window["end_date"] = backfill_end
    if window:
        # compact separators: no spaces for the vars payload
        args += ["--vars", json.dumps(window, separators=(",", ":"))]
    return args


def _run_dbt(stage: list[str], args: list[str]) -> None:
    """Hand a dbt command to the dbt deployment and wait for it."""
    _log(f"{stage}: dbt {' '.join(args)}")
    flow_run = run_deployment(
        name=DBT_DEPLOYMENT,
        parameters={"dbt_args": args},
        timeout=0,
    )
    state = flow_run.state
    if state is not None and state.is_failed():
        raise RuntimeError(f"dbt {' '.join(args)} failed: {state.message}")


@task(retries=2, retry_delay_seconds=30)
def extract(
    mock: bool,
    full_refresh: bool,
    backfill_start: str | None,
    backfill_end: str | None,
) -> dict:
    """Bronze: staging models (the extract, in an ELT pipeline)."""
    if mock:
        _log("MOCK extract: pulling new blocks from bigquery-public-data ...")
        return {"mock": True}

    args = _dbt_args(["staging"], full_refresh, backfill_start, backfill_end)
    _run_dbt("extract", args)
    return {"stage": "staging"}


@task
def transform(
    mock: bool,
    full_refresh: bool,
    backfill_start: str | None,
    backfill_end: str | None,
) -> dict:
    """Silver: trades, prices, hourly bars, balances."""
    if mock:
        _log("MOCK transform: dbt run - trades, prices, balances")
        return {"mock": True}

    args = _dbt_args(["transformation"], full_refresh, backfill_start, backfill_end)
    _run_dbt("transform", args)
    return {"stage": "transformation"}


@task
def label(
    mock: bool,
    full_refresh: bool,
    backfill_start: str | None,
    backfill_end: str | None,
) -> dict:
    """Gold: smart trader metrics."""
    if mock:
        _log("MOCK label: smart trader metrics")
        return {"mock": True}

    args = _dbt_args(["datamarts"], full_refresh, backfill_start, backfill_end)
    _run_dbt("label", args)
    return {"stage": "datamarts"}


@task
def test(
    mock: bool,
    full_refresh: bool,
    backfill_start: str | None,
    backfill_end: str | None,
) -> dict:
    """dbt test - fail loudly, never quietly."""
    if mock:
        _log("MOCK test: all tests green")
        return {"mock": True}

    _run_dbt("test", ["test"])
    return {"stage": "test"}


@task
def publish(mock: bool) -> dict:
    """
    Promote labels to the serving layer (swap/alias pattern).

    Out of scope for the sample: there is no serving store here, so labels
    are queried straight from the datamart. In a real deployment this is
    where the alias flips and the API cache is warmed - see docs/draft.md.
    """
    if not mock:
        _log("publish: no serving layer in the sample - datamart is the "
             "serving surface (see docs/draft.md section 3)")
        return {"promoted": False, "reason": "no serving layer in the sample"}

    _log("MOCK publish: labels promoted to serving tables, API cache warm")
    return {"promoted": True}


@flow(name="daily-label-pipeline", log_prints=True)
def label_pipeline(
    mock: bool = True,
    full_refresh: bool = False,
    backfill_start: str | None = None,
    backfill_end: str | None = None,
) -> dict:
    """
    One orchestrated run of the label pipeline (mock by default).

    Examples:
        label_pipeline()                       # incremental, no-op mock
        label_pipeline(mock=False)             # normal incremental run
        label_pipeline(mock=False, full_refresh=True)          # rebuild
        label_pipeline(mock=False, backfill_start="2026-09-23",
                       backfill_end="2026-09-23T06:00:00")     # 6h backfill
    """
    window = f"[{backfill_start or 'START_DATE'}, {backfill_end or 'now'})"
    _log(f"daily-label-pipeline starting (mock={mock}, "
         f"full_refresh={full_refresh}, window={window})")

    stats = {
        "extract": extract(mock, full_refresh, backfill_start, backfill_end),
        "transform": transform(mock, full_refresh, backfill_start, backfill_end),
        "label": label(mock, full_refresh, backfill_start, backfill_end),
        "test": test(mock, full_refresh, backfill_start, backfill_end),
        "publish": publish(mock),
    }
    _log(f"daily-label-pipeline done: {stats}")
    return stats


if __name__ == "__main__":
    label_pipeline()
