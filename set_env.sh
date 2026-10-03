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
# Shell Environment Variable Auto-Exporter (set_env.sh)
# =====================================================================
# Usage: source ./set_env.sh
# Reads terraform/terraform.tfvars and exports TF_VAR_* environment
# variables into the active shell session.
# =====================================================================

if [ ! -f "terraform/terraform.tfvars" ]; then
    echo "ERROR: terraform/terraform.tfvars not found."
    return 1 2>/dev/null || exit 1
fi

TF_PROJECT_ID=$(grep -E "^\s*project_id\s*=" terraform/terraform.tfvars | awk -F'=' '{print $2}' | sed 's/#.*//' | tr -d ' "' | head -n 1)
TF_REGION=$(grep -E "^\s*region\s*=" terraform/terraform.tfvars | awk -F'=' '{print $2}' | sed 's/#.*//' | tr -d ' "' | head -n 1)
TF_ZONE=$(grep -E "^\s*zone\s*=" terraform/terraform.tfvars | awk -F'=' '{print $2}' | sed 's/#.*//' | tr -d ' "' | head -n 1)

export TF_VAR_project_id="$TF_PROJECT_ID"
export TF_VAR_region="$TF_REGION"
export TF_VAR_zone="$TF_ZONE"

bucket=$(grep -E "^\s*bucket_name\s*=" terraform/terraform.tfvars | awk -F'=' '{print $2}' | sed 's/#.*//' | tr -d ' "' | head -n 1 || true)
if [ -n "$bucket" ]; then
    export TF_VAR_bucket_name="$bucket"
fi

source_bucket=$(grep -E "^\s*lsf_source_bucket\s*=" terraform/terraform.tfvars | awk -F'=' '{print $2}' | sed 's/#.*//' | tr -d ' "' | head -n 1 || true)
if [ -n "$source_bucket" ]; then
    export TF_VAR_lsf_source_bucket="$source_bucket"
    export LSF_SOURCE_BUCKET="$source_bucket"
fi

echo "Exported Terraform variables into shell session:"
echo "  TF_VAR_project_id = ${TF_VAR_project_id}"
echo "  TF_VAR_region     = ${TF_VAR_region}"
echo "  TF_VAR_zone       = ${TF_VAR_zone}"
if [ -n "${TF_VAR_bucket_name:-}" ]; then
    echo "  TF_VAR_bucket_name = ${TF_VAR_bucket_name}"
fi
if [ -n "${TF_VAR_lsf_source_bucket:-}" ]; then
    echo "  LSF_SOURCE_BUCKET  = ${LSF_SOURCE_BUCKET}"
fi
