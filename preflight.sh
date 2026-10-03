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
# LSF Hybrid Cloud - Pre-Flight Check Script (preflight.sh)
# =====================================================================
# This script verifies that all required CLI tools, GCP authentication
# credentials, project APIs, and LSF installer files (local Install_Files/
# or shared GCS source bucket) are present and valid before running
# Terraform or deploying the cluster.
# =====================================================================

set -e

get_tfvar() {
    local var_name="$1"
    local tfvars_file=""
    if [ -f "terraform/terraform.tfvars" ]; then
        tfvars_file="terraform/terraform.tfvars"
    elif [ -f "../terraform/terraform.tfvars" ]; then
        tfvars_file="../terraform/terraform.tfvars"
    fi
    if [ -n "$tfvars_file" ]; then
        grep -E "^\s*${var_name}\s*=" "$tfvars_file" 2>/dev/null | awk -F'=' '{print $2}' | sed 's/#.*//' | tr -d ' "' | head -n 1 || true
    fi
}

CLI_PROJECT_ID=""
CLI_SOURCE_BUCKET=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --project=*)
            CLI_PROJECT_ID="${1#*=}"
            shift
            ;;
        --project)
            CLI_PROJECT_ID="$2"
            shift 2
            ;;
        --source-bucket=*)
            CLI_SOURCE_BUCKET="${1#*=}"
            shift
            ;;
        --source-bucket)
            CLI_SOURCE_BUCKET="$2"
            shift 2
            ;;
        *)
            if [ -z "$CLI_PROJECT_ID" ]; then
                CLI_PROJECT_ID="$1"
            fi
            shift
            ;;
    esac
done

PROJECT_ID="${CLI_PROJECT_ID:-${TF_VAR_project_id:-$(get_tfvar "project_id")}}"
if [ -z "$PROJECT_ID" ] || [ "$PROJECT_ID" = "(unset)" ]; then
    PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"
fi

SOURCE_BUCKET="${CLI_SOURCE_BUCKET:-${LSF_SOURCE_BUCKET:-${TF_VAR_lsf_source_bucket:-$(get_tfvar "lsf_source_bucket")}}}"
SOURCE_BUCKET="${SOURCE_BUCKET#gs://}"
SOURCE_BUCKET="${SOURCE_BUCKET%/}"

echo "=================================================="
echo "LSF Hybrid Cloud: Pre-Flight Check"
echo "=================================================="

# 1. Check Required CLI Tools
echo -n "1. Checking required CLI tools (terraform, gcloud)... "
for cmd in terraform gcloud; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "FAILED"
        echo "ERROR: '$cmd' is not installed or not in your PATH."
        exit 1
    fi
done
echo "PASSED"

# 2. Check Google Cloud Authentication & ADC
echo -n "2. Checking Google Cloud authentication & ADC token... "
if ! gcloud auth print-access-token &> /dev/null; then
    echo "FAILED"
    echo "ERROR: Your standard Google Cloud login session is missing or expired."
    echo "Please run: gcloud auth login"
    exit 1
fi

if ! gcloud auth application-default print-access-token &> /dev/null; then
    echo "FAILED"
    echo "ERROR: Your Application Default Credentials (ADC) for Terraform are missing or expired (invalid_grant / reauth required)."
    echo "Please run: gcloud auth application-default login"
    exit 1
fi
echo "PASSED"

# 3. Check GCP Project Access & Enabled APIs
if [ -n "$PROJECT_ID" ] && [ "$PROJECT_ID" != "(unset)" ]; then
    echo -n "3. Checking access to GCP Project '$PROJECT_ID'... "
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        echo "FAILED"
        echo "ERROR: Cannot access project '$PROJECT_ID'. Check your permissions or project ID."
        exit 1
    fi
    echo "PASSED"

    echo "4. Verifying required GCP APIs (compute, dns, iam, storage)..."
    REQUIRED_APIS=(
        "compute.googleapis.com"
        "dns.googleapis.com"
        "iam.googleapis.com"
        "storage.googleapis.com"
        "iamcredentials.googleapis.com"
    )
    ENABLED_APIS=$(gcloud services list --project="$PROJECT_ID" --enabled --format="value(config.name)")
    for api in "${REQUIRED_APIS[@]}"; do
        if ! echo "$ENABLED_APIS" | grep -q "^${api}$"; then
            echo "   -> Enabling required API: $api on project $PROJECT_ID..."
            gcloud services enable "$api" --project="$PROJECT_ID" || {
                echo "ERROR: Failed to enable API '$api'. Please check your project permissions."
                exit 1
            }
        else
            echo "   -> API enabled: $api"
        fi
    done
else
    echo "3. NOTE: No GCP Project ID provided as argument or in terraform.tfvars. Skipping API validation."
    echo "   Usage: ./preflight.sh <YOUR_GCP_PROJECT_ID>"
fi

# 5. Check for Customer-Supplied LSF Installer Archives in Install_Files/ or Shared GCS Source Bucket
echo -n "5. Checking for LSF installer archives (Install_Files/ or shared GCS bucket)... "
INSTALL_DIR="Install_Files"
REQUIRED_FILES=(
    "lsf_std_entitlement.dat"
    "lsf10.1_lsfinstall_linux_x86_64.tar.Z"
    "lsf10.1_lnx310-lib217-x86_64.tar.Z"
    "lsf10.1_lnx310-lib217-x86_64-602430.tar.Z"
)

FOUND_COUNT=0
for file in "${REQUIRED_FILES[@]}"; do
    if [ -f "$INSTALL_DIR/$file" ]; then
        FOUND_COUNT=$((FOUND_COUNT + 1))
    fi
done

if [ "$FOUND_COUNT" -eq "${#REQUIRED_FILES[@]}" ]; then
    echo "PASSED (4/4 local archives found in '$INSTALL_DIR/')"
elif [ -n "$SOURCE_BUCKET" ]; then
    REMOTE_COUNT=0
    for file in "${REQUIRED_FILES[@]}"; do
        if gcloud storage ls "gs://${SOURCE_BUCKET}/${file}" &>/dev/null; then
            REMOTE_COUNT=$((REMOTE_COUNT + 1))
        fi
    done
    if [ "$REMOTE_COUNT" -eq "${#REQUIRED_FILES[@]}" ]; then
        echo "PASSED (4/4 archives verified in shared bucket gs://${SOURCE_BUCKET})"
    else
        echo "CONFIGURED (Shared source bucket set to gs://${SOURCE_BUCKET}; found ${REMOTE_COUNT}/${#REQUIRED_FILES[@]} archives)"
    fi
elif [ "$FOUND_COUNT" -eq 0 ]; then
    echo "SKIPPED (No local Install_Files/ or lsf_source_bucket configured - set lsf_source_bucket for Qwiklabs/GCS staging or use pre-built Golden Images)"
else
    echo "WARNING ($FOUND_COUNT of ${#REQUIRED_FILES[@]} files found in '$INSTALL_DIR/')"
fi

echo "=================================================="
echo "ALL PRE-FLIGHT CHECKS PASSED!"
if [ -n "$PROJECT_ID" ] && [ "$PROJECT_ID" != "(unset)" ]; then
    echo "You are ready to deploy: cd terraform && terraform init && terraform apply"
else
    echo "You are ready to deploy your Terraform infrastructure."
fi
echo "=================================================="
