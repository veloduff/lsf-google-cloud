#!/bin/bash
# =====================================================================
# LSF Hybrid Cloud - GCS Upload Automation Script (upload_assets.sh)
# =====================================================================
# This script auto-detects your Terraform-created GCS bucket and
# uploads the required LSF installer files and custom configurations.
# =====================================================================

set -e

# Disable parallel composite uploads dynamically for this script to:
# 1. Eliminate confusing progress bars.
# 2. Suppress the long warning messages in the terminal output.
# 3. Ensure files are uploaded as standard singular objects.
export CLOUDSDK_STORAGE_PARALLEL_COMPOSITE_UPLOAD_ENABLED=False

echo "=================================================="
echo "LSF Hybrid Cloud: Uploading Assets to GCS"
echo "=================================================="

# 1. Check if Terraform has been run and bucket output exists
if [ ! -d "terraform" ]; then
    echo "ERROR: Run this script from the project root directory."
    exit 1
fi

echo "Retrieving GCS bucket name from Terraform state..."
cd terraform
BUCKET_NAME=$(terraform output -raw lsf_install_bucket_name 2>/dev/null || true)
cd ..

if [ -z "$BUCKET_NAME" ]; then
    echo "ERROR: Could not retrieve bucket name from Terraform."
    echo "Did you run 'terraform apply' successfully?"
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

# 2. Check if LSF is already installed on the Master VM
echo "Checking LSF installation status on master VM..."
LSF_INSTALLED_ON_VM=false
if gcloud compute ssh lsf-master --zone=us-central1-a --tunnel-through-iap --quiet --command="test -f /opt/lsf/conf/profile.lsf" &>/dev/null; then
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
    # 3. Upload installers (skips already uploaded files using --no-clobber)
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
