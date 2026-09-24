#!/bin/bash
# Idempotent BigQuery dataset bootstrap for the sample stack.
#
# Runs inside the bigquery-init compose service (gcloud SDK image).
# For the sample we use the gcloud CLI; in real life this is Terraform
# (IaC) applied via CI/CD - dataset resource, project factory,
# least-privilege service accounts, remote state. Discussion: docs/draft.md.
#
# Every bq call is explicit about --project_id: the mounted host gcloud
# config may point at a different (or deleted) default project, and a
# silent fallback to it produces cryptic "Project X has been deleted"
# errors instead of creating the dataset.
set -euo pipefail

if [ "${DBT_PROJECT:-}" = "your-gcp-project-id" ] || [ -z "${DBT_PROJECT:-}" ]; then
  echo "ERROR: set DBT_PROJECT (GCP project id) - e.g. in .env"
  echo "       refusing to create datasets in a placeholder/empty project"
  exit 1
fi

DATASET="${DBT_DATASET:-nansen_labels_dev}"
LOCATION="${DBT_LOCATION:-US}"

BQ=(bq --project_id="$DBT_PROJECT" --location="$LOCATION")

if "${BQ[@]}" show --dataset "${DBT_PROJECT}:${DATASET}" >/dev/null 2>&1; then
  echo "dataset ${DBT_PROJECT}:${DATASET} already exists - skipping"
  exit 0
fi

if ! "${BQ[@]}" mk --dataset "${DBT_PROJECT}:${DATASET}"; then
  echo "ERROR: could not create dataset ${DBT_PROJECT}:${DATASET}" >&2
  exit 1
fi

echo "dataset ${DBT_PROJECT}:${DATASET} created ($LOCATION)"
