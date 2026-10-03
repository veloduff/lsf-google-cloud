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
# LSF Hybrid Cloud - GCS Upload Automation Script (upload_assets.sh)
# =====================================================================
# This script auto-detects your Terraform-created GCS bucket and
# uploads the required LSF installer files (from local Install_Files/
# or a shared GCS source bucket such as in Qwiklabs) along with
# custom cluster configurations, EDA workflows, and scaling scripts.
# =====================================================================

set -e

# Helper function to read a variable from terraform/terraform.tfvars if present
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

# Disable parallel composite uploads dynamically for this script
export CLOUDSDK_STORAGE_PARALLEL_COMPOSITE_UPLOAD_ENABLED=False

CLI_BUCKET_NAME=""
CLI_SOURCE_BUCKET=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --bucket=*)
            CLI_BUCKET_NAME="${1#*=}"
            shift
            ;;
        --bucket)
            CLI_BUCKET_NAME="$2"
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
            if [ -z "$CLI_BUCKET_NAME" ]; then
                CLI_BUCKET_NAME="$1"
            fi
            shift
            ;;
    esac
done

echo "=================================================="
echo "LSF Hybrid Cloud: Uploading Assets to GCS"
echo "=================================================="

# 1. Determine target GCS bucket name: CLI arg > env var > terraform.tfvars > terraform output
if [ -n "$CLI_BUCKET_NAME" ]; then
    BUCKET_NAME="$CLI_BUCKET_NAME"
elif [ -n "${TF_VAR_bucket_name:-}" ]; then
    BUCKET_NAME="$TF_VAR_bucket_name"
elif [ -n "$(get_tfvar "bucket_name")" ]; then
    BUCKET_NAME="$(get_tfvar "bucket_name")"
fi

if [ -z "${BUCKET_NAME:-}" ]; then
    if [ -d "terraform" ]; then
        echo "Retrieving GCS bucket name from Terraform output..."
        BUCKET_NAME=$(terraform -chdir=terraform output -raw lsf_install_bucket_name 2>/dev/null || true)
    fi
fi

if [ -z "${BUCKET_NAME:-}" ] || [ "$BUCKET_NAME" = "(unset)" ]; then
    echo "ERROR: Could not retrieve target bucket name from CLI argument, environment variables, terraform.tfvars, or Terraform output."
    echo "Did you run 'terraform apply' successfully or specify bucket_name in terraform.tfvars / TF_VAR_bucket_name?"
    exit 1
fi

BUCKET_NAME="${BUCKET_NAME#gs://}"
BUCKET_NAME="${BUCKET_NAME%/}"
echo "Target bucket: gs://${BUCKET_NAME}"

# Determine optional shared GCS source bucket for LSF installers (used in Qwiklabs / enterprise staging)
SOURCE_BUCKET="${CLI_SOURCE_BUCKET:-${LSF_SOURCE_BUCKET:-${TF_VAR_lsf_source_bucket:-$(get_tfvar "lsf_source_bucket")}}}"
if [ -z "$SOURCE_BUCKET" ] && [ -d "terraform" ]; then
    SOURCE_BUCKET=$(terraform -chdir=terraform output -raw lsf_source_bucket 2>/dev/null || true)
fi
SOURCE_BUCKET="${SOURCE_BUCKET#gs://}"
SOURCE_BUCKET="${SOURCE_BUCKET%/}"

# 2. Define required LSF 10.1 installer archives
INSTALL_DIR="Install_Files"
REQUIRED_ARCHIVES=(
    "lsf10.1_lsfinstall_linux_x86_64.tar.Z"
    "lsf10.1_lnx310-lib217-x86_64.tar.Z"
    "lsf_std_entitlement.dat"
    "lsf10.1_lnx310-lib217-x86_64-602430.tar.Z"
)

# 3. Check if LSF is already installed on the Master VM
echo "Checking LSF installation status on master VM..."
LSF_INSTALLED_ON_VM=false
MASTER_ZONE=$(gcloud compute instances list --filter="name=lsf-master" --format="value(zone)" --limit=1 2>/dev/null || true)
if [ -z "$MASTER_ZONE" ]; then
    PREF_ZONE="$(get_tfvar "zone")"
    PREF_REGION="$(get_tfvar "region")"
    MASTER_ZONE="${PREF_ZONE:-${PREF_REGION:+$PREF_REGION-a}}"
fi
MASTER_ZONE="${MASTER_ZONE:-us-central1-a}"

if gcloud compute ssh lsf-master --zone="$MASTER_ZONE" --tunnel-through-iap --quiet --command="test -f /opt/lsf/conf/profile.lsf" &>/dev/null; then
    echo " -> LSF is already installed on master VM. Skipping installer upload."
    LSF_INSTALLED_ON_VM=true
else
    echo " -> LSF is not detected on master VM. Checking installer sources..."
fi

if [ "$LSF_INSTALLED_ON_VM" = "false" ]; then
    # Check if all 4 files exist locally in Install_Files/
    LOCAL_FOUND=true
    for archive in "${REQUIRED_ARCHIVES[@]}"; do
        if [ ! -f "${INSTALL_DIR}/${archive}" ]; then
            LOCAL_FOUND=false
            break
        fi
    done

    if [ "$LOCAL_FOUND" = "true" ]; then
        echo "Verified local installer files in '${INSTALL_DIR}/'!"
        echo "Uploading customer-supplied LSF installers from local directory to gs://${BUCKET_NAME}/..."
        for archive in "${REQUIRED_ARCHIVES[@]}"; do
            echo " -> Uploading ${archive}..."
            gcloud storage cp --no-clobber "${INSTALL_DIR}/${archive}" "gs://${BUCKET_NAME}/${archive}"
        done
    elif [ -n "$SOURCE_BUCKET" ] && [ "$SOURCE_BUCKET" != "(unset)" ]; then
        echo "Staging LSF installer archives from shared GCS source bucket: gs://${SOURCE_BUCKET}/..."
        for archive in "${REQUIRED_ARCHIVES[@]}"; do
            echo " -> Copying gs://${SOURCE_BUCKET}/${archive} to gs://${BUCKET_NAME}/${archive}..."
            gcloud storage cp --no-clobber "gs://${SOURCE_BUCKET}/${archive}" "gs://${BUCKET_NAME}/${archive}"
        done
        echo "All 4 LSF installer archives staged from gs://${SOURCE_BUCKET}/!"
    else
        echo "WARNING: Local '${INSTALL_DIR}/' not found and no shared LSF_SOURCE_BUCKET configured."
        echo "Skipping LSF installer archives upload (set LSF_SOURCE_BUCKET / lsf_source_bucket for GCS-to-GCS staging, or use pre-built Golden Images)."
    fi
fi

# 4. Upload LSF configurations (always syncs configuration folder)
echo "Uploading LSF configuration directory..."
gcloud storage cp -r "lsf_config" "gs://${BUCKET_NAME}/"

# 5. Upload EDA sample workflow directory
echo "Uploading EDA sample workflow directory..."
gcloud storage cp -r "eda_workflow" "gs://${BUCKET_NAME}/"

# 6. Upload Submit & Scaling test scripts directory
echo "Uploading Submit & Scaling test scripts directory..."
gcloud storage cp -r "submit_scripts" "gs://${BUCKET_NAME}/"

echo "=================================================="
echo "ALL ASSETS UPLOADED SUCCESSFULLY TO:"
echo "gs://${BUCKET_NAME}/"
echo "=================================================="
