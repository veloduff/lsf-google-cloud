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
# LSF Job Submission Wrapper - submit_eda_job.sh
# =====================================================================

# Check if LSF environment is sourced
if [ -z "${LSF_ENVDIR:-}" ]; then
    echo "WARNING: LSF environment is not sourced. Sourcing /opt/lsf/conf/profile.lsf..."
    if [ -f "/opt/lsf/conf/profile.lsf" ]; then
        # shellcheck disable=SC1091
        . /opt/lsf/conf/profile.lsf
    else
        echo "ERROR: /opt/lsf/conf/profile.lsf not found! Please source LSF profile manually."
        exit 1
    fi
fi

echo "Submitting EDA job to LSF..."

# Submit the job using bsub:
# -q eda: Submit to the eda queue (which triggers cloud bursting)
# -R "select[googlehost] rusage[mem=8192]": Request a GCP VM and reserve 8GB RAM
# -o eda_job_%J.out: Redirect standard output to a file containing the Job ID
# -e eda_job_%J.err: Redirect standard error
bsub -q eda \
     -R "select[googlehost] rusage[mem=8192]" \
     -o eda_job_%J.out \
     -e eda_job_%J.err \
     ./run_eda_job.sh

echo "Use 'bjobs' to monitor job status, or 'bhosts -rc' to monitor GCP VM creation."
