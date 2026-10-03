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
# LSF Job Submission Script: Scale 10 Dynamic GCE Instances
# =====================================================================

# 1. Source the LSF profile to expose commands
if [ -f "/opt/lsf/conf/profile.lsf" ]; then
    # shellcheck disable=SC1091
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
# -n 20: Requests exactly 20 slots concurrently (triggering 10 n2-standard-4 hosts, 2 slots/host)
# -R "select[googlehost]": Directs jobs to dynamic GCP workers
echo "Submitting parallel job requesting 20 slots to queue '$QUEUE'..."
bsub -R "select[googlehost]" \
     -q "$QUEUE" \
     -J "$JOB_NAME" \
     -n 20 \
     sleep "$RUNTIME_SEC"

echo "=================================================="
echo "Job submitted successfully!"
echo "Run 'bjobs' and 'bhosts' to monitor progress."
echo "=================================================="
