#!/bin/bash
# Idempotent BigQuery dataset bootstrap for the sample stack.
#
# Runs inside the bigquery-init compose service (gcloud SDK image).
# For the sample we use the gcloud CLI; in real life this is Terraform
# (IaC) applied via CI/CD - dataset resource, project factory,
# least-privilege service accounts, remote state. Discussion: docs/draft.md.
set -euo pipefail

if [ "${DBT_PROJECT:-}" = "your-gcp-project-id" ] || [ -z "${DBT_PROJECT:-}" ]; then
  echo "ERROR: set DBT_PROJECT (GCP project id) - e.g. in .env"
  echo "       refusing to create datasets in a placeholder/empty project"
  exit 1
fi

DATASET="${DBT_DATASET:-nansen_labels_dev}"
LOCATION="${DBT_LOCATION:-US}"

if bq --location="$LOCATION" mk --dataset "$DBT_PROJECT:$DATASET"; then
  echo "dataset $DBT_PROJECT:$DATASET created ($LOCATION)"
else
  echo "dataset $DBT_PROJECT:$DATASET already exists (or auth failed) - skipping"
fi