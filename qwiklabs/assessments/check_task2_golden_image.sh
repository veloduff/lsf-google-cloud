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
# Qwiklabs Assessment 2: Verify LSF Worker Golden Image
# =====================================================================
set -euo pipefail

PROJECT_ID="${1:-${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || true)}}"
IMAGE_NAME="lsf-submit-and-worker-rocky-8-image"

if [ -z "$PROJECT_ID" ]; then
    echo "ASSESSMENT FAILED: GCP Project ID could not be determined."
    exit 1
fi

IMAGE_STATUS=$(gcloud compute images describe "$IMAGE_NAME" --project="$PROJECT_ID" --format="value(status)" 2>/dev/null || true)
IMAGE_FAMILY=$(gcloud compute images describe "$IMAGE_NAME" --project="$PROJECT_ID" --format="value(family)" 2>/dev/null || true)

if [ "$IMAGE_STATUS" != "READY" ]; then
    echo "ASSESSMENT FAILED: Custom image '$IMAGE_NAME' was not found or is not READY (status: '${IMAGE_STATUS:-NOT_FOUND}'). Please run './lsf_config/build_golden_image.sh'."
    exit 1
fi

if [ "$IMAGE_FAMILY" != "lsf-rocky-8" ]; then
    echo "ASSESSMENT FAILED: Custom image '$IMAGE_NAME' exists but does not belong to image family 'lsf-rocky-8' (found: '${IMAGE_FAMILY:-none}'). Please run './lsf_config/build_golden_image.sh' to bake the Golden Image."
    exit 1
fi

echo "ASSESSMENT PASSED: Golden Image '$IMAGE_NAME' (family: lsf-rocky-8) is READY!"
exit 0
