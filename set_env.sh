#!/bin/bash
# =====================================================================
# Shell Environment Variable Auto-Exporter (set_env.sh)
# =====================================================================
# Usage: source ./set_env.sh
# Reads terraform/terraform.tfvars and exports TF_VAR_* environment variables into active shell session.
# =====================================================================

if [ ! -f "terraform/terraform.tfvars" ]; then
    echo "ERROR: terraform/terraform.tfvars not found."
    return 1 2>/dev/null || exit 1
fi

export TF_VAR_project_id=$(grep -E "^\s*project_id\s*=" terraform/terraform.tfvars | awk -F'=' '{print $2}' | tr -d ' "' | head -n 1)
export TF_VAR_region=$(grep -E "^\s*region\s*=" terraform/terraform.tfvars | awk -F'=' '{print $2}' | tr -d ' "' | head -n 1)
export TF_VAR_zone=$(grep -E "^\s*zone\s*=" terraform/terraform.tfvars | awk -F'=' '{print $2}' | tr -d ' "' | head -n 1)

bucket=$(grep -E "^\s*bucket_name\s*=" terraform/terraform.tfvars | awk -F'=' '{print $2}' | tr -d ' "' | head -n 1 || true)
if [ -n "$bucket" ]; then
    export TF_VAR_bucket_name="$bucket"
fi

echo "Exported Terraform variables into shell session:"
echo "  TF_VAR_project_id = ${TF_VAR_project_id}"
echo "  TF_VAR_region     = ${TF_VAR_region}"
echo "  TF_VAR_zone       = ${TF_VAR_zone}"
if [ -n "${TF_VAR_bucket_name:-}" ]; then
    echo "  TF_VAR_bucket_name = ${TF_VAR_bucket_name}"
fi
