#!/bin/bash
# =====================================================================
# LSF Hybrid Cloud - GCS Upload Automation Script (upload_assets.sh)
# =====================================================================
# This script auto-detects your Terraform-created GCS bucket and
# uploads the required LSF installer files and custom configurations.
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
        grep -E "^\s*${var_name}\s*=" "$tfvars_file" 2>/dev/null | awk -F'=' '{print $2}' | tr -d ' "' | head -n 1 || true
    fi
}

# Disable parallel composite uploads dynamically for this script
export CLOUDSDK_STORAGE_PARALLEL_COMPOSITE_UPLOAD_ENABLED=False

echo "=================================================="
echo "LSF Hybrid Cloud: Uploading Assets to GCS"
echo "=================================================="

# 1. Determine GCS bucket name: custom CLI argument > env var > terraform.tfvars > terraform output
if [ -n "$1" ]; then
    BUCKET_NAME="$1"
elif [ -n "$TF_VAR_bucket_name" ]; then
    BUCKET_NAME="$TF_VAR_bucket_name"
elif [ -n "$(get_tfvar "bucket_name")" ]; then
    BUCKET_NAME="$(get_tfvar "bucket_name")"
fi

if [ -z "${BUCKET_NAME:-}" ]; then
    if [ -d "terraform" ]; then
        echo "Retrieving GCS bucket name from Terraform output..."
        cd terraform
        BUCKET_NAME=$(terraform output -raw lsf_install_bucket_name 2>/dev/null || true)
        cd ..
    fi
fi

if [ -z "${BUCKET_NAME:-}" ] || [ "$BUCKET_NAME" = "(unset)" ]; then
    echo "ERROR: Could not retrieve bucket name from CLI argument, environment variables, terraform.tfvars, or Terraform output."
    echo "Did you run 'terraform apply' successfully or specify bucket_name in terraform.tfvars / TF_VAR_bucket_name?"
    exit 1
fi

echo "Target bucket: gs://${BUCKET_NAME}"

# 2. Check and upload required installer files
INSTALL_DIR="Install_Files"

FILES_TO_UPLOAD=(
    "$INSTALL_DIR/lsf10.1_lsfinstall_linux_x86_64.tar.Z:lsf10.1_lsfinstall_linux_x86_64.tar.Z"
    "$INSTALL_DIR/lsf10.1_lnx310-lib217-x86_64.tar.Z:lsf10.1_lnx310-lib217-x86_64.tar.Z"
    "$INSTALL_DIR/lsf_std_entitlement.dat:lsf_std_entitlement.dat"
    "$INSTALL_DIR/lsf10.1_lnx310-lib217-x86_64-602430.tar.Z:lsf10.1_lnx310-lib217-x86_64-602430.tar.Z"
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
    echo " -> LSF is not detected on master VM. Checking local installers..."
fi

UPLOAD_INSTALLERS=true
if [ "$LSF_INSTALLED_ON_VM" = "true" ]; then
    UPLOAD_INSTALLERS=false
else
    echo "Verifying local installer files..."
    for entry in "${FILES_TO_UPLOAD[@]}"; do
        local_file="${entry%%:*}"
        if [ ! -f "$local_file" ]; then
            echo "WARNING: Required installer file '$local_file' not found."
            echo "Skipping LSF installer archives upload (assuming pre-built Golden Images will be used)."
            UPLOAD_INSTALLERS=false
            break
        fi
    done
fi

if [ "$UPLOAD_INSTALLERS" = "true" ]; then
    echo "All local files verified!"
    # 4. Upload installers (skips already uploaded files using --no-clobber)
    echo "Uploading LSF installers to GCS..."
    for entry in "${FILES_TO_UPLOAD[@]}"; do
        local_file="${entry%%:*}"
        remote_name="${entry##*:}"
        echo " -> Uploading ${remote_name}..."
        gcloud storage cp --no-clobber "$local_file" "gs://${BUCKET_NAME}/${remote_name}"
    done
else
    echo "--- Skipping LSF installers upload block ---"
fi

# 5. Upload LSF configurations (always syncs configuration folder)
echo "Uploading LSF configuration directory..."
gcloud storage cp -r "lsf_config" "gs://${BUCKET_NAME}/"

# 6. Upload EDA sample workflow directory
echo "Uploading EDA sample workflow directory..."
gcloud storage cp -r "eda_workflow" "gs://${BUCKET_NAME}/"

# 7. Upload Submit & Scaling test scripts directory
echo "Uploading Submit & Scaling test scripts directory..."
gcloud storage cp -r "submit_scripts" "gs://${BUCKET_NAME}/"

echo "=================================================="
echo "ALL ASSETS UPLOADED SUCCESSFULLY TO:"
echo "gs://${BUCKET_NAME}/"
echo "=================================================="
