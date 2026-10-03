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
# Qwiklabs Assessment 4: Verify Dynamic Cloud Bursting & Auto-Scaling
# =====================================================================
set -euo pipefail

PROJECT_ID="${1:-${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || true)}}"

if [ -z "$PROJECT_ID" ]; then
    echo "ASSESSMENT FAILED: GCP Project ID could not be determined."
    exit 1
fi

MASTER_ZONE=$(gcloud compute instances list --project="$PROJECT_ID" --filter="name=lsf-master" --format="value(zone)" --limit=1 2>/dev/null || true)
if [ -z "$MASTER_ZONE" ]; then
    echo "ASSESSMENT FAILED: Could not locate 'lsf-master' instance."
    exit 1
fi

# Check if dynamic worker instances exist in GCE OR if scale_10_hosts is recorded in LSF event logs / active jobs
WORKER_COUNT=$(gcloud compute instances list --project="$PROJECT_ID" --filter="name~^compute- OR labels.environment=lsf-hybrid-cloud AND -name:(lsf-master lsf-submit lsf-golden-build)" --format="value(name)" 2>/dev/null | wc -l || echo "0")

LSF_SCALING_EVIDENCE=$(gcloud compute ssh lsf-master \
    --project="$PROJECT_ID" \
    --zone="$MASTER_ZONE" \
    --tunnel-through-iap \
    --quiet \
    --command="grep -l 'scale_10_hosts' /opt/lsf/work/eda_cluster/logdir/lsb.events* 2>/dev/null || (source /opt/lsf/conf/profile.lsf && bjobs -u all -a 2>/dev/null | grep 'scale_10_hosts') || true" 2>/dev/null || true)

if [ "$WORKER_COUNT" -eq 0 ] && [ -z "$LSF_SCALING_EVIDENCE" ]; then
    echo "ASSESSMENT FAILED: No 'scale_10_hosts' cloud-bursting job or dynamic worker instances detected. Please run './submit_scale_10.sh' from '/home/lsfadmin/submit_scripts' on lsf-submit."
    exit 1
fi

echo "ASSESSMENT PASSED: Dynamic cloud bursting job ('scale_10_hosts') and LSF Resource Connector auto-scaling verified!"
exit 0
