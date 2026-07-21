#!/bin/bash
# =====================================================================
# LSF Hybrid Cloud - Pre-Flight Check Script (preflight.sh)
# =====================================================================
# This script verifies that all required CLI tools, GCP authentication
# credentials, project APIs, and LSF installer files are present and
# valid before running Terraform or deploying the cluster.
# =====================================================================

set -e

PROJECT_ID="$1"

echo "=================================================="
echo "LSF Hybrid Cloud: Pre-Flight Check"
echo "=================================================="

# 1. Check Required CLI Tools
echo -n "1. Checking required CLI tools (terraform, gcloud)... "
for cmd in terraform gcloud; do
    if ! command -v $cmd &> /dev/null; then
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
if [ -n "$PROJECT_ID" ]; then
    echo -n "3. Checking access to GCP Project '$PROJECT_ID'... "
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        echo "FAILED"
        echo "ERROR: Cannot access project '$PROJECT_ID'. Check your permissions or project ID."
        exit 1
    fi
    echo "PASSED"

    echo "4. Verifying required GCP APIs (compute, iam, storage)..."
    REQUIRED_APIS=("compute.googleapis.com" "iam.googleapis.com" "storage.googleapis.com" "iamcredentials.googleapis.com")
    ENABLED_APIS=$(gcloud services list --project="$PROJECT_ID" --enabled --format="value(config.name)")
    for api in "${REQUIRED_APIS[@]}"; do
        if ! echo "$ENABLED_APIS" | grep -q "$api"; then
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
    echo "3. NOTE: No GCP Project ID provided as argument. Skipping API validation."
    echo "   Usage: ./preflight.sh <YOUR_GCP_PROJECT_ID>"
fi

# 4. Check LSF Installer Archives in Install_Files/
echo -n "5. Checking for required LSF installer archives... "
INSTALL_DIR="Install_Files"
REQUIRED_FILES=(
    "lsf10.1_lnx310-lib217-x86_64.tar.Z"
    "lsf10.1_lsfinstall_linux_x86_64.tar.Z"
    "lsf_std_entitlement.dat"
    "lsf10.1_lnx310-lib217-x86_64-602430.tar.Z"
)

for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$INSTALL_DIR/$file" ]; then
        echo "FAILED"
        echo "ERROR: Required installer file '$file' not found in '$INSTALL_DIR/'."
        echo "Please ensure all LSF installer files are present before proceeding."
        exit 1
    fi
done
echo "PASSED"

echo "=================================================="
echo "ALL PRE-FLIGHT CHECKS PASSED!"
if [ -n "$PROJECT_ID" ]; then
    echo "You are ready to deploy: cd terraform && terraform apply -var=\"project_id=$PROJECT_ID\""
else
    echo "You are ready to deploy your Terraform infrastructure."
fi
echo "=================================================="
