"""Container healthcheck: hit the Prefect API until it answers.

Used by the compose `server` service. Exits 0 when healthy.
"""

import os
import sys
import time
import urllib.request

URL = os.environ.get(
    "PREFECT_HEALTHCHECK_URL", "http://localhost:4200/api/health"
)
DEADLINE_SECONDS = 300

deadline = time.time() + DEADLINE_SECONDS
while time.time() < deadline:
    try:
        with urllib.request.urlopen(URL, timeout=5) as response:
            if response.status == 200:
                sys.exit(0)
    except OSError:
        time.sleep(2)

sys.exit(1)