#!/bin/bash
# Copyright 2026 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# =====================================================================
# SSH Helper for LSF Master Host (ssh_master.sh)
# =====================================================================
set -e

get_tfvar() {
    local var_name="$1"
    if [ -f "terraform/terraform.tfvars" ]; then
        grep -E "^\s*${var_name}\s*=" terraform/terraform.tfvars | awk -F'=' '{print $2}' | sed 's/#.*//' | tr -d ' "' | head -n 1 || true
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
if [ -n "$PROJECT_ID" ]; then
    gcloud compute ssh lsf-master --project="$PROJECT_ID" --zone="$ZONE" --tunnel-through-iap "$@"
else
    gcloud compute ssh lsf-master --zone="$ZONE" --tunnel-through-iap "$@"
fi
