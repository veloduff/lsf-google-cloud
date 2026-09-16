#!/bin/bash
# =====================================================================
# Automated LSF Master Installation & Configuration Script (setup_master.sh)
# =====================================================================
set -e

# Capture the absolute path to the directory containing this script before any directory changes
CONFIG_SRC=$(cd "$(dirname "$0")" && pwd)
echo "Resolved CONFIG_SRC to: $CONFIG_SRC"


echo "=================================================="
echo "Starting LSF Master Setup on: $(hostname)"
echo "=================================================="

# 1. Ensure required system packages and user exist
echo "--- Step 1: Installing prerequisites and lsfadmin user ---"
hostnamectl set-hostname master.onprem.local || true

groupadd -f lsf
id -u lsfadmin &>/dev/null || useradd -m -g lsf -s /bin/bash lsfadmin
usermod -g lsf lsfadmin || true

# Clean up any existing LSF processes
echo "Stopping any running LSF daemons..."
killall -9 lim res sbatchd pim mbatchd mbschd ebrokerd 2>/dev/null || true

# 2. Check if LSF is already installed
if [ ! -f "/opt/lsf/conf/profile.lsf" ]; then
    echo "LSF profile not found. Starting clean LSF installation..."

    # Clean LSF target directory to support retries cleanly
    echo "Cleaning /opt/lsf target directory..."
    rm -rf /opt/lsf/* /opt/lsf/.* 2>/dev/null || true

    # Wait for system boot package updates to release the yum/dnf lock
    echo "Waiting for system package manager locks to release..."
    while fuser /var/lib/dnf/lock >/dev/null 2>&1 || fuser /var/lib/rpm/lock >/dev/null 2>&1 || pgrep -f dnf >/dev/null 2>&1 || pgrep -f yum >/dev/null 2>&1; do
        echo "Package manager is busy. Waiting 5 seconds..."
        sleep 5
    done

    echo "Installing system packages and prerequisites..."
    yum update -y
    yum install -y nfs-utils ed wget git gcc make epel-release libnsl java-1.8.0-openjdk-headless bc
    echo "--- Step 2: Locating LSF Installation Archives ---"
    INSTALL_DIR="/tmp/lsf_dist"
    mkdir -p $INSTALL_DIR

    if [ ! -f "$INSTALL_DIR/lsf10.1_lsfinstall_linux_x86_64.tar.Z" ] || \
       [ ! -f "$INSTALL_DIR/lsf10.1_lnx310-lib217-x86_64.tar.Z" ] || \
       [ ! -f "$INSTALL_DIR/lsf_std_entitlement.dat" ] || \
       [ ! -f "$INSTALL_DIR/lsf10.1_lnx310-lib217-x86_64-602430.tar.Z" ]; then
        echo "Attempting to download LSF installers from GCS bucket..."
        # Auto-detect the GCS bucket created by Terraform
        BUCKET_NAME=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/attributes/lsf_bucket)
        if [ -n "$BUCKET_NAME" ]; then
            echo "Found bucket: gs://$BUCKET_NAME. Downloading files..."
            gcloud storage cp gs://$BUCKET_NAME/*.tar.Z $INSTALL_DIR/
            gcloud storage cp gs://$BUCKET_NAME/*.dat $INSTALL_DIR/
        else
            echo "ERROR: Installers not found in $INSTALL_DIR and no GCS bucket found."
            echo "Please upload lsf10.1_lsfinstall_linux_x86_64.tar.Z, lsf10.1_lnx310-lib217-x86_64.tar.Z, and lsf_std_entitlement.dat to $INSTALL_DIR"
            exit 1
        fi
    fi

    # 3. Extract lsfinstall
    echo "--- Step 3: Extracting LSF Installer ---"
    cd $INSTALL_DIR
    tar -zxvf lsf10.1_lsfinstall_linux_x86_64.tar.Z
    cd lsf10.1_lsfinstall

    # 4. Create silent install.config
    echo "--- Step 4: Generating silent install.config ---"
    cat <<EOT > install.config
LSF_TOP="/opt/lsf"
LSF_ADMINS="lsfadmin root"
LSF_CLUSTER_NAME="eda_cluster"
LSF_MASTER_LIST="master.onprem.local"
LSF_TARDIR="$INSTALL_DIR"
LSF_ENTITLEMENT_FILE="$INSTALL_DIR/lsf_std_entitlement.dat"
LSF_SERVER_HOSTS="master.onprem.local"
LSF_SILENT_INSTALL_TARLIST="all"
ACCEPT_LICENSE="Y"
SILENT_INSTALL="Y"
EOT

    # 5. Run silent installation
    echo "--- Step 5: Running ./lsfinstall ---"
    ./lsfinstall -f install.config

    # 5b. Apply Service Pack 15 Patch (Upgrade to 10.1.0.15)
    echo "--- Step 5b: Applying Service Pack 15 Patch ---"
    ./patchinstall -f install.config --silent $INSTALL_DIR/lsf10.1_lnx310-lib217-x86_64-602430.tar.Z
else
    echo "LSF installation detected at /opt/lsf."
    DAEMONS_DIR=$(ls -d /opt/lsf/10.1/linux*/etc 2>/dev/null || true)
    if [ -n "$DAEMONS_DIR" ] && [ -f "$DAEMONS_DIR/lim" ]; then
        echo "Installed LSF Binary Version Details:"
        $DAEMONS_DIR/lim -V || true
    fi
    echo "Skipping core package installation and patching."
fi

# 6. Apply custom Hybrid Cloud configurations
echo "--- Step 6: Applying Hybrid Cloud & Resource Connector Configs ---"
if [ -f "$CONFIG_SRC/lsf.conf" ]; then
    echo "Copying custom configurations from $CONFIG_SRC to /opt/lsf/conf/..."
    cp -f $CONFIG_SRC/lsf.conf /opt/lsf/conf/
    cp -f $CONFIG_SRC/lsf.shared /opt/lsf/conf/
    cp -f $CONFIG_SRC/lsf.cluster.eda_cluster /opt/lsf/conf/
    
    mkdir -p /opt/lsf/conf/lsbatch/eda_cluster/configdir
    cp -f $CONFIG_SRC/lsb.queues /opt/lsf/conf/lsbatch/eda_cluster/configdir/
    cp -f $CONFIG_SRC/lsb.hosts /opt/lsf/conf/lsbatch/eda_cluster/configdir/
    cp -f $CONFIG_SRC/lsb.resources /opt/lsf/conf/lsbatch/eda_cluster/configdir/
    cp -f $CONFIG_SRC/lsb.modules /opt/lsf/conf/lsbatch/eda_cluster/configdir/
    
    # Resource connector configs
    mkdir -p /opt/lsf/conf/resource_connector/google/conf
    cp -f $CONFIG_SRC/hostProviders.json /opt/lsf/conf/resource_connector/
    cp -f $CONFIG_SRC/googleprov_config.json /opt/lsf/conf/resource_connector/google/conf/
    
    # Dynamically detect project ID, zone, and region from metadata
    PROJECT_ID=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/project/project-id)
    ZONE_FULL=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/zone)
    ZONE=$(basename "$ZONE_FULL")
    REGION="${ZONE%-*}"

    # Substitute project ID and zone in lsf.conf
    sed -i "s#YOUR_GCP_PROJECT_ID#$PROJECT_ID#g" /opt/lsf/conf/lsf.conf
    sed -i "s#YOUR_GCP_ZONE#$ZONE#g" /opt/lsf/conf/lsf.conf
    
    # Substitute project ID and region in googleprov_config.json
    sed -i "s#YOUR_GCP_PROJECT_ID#$PROJECT_ID#g" /opt/lsf/conf/resource_connector/google/conf/googleprov_config.json
    sed -i "s#YOUR_GCP_REGION#$REGION#g" /opt/lsf/conf/resource_connector/google/conf/googleprov_config.json
    
    cp -f $CONFIG_SRC/googleprov_templates.json /opt/lsf/conf/resource_connector/google/conf/
    
    # Ensure worker image exists in local project for instant bulk VM creation
    if ! gcloud compute images describe lsf-submit-and-worker-rocky-8-image --project="$PROJECT_ID" &>/dev/null; then
        echo "Creating base worker image alias lsf-submit-and-worker-rocky-8-image..."
        gcloud compute images create lsf-submit-and-worker-rocky-8-image \
          --project="$PROJECT_ID" \
          --source-image-family=rocky-linux-8-optimized-gcp \
          --source-image-project=rocky-linux-cloud --quiet || true
    fi
    WORKER_IMAGE="lsf-submit-and-worker-rocky-8-image"
    HOST_PROJECT="$PROJECT_ID"

    if [ -n "$WORKER_IMAGE" ]; then
        sed -i "s#YOUR_WORKER_IMAGE_NAME#$WORKER_IMAGE#g" /opt/lsf/conf/resource_connector/google/conf/googleprov_templates.json
        sed -i "s#YOUR_HOST_PROJECT#$HOST_PROJECT#g" /opt/lsf/conf/resource_connector/google/conf/googleprov_templates.json
    fi
    sed -i "s#YOUR_GCP_REGION#$REGION#g" /opt/lsf/conf/resource_connector/google/conf/googleprov_templates.json
    sed -i "s#YOUR_GCP_ZONE#$ZONE#g" /opt/lsf/conf/resource_connector/google/conf/googleprov_templates.json
    
    # Ensure H4D launch template exists with hyperdisk-balanced boot disk and TERMINATE maintenance policy
    if ! gcloud compute instance-templates describe lsf-h4d-worker-template --project="$PROJECT_ID" &>/dev/null; then
        echo "Creating global instance template lsf-h4d-worker-template with hyperdisk-balanced boot disk..."
        gcloud compute instance-templates create lsf-h4d-worker-template \
          --project="$PROJECT_ID" \
          --machine-type=h4d-standard-192 \
          --image="$WORKER_IMAGE" \
          --boot-disk-type=hyperdisk-balanced \
          --boot-disk-size=50GB \
          --maintenance-policy=TERMINATE \
          --network=lsf-cloud-vpc \
          --subnet=lsf-cloud-subnet \
          --service-account="lsf-resource-connector-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
          --scopes=cloud-platform \
          --tags=lsf-worker --quiet || true
    fi

    ln -sf /opt/lsf/conf/resource_connector/google/conf /opt/lsf/conf/resource_connector/google/conf/conf
    
    # Copy user_data.sh and getRequestStatus.sh scripts for cloud workers and connector
    mkdir -p /opt/lsf/10.1/resource_connector/google/scripts
    cp -f $CONFIG_SRC/user_data.sh /opt/lsf/10.1/resource_connector/google/scripts/
    chmod +x /opt/lsf/10.1/resource_connector/google/scripts/user_data.sh
    if [ -f "$CONFIG_SRC/getRequestStatus.sh" ]; then
        cp -f $CONFIG_SRC/getRequestStatus.sh /opt/lsf/10.1/resource_connector/google/scripts/
        chmod +x /opt/lsf/10.1/resource_connector/google/scripts/getRequestStatus.sh
        chown lsfadmin:lsf /opt/lsf/10.1/resource_connector/google/scripts/getRequestStatus.sh
    fi
fi

# 6b. Copy EDA workflows & Scaling scripts from GCS to shared NFS directory (/home/lsfadmin)
echo "--- Step 6b: Copying workflows and scripts from GCS ---"
BUCKET_NAME=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/attributes/lsf_bucket)
if [ -n "$BUCKET_NAME" ]; then
    rm -rf /home/lsfadmin/eda_workflow /home/lsfadmin/submit_scripts
    gcloud storage cp -r gs://$BUCKET_NAME/eda_workflow /home/lsfadmin/
    gcloud storage cp -r gs://$BUCKET_NAME/submit_scripts /home/lsfadmin/
    chown -R lsfadmin:lsf /home/lsfadmin/eda_workflow /home/lsfadmin/submit_scripts
    chmod +x /home/lsfadmin/eda_workflow/*.sh /home/lsfadmin/submit_scripts/*.sh
    echo "Workflows and scaling scripts successfully copied to /home/lsfadmin/"
else
    echo "WARNING: No GCS bucket found. Skipping workflow/script copy."
fi

# Sanitize LSF dynamic work directories to ensure a clean history starting at Job ID 1
echo "Sanitizing dynamic cluster history event logs..."
find /opt/lsf/work -type f -delete 2>/dev/null || true

# Fix ownership
chown -R lsfadmin:lsf /opt/lsf

# Configure eauth binary to run as root with SUID permissions (mandatory for authentication)
echo "Configuring eauth SUID root permissions..."
EAUTH_PATH=$(ls /opt/lsf/10.1/linux*/etc/eauth)
chown root $EAUTH_PATH
chmod 4755 $EAUTH_PATH

# 7. Start LSF daemons directly
echo "--- Step 7: Starting LSF Cluster Daemons ---"
set +e
source /opt/lsf/conf/profile.lsf
set -e
DAEMONS_DIR=$(ls -d /opt/lsf/10.1/linux*/etc)
$DAEMONS_DIR/lim || true
sleep 5
$DAEMONS_DIR/res || true
sleep 5
$DAEMONS_DIR/sbatchd || true
sleep 5
lsadmin reconfig -f || true
badmin reconfig -f || true

echo "=================================================="
echo "SUCCESS! LSF Master is fully installed and configured."
echo "Run 'source /opt/lsf/conf/profile.lsf' followed by 'lsid' and 'bhosts' to verify."
echo "=================================================="
