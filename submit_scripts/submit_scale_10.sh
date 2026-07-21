#!/bin/bash
# =====================================================================
# LSF Job Submission Script: Scale 10 Dynamic GCE Instances
# =====================================================================

# 1. Source the LSF profile to expose commands
if [ -f "/opt/lsf/conf/profile.lsf" ]; then
    source /opt/lsf/conf/profile.lsf
else
    echo "ERROR: LSF profile not found. Please source /opt/lsf/conf/profile.lsf manually."
    exit 1
fi

# 2. Define job parameters
JOB_NAME="scale_10_hosts"
QUEUE="eda"
RUNTIME_SEC=900 # 15 minutes to guarantee simultaneous execution overlap

# 3. Submit a single parallel job requesting 20 slots
# -n 20: Requests exactly 20 slots concurrently (triggering 10 c2-standard-4 hosts)
# -R "select[googlehost]": Directs jobs to dynamic GCP workers
echo "Submitting parallel job requesting 20 slots to queue '$QUEUE'..."
bsub -R "select[googlehost]" \
     -q "$QUEUE" \
     -J "$JOB_NAME" \
     -n 20 \
     sleep "$RUNTIME_SEC"

echo "=================================================="
echo "Job array submitted successfully!"
echo "Run 'bjobs' and 'bhosts' to monitor progress."
echo "=================================================="
