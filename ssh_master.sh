#!/bin/bash
# =====================================================================
# SSH Helper for LSF Master Host (ssh_master.sh)
# =====================================================================
set -e

get_tfvar() {
    local var_name="$1"
    if [ -f "terraform/terraform.tfvars" ]; then
        grep -E "^\s*${var_name}\s*=" terraform/terraform.tfvars | awk -F'=' '{print $2}' | tr -d ' "' | head -n 1 || true
    fi
}

PROJECT_ID=$(gcloud compute instances list --filter="name=lsf-master" --format="value(project)" --limit=1 2>/dev/null || true)
PROJECT_ID="${PROJECT_ID:-$(get_tfvar "project_id")}"
ZONE=$(gcloud compute instances list --filter="name=lsf-master" --format="value(zone)" --limit=1 2>/dev/null || true)
ZONE="${ZONE:-$(get_tfvar "zone")}"

if [ -z "$ZONE" ]; then
    echo "ERROR: Could not locate lsf-master instance or zone in terraform.tfvars."
    exit 1
fi

echo "Connecting to lsf-master (Project: ${PROJECT_ID:-default}, Zone: ${ZONE}) via IAP SSH..."
gcloud compute ssh lsf-master ${PROJECT_ID:+--project="$PROJECT_ID"} --zone="$ZONE" --tunnel-through-iap "$@"
