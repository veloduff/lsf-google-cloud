#!/bin/bash
# =====================================================================
# LSF Hybrid Cloud: Automated Golden Image Builder (build_golden_image.sh)
# =====================================================================
set -euo pipefail

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

# Initialize variables safely for set -u
CLI_PROJECT_ID=""
CLI_REGION=""
CLI_ZONE=""
CLI_SUBNET=""
POSITIONAL_ARGS=()

while [[ $# -gt 0 ]]; do
  case $1 in
    --project=*)
      CLI_PROJECT_ID="${1#*=}"
      shift
      ;;
    --project)
      CLI_PROJECT_ID="$2"
      shift 2
      ;;
    --region=*)
      CLI_REGION="${1#*=}"
      shift
      ;;
    --region)
      CLI_REGION="$2"
      shift 2
      ;;
    --zone=*)
      CLI_ZONE="${1#*=}"
      shift
      ;;
    --zone)
      CLI_ZONE="$2"
      shift 2
      ;;
    --subnet=*)
      CLI_SUBNET="${1#*=}"
      shift
      ;;
    --subnet)
      CLI_SUBNET="$2"
      shift 2
      ;;
    *)
      POSITIONAL_ARGS+=("$1")
      shift
      ;;
  esac
done

POS1="${POSITIONAL_ARGS[0]:-}"
POS2="${POSITIONAL_ARGS[1]:-}"

TF_PROJECT="${TF_VAR_project_id:-}"
TF_REGION="${TF_VAR_region:-}"
TF_ZONE="${TF_VAR_zone:-}"

# Determine Project ID (CLI flag > Positional arg > TF_VAR_project_id > terraform.tfvars > gcloud config)
PROJECT_ID="${CLI_PROJECT_ID:-${POS1:-${TF_PROJECT:-$(get_tfvar "project_id")}}}"
if [ -z "$PROJECT_ID" ] || [ "$PROJECT_ID" = "(unset)" ]; then
    PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"
fi

# Determine Region and Zone (CLI flag/arg > TF_VAR_* > terraform.tfvars > gcloud config)
REGION="${CLI_REGION:-${TF_REGION:-$(get_tfvar "region")}}"
if [ -z "$REGION" ] || [ "$REGION" = "(unset)" ]; then
    REGION="$(gcloud config get-value compute/region 2>/dev/null || true)"
fi
REGION="${REGION:-us-central1}"

ZONE="${CLI_ZONE:-${POS2:-${TF_ZONE:-$(get_tfvar "zone")}}}"
if [ -z "$ZONE" ] || [ "$ZONE" = "(unset)" ]; then
    ZONE="$(gcloud config get-value compute/zone 2>/dev/null || true)"
fi

# If zone is not set, derive from region
if [ -z "$ZONE" ] || [ "$ZONE" = "(unset)" ]; then
    ZONE="${REGION}-a"
fi

SUBNET="${CLI_SUBNET:-lsf-cloud-subnet}"
BUILD_VM="lsf-golden-build"
IMAGE_NAME="lsf-submit-and-worker-rocky-8-image"

if [ -z "$PROJECT_ID" ] || [ "$PROJECT_ID" = "(unset)" ]; then
    echo "ERROR: GCP Project ID is required. Please specify via --project, TF_VAR_project_id, terraform/terraform.tfvars, or gcloud config."
    exit 1
fi

echo "=================================================="
echo "Starting Golden Image Build Pipeline for LSF Workers"
echo "=================================================="
echo " Project ID : ${PROJECT_ID}"
echo " Region     : ${REGION}"
echo " Zone       : ${ZONE}"
echo " Subnet     : ${SUBNET}"
echo " Image Name : ${IMAGE_NAME}"
echo "=================================================="

# 1. Spin up temporary builder VM
echo "Step 1: Creating temporary GCE VM '$BUILD_VM'..."
gcloud compute instances create "$BUILD_VM" \
    --project="$PROJECT_ID" \
    --zone="$ZONE" \
    --machine-type="c2-standard-4" \
    --subnet="$SUBNET" \
    --service-account="lsf-resource-connector-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
    --scopes="https://www.googleapis.com/auth/cloud-platform" \
    --image-project="rocky-linux-cloud" \
    --image-family="rocky-linux-8-optimized-gcp" \
    --boot-disk-size="20GB" \
    --boot-disk-type="pd-ssd" \
    --no-address \
    --shielded-secure-boot \
    --shielded-vtpm \
    --shielded-integrity-monitoring \
    --quiet

# Wait for SSH to become ready
echo "Waiting for VM to initialize and SSH to become ready..."
SSH_READY=false
for i in {1..12}; do
    if gcloud compute ssh "$BUILD_VM" --project="$PROJECT_ID" --zone="$ZONE" --tunnel-through-iap --command="true" --quiet &>/dev/null; then
        SSH_READY=true
        echo " -> SSH is ready!"
        break
    fi
    echo " -> SSH not ready yet (attempt $i/12). Retrying in 10s..."
    sleep 10
done

if [ "$SSH_READY" = "false" ]; then
    echo "ERROR: Unable to connect to '$BUILD_VM' via SSH after 120 seconds."
    exit 1
fi

# 2. Run dependency and package installation commands inside the VM
echo "Step 2: Installing OS dependencies, Miniconda, and EDA tools..."
gcloud compute ssh "$BUILD_VM" \
    --project="$PROJECT_ID" \
    --zone="$ZONE" \
    --tunnel-through-iap \
    --command='sudo bash -s << "EOF"
set -euo pipefail
logfile=/tmp/image_build.log
echo "Starting remote installation tasks..." > $logfile

# Install prerequisites
echo "--- Installing OS Packages ---" >> $logfile
dnf install -y nfs-utils ed epel-release libnsl java-1.8.0-openjdk-headless wget >> $logfile 2>&1

# Install Miniconda
echo "--- Installing Miniconda ---" >> $logfile
wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O /tmp/miniconda.sh >> $logfile 2>&1
bash /tmp/miniconda.sh -b -p /opt/conda >> $logfile 2>&1
rm -f /tmp/miniconda.sh

# Configure Conda PATH globally (including eda environment path)
echo "export PATH=\"/opt/conda/envs/eda/bin:/opt/conda/bin:\$PATH\"" > /etc/profile.d/conda.sh

# Accept ToS for default Anaconda channels (mandatory for non-interactive installs)
echo "--- Accepting Anaconda Terms of Service ---" >> $logfile
/opt/conda/bin/conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main >> $logfile 2>&1
/opt/conda/bin/conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r >> $logfile 2>&1

# Add community channels
/opt/conda/bin/conda config --add channels litex-hub >> $logfile 2>&1
/opt/conda/bin/conda config --add channels conda-forge >> $logfile 2>&1

# Create EDA environment and install tools
echo "--- Creating Conda Environment 'eda' and installing tools ---" >> $logfile
/opt/conda/bin/conda create -y -n eda -c litex-hub -c conda-forge python=3.10 yosys openroad magic netgen verilator iverilog gtkwave >> $logfile 2>&1

echo "Verification of EDA installations:" >> $logfile
/opt/conda/envs/eda/bin/iverilog -V >> $logfile 2>&1 || true
/opt/conda/envs/eda/bin/yosys -V >> $logfile 2>&1 || true
/opt/conda/envs/eda/bin/verilator --version >> $logfile 2>&1 || true

echo "Remote installation tasks completed successfully!" >> $logfile
EOF
'

# 3. Stop the builder VM (mandatory before creating custom machine image)
echo "Step 3: Stopping GCE VM '$BUILD_VM'..."
gcloud compute instances stop "$BUILD_VM" \
    --project="$PROJECT_ID" \
    --zone="$ZONE" \
    --quiet

# 4. Recreate the custom machine image
if gcloud compute images describe "$IMAGE_NAME" --project="$PROJECT_ID" &>/dev/null; then
    echo "Step 4a: Deleting existing custom image '$IMAGE_NAME'..."
    gcloud compute images delete "$IMAGE_NAME" --project="$PROJECT_ID" --quiet
fi

echo "Step 4b: Creating custom machine image '$IMAGE_NAME' from build VM disk..."
gcloud compute images create "$IMAGE_NAME" \
    --project="$PROJECT_ID" \
    --source-disk="$BUILD_VM" \
    --source-disk-zone="$ZONE" \
    --family="lsf-rocky-8"

# 5. Clean up temporary VM
echo "Step 5: Deleting builder VM '$BUILD_VM'..."
gcloud compute instances delete "$BUILD_VM" \
    --project="$PROJECT_ID" \
    --zone="$ZONE" \
    --quiet

echo "=================================================="
echo "SUCCESS: Custom LSF Golden Image '$IMAGE_NAME' has been created."
echo "=================================================="
