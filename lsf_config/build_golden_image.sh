#!/bin/bash
# =====================================================================
# LSF Hybrid Cloud: Automated Golden Image Builder (build_golden_image.sh)
# =====================================================================
set -euo pipefail

PROJECT_ID="lsf-testing-001"
ZONE="us-central1-a"
SUBNET="lsf-cloud-subnet"
BUILD_VM="lsf-golden-build"
IMAGE_NAME="lsf-submit-and-worker-rocky-8-image"

echo "=================================================="
echo "Starting Golden Image Build Pipeline for LSF Workers"
echo "=================================================="

# 1. Spin up temporary builder VM
echo "Step 1: Creating temporary GCE VM '$BUILD_VM'..."
gcloud compute instances create "$BUILD_VM" \
    --project="$PROJECT_ID" \
    --zone="$ZONE" \
    --machine-type="c2-standard-4" \
    --subnet="$SUBNET" \
    --service-account="lsf-resource-connector-sa@lsf-testing-001.iam.gserviceaccount.com" \
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
sleep 35

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
