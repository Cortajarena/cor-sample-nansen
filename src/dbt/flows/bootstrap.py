"""Idempotent bootstrap for the dbt worker.

Runs inside the dbt-init container (same image as the worker). Safe to
re-run: existing pool and deployment are simply kept up to date.

  1. ensure the `dbt-local` work pool exists (process type)
  2. register the deployment defined in prefect.yaml
"""

import asyncio
import os
import subprocess
import sys
import time
import urllib.request

from prefect.client.orchestration import get_client
from prefect.client.schemas.actions import WorkPoolCreate

POOL_NAME = "dbt-local"


def wait_for_server(timeout_seconds: int = 180) -> None:
    """Block until the Prefect API answers.

    There is no depends_on for `server`: it belongs to the `prefect` profile
    and compose cannot resolve a dependency on a filtered-out service, so
    bootstrapping waits for it instead.
    """
    url = os.environ.get("PREFECT_API_URL", "http://server:4200/api") + "/health"
    deadline = time.time() + timeout_seconds
    while time.time() < deadline:
        try:
            with urllib.request.urlopen(url, timeout=5) as response:
                if response.status == 200:
                    print(f"prefect api reachable at {url}")
                    return
        except OSError:
            time.sleep(2)
    raise SystemExit(f"prefect api not reachable at {url} after {timeout_seconds}s")


async def ensure_pool() -> None:
    async with get_client() as client:
        pools = await client.read_work_pools()
        if POOL_NAME in [p.name for p in pools]:
            print(f"pool '{POOL_NAME}' already exists")
            return
        # Prefect 3.x takes a WorkPoolCreate object, not name=/type= kwargs
        await client.create_work_pool(
            work_pool=WorkPoolCreate(name=POOL_NAME, type="process")
        )
        print(f"pool '{POOL_NAME}' created")


def register_deployment() -> None:
    result = subprocess.run(
        ["prefect", "deploy", "--all", "--no-prompt",
         "flows/dbt_run.py:dbt_run"],
        capture_output=True, text=True,
    )
    print(result.stdout)
    if result.returncode != 0:
        print(result.stderr, file=sys.stderr)
        raise SystemExit(result.returncode)
    print("deployment registered")


wait_for_server()
asyncio.run(ensure_pool())
register_deployment()
