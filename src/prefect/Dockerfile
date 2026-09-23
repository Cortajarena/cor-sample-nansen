# ---------------------------------------------------------------------------
# Prefect subproject - orchestration for the label pipeline
#
#   build : docker build -t nansen-prefect src/prefect
#   run   : docker run --rm nansen-prefect <prefect args> (ENTRYPOINT `prefect`)
#
# In compose (root docker-compose.yml, profile "prefect"):
#   server  - API + UI on :4200
#   init    - one-shot: ensure the local work pool exists
#   worker  - polls the pool for flow runs
# ---------------------------------------------------------------------------
FROM python:3.12-slim

WORKDIR /opt/prefect

# requirements first for layer caching, then the project skeleton
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

ENTRYPOINT ["prefect"]