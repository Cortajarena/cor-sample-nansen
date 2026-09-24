"""
dbt runner flow.

Lives in the dbt image, on its own Prefect work pool (`dbt-local`). The
orchestrating pipeline does not shell out to docker or know anything about
containers - it calls this deployment with `run_deployment` and waits.

Why separate: dbt and Prefect have heavy, partly incompatible dependency
trees, and the dbt container is the only place that holds BigQuery
credentials. Keeping one toolchain per image and letting Prefect do the
handoff is cheaper than coupling them.

`dbt_args` is a LIST so that things like --vars JSON survive intact: a
single string would have to be re-split on whitespace and any quoted value
containing spaces would break.
"""

import subprocess

from prefect import flow, get_run_logger

# the dbt project is mounted/copied here (src/compose.yml)
PROJECT_DIR = "/usr/src/dbt"


@flow(name="dbt-run", log_prints=True)
def dbt_run(dbt_args: list[str] | None = None) -> dict:
    """Run `dbt <dbt_args>` and fail the flow run if dbt fails."""
    logger = get_run_logger()
    args = list(dbt_args) if isinstance(dbt_args, list) else (dbt_args or "run").split()
    cmd = ["dbt", *args]
    logger.info(f"dbt: {' '.join(cmd)} (cwd={PROJECT_DIR})")

    result = subprocess.run(cmd, cwd=PROJECT_DIR, capture_output=True, text=True)

    for line in (result.stdout or "").splitlines():
        logger.info(line)
    for line in (result.stderr or "").splitlines():
        logger.warning(line)

    if result.returncode != 0:
        raise RuntimeError(f"dbt {' '.join(cmd)} failed: {result.returncode}")

    return {"args": args, "exit_code": result.returncode}
