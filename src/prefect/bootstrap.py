"""Idempotent bootstrap for the local Prefect setup.

Runs inside the init container. Safe to re-run: existing pool and
deployment are simply kept up to date.

  1. ensure the `labels-local` work pool exists (process type)
  2. register the deployment defined in prefect.yaml
"""

import asyncio
import subprocess
import sys

from prefect.client.orchestration import get_client
from prefect.client.schemas.actions import WorkPoolCreate

POOL_NAME = "labels-local"


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
    # `prefect deploy` is the standard registration path (reads prefect.yaml)
    result = subprocess.run(
        ["prefect", "deploy", "--all", "--no-prompt",
         "flows/label_pipeline.py:label_pipeline"],
        capture_output=True,
        text=True,
    )
    print(result.stdout)
    if result.returncode != 0:
        print(result.stderr, file=sys.stderr)
        raise SystemExit(result.returncode)
    print("deployment registered")


asyncio.run(ensure_pool())
register_deployment()