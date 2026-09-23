# ---------------------------------------------------------------------------
# dbt subproject - nansen_labels
#
# Custom image (no prebuilt dbt image): python-slim + pinned adapter from
# requirements.txt, so the toolchain is fully ours and reproducible.
#
#   build : docker build -t nansen-dbt src/dbt
#   run   : docker run --rm nansen-dbt <dbt args>   (ENTRYPOINT is `dbt`)
#           e.g. docker run --rm nansen-dbt parse
# ---------------------------------------------------------------------------
FROM python:3.12-slim

# git: required by `dbt deps` (dbt packages install from git repos)
RUN apt-get update \
    && apt-get install -y --no-install-recommends git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /usr/src/dbt

# requirements first for layer caching, then the project skeleton
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# Everything runs as `dbt <command>`; swap in compose later
ENTRYPOINT ["dbt"]
CMD ["--help"]