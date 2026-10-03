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
# Qwiklabs Assessment 3: Verify LSF Assets in GCS & LSF Master Setup
# =====================================================================
set -euo pipefail

PROJECT_ID="${1:-${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || true)}}"

if [ -z "$PROJECT_ID" ]; then
    echo "ASSESSMENT FAILED: GCP Project ID could not be determined."
    exit 1
fi

# 1. Verify GCS bucket has LSF configs, workflows, and installer archives staged
BUCKET_NAME=$(gcloud storage buckets list --project="$PROJECT_ID" --filter="name:lsf-install-bucket" --format="value(name)" --limit=1 2>/dev/null || true)
if [ -z "$BUCKET_NAME" ]; then
    echo "ASSESSMENT FAILED: GCS installation bucket not found."
    exit 1
fi

REQUIRED_GCS_OBJECTS=(
    "lsf_std_entitlement.dat"
    "lsf10.1_lsfinstall_linux_x86_64.tar.Z"
    "lsf10.1_lnx310-lib217-x86_64.tar.Z"
    "lsf10.1_lnx310-lib217-x86_64-602430.tar.Z"
    "lsf_config/setup_master.sh"
    "eda_workflow/run_eda_job.sh"
    "submit_scripts/submit_scale_10.sh"
)

for obj in "${REQUIRED_GCS_OBJECTS[@]}"; do
    if ! gcloud storage ls "gs://${BUCKET_NAME}/${obj}" --project="$PROJECT_ID" &>/dev/null; then
        echo "ASSESSMENT FAILED: Required object 'gs://${BUCKET_NAME}/${obj}' not found. Please run './upload_assets.sh'."
        exit 1
    fi
done

# 2. Verify LSF Master installation and active daemons via IAP SSH
MASTER_ZONE=$(gcloud compute instances list --project="$PROJECT_ID" --filter="name=lsf-master" --format="value(zone)" --limit=1 2>/dev/null || true)
if [ -z "$MASTER_ZONE" ]; then
    echo "ASSESSMENT FAILED: Could not locate 'lsf-master' instance."
    exit 1
fi

if ! gcloud compute ssh lsf-master \
    --project="$PROJECT_ID" \
    --zone="$MASTER_ZONE" \
    --tunnel-through-iap \
    --quiet \
    --command="test -f /opt/lsf/conf/profile.lsf && source /opt/lsf/conf/profile.lsf && lsid && bhosts" &>/dev/null; then
    echo "ASSESSMENT FAILED: LSF is not installed or daemons (lim, res, sbatchd, mbatchd) are not responding on 'lsf-master'. Please run 'sudo bash ./lsf_config/setup_master.sh' on lsf-master."
    exit 1
fi

echo "ASSESSMENT PASSED: LSF installer archives & configurations are staged in GCS, and LSF Master cluster daemons are active!"
exit 0
