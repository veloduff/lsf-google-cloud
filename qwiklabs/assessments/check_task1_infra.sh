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
# Qwiklabs Assessment 1: Verify Hybrid Cloud Terraform Infrastructure
# =====================================================================
set -euo pipefail

PROJECT_ID="${1:-${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || true)}}"

if [ -z "$PROJECT_ID" ]; then
    echo "ASSESSMENT FAILED: GCP Project ID could not be determined."
    exit 1
fi

# 1. Verify VPC networks exist
for vpc in lsf-onprem-vpc lsf-cloud-vpc; do
    if ! gcloud compute networks describe "$vpc" --project="$PROJECT_ID" &>/dev/null; then
        echo "ASSESSMENT FAILED: VPC network '$vpc' was not found. Please run 'terraform apply' in the terraform/ directory."
        exit 1
    fi
done

# 2. Verify VPC Network Peering is ACTIVE
PEERING_STATE=$(gcloud compute networks peerings list --network="lsf-onprem-vpc" --project="$PROJECT_ID" --format="value(peerings.state)" 2>/dev/null || true)
if [[ "$PEERING_STATE" != *"ACTIVE"* ]]; then
    echo "ASSESSMENT FAILED: VPC Peering between 'lsf-onprem-vpc' and 'lsf-cloud-vpc' is not ACTIVE."
    exit 1
fi

# 3. Verify Cloud DNS Peering Zones exist
for zone_name in cloud-dns-peering cloud-reverse-dns-peering; do
    if ! gcloud dns managed-zones describe "$zone_name" --project="$PROJECT_ID" &>/dev/null; then
        echo "ASSESSMENT FAILED: Cloud DNS peering zone '$zone_name' was not found."
        exit 1
    fi
done

# 4. Verify GCS Installation Bucket exists
BUCKET_URI=$(gcloud storage buckets list --project="$PROJECT_ID" --filter="name:lsf-install-bucket" --format="value(storage_url)" --limit=1 2>/dev/null || true)
if [ -z "$BUCKET_URI" ]; then
    echo "ASSESSMENT FAILED: GCS bucket 'lsf-install-bucket-*' was not found."
    exit 1
fi

# 5. Verify lsf-master and lsf-submit VMs are RUNNING
for vm in lsf-master lsf-submit; do
    VM_STATUS=$(gcloud compute instances list --project="$PROJECT_ID" --filter="name=${vm}" --format="value(status)" --limit=1 2>/dev/null || true)
    if [ "$VM_STATUS" != "RUNNING" ]; then
        echo "ASSESSMENT FAILED: Compute Engine instance '$vm' is not RUNNING (current status: '${VM_STATUS:-NOT_FOUND}')."
        exit 1
    fi
done

echo "ASSESSMENT PASSED: Hybrid VPCs, VPC Peering, Cloud DNS Peering, GCS Bucket, and On-Premises VMs (lsf-master & lsf-submit) are deployed and running!"
exit 0
