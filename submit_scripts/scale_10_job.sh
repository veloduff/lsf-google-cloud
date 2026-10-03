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
# LSF Batch Job Script: scale_10_job.sh
# =====================================================================
#
# BSUB CONFIGURATION:
#BSUB -J scale_10_hosts
#BSUB -q eda
#BSUB -n 20
#BSUB -R "select[googlehost]"
#BSUB -o scale_10_hosts_%J.out
#BSUB -e scale_10_hosts_%J.err

# Source the dynamic worker PATH so pre-installed EDA tools are exposed
export PATH="/opt/conda/envs/eda/bin:/opt/conda/bin:$PATH"

echo "=================================================="
echo "LSF Parallel Job Started: $(date)"
echo "Executing on hosts: ${LSB_MCPU_HOSTS:-unknown}"
echo "=================================================="

# Run parallel workload (in this case, sleep 900)
sleep 900

echo "=================================================="
echo "LSF Parallel Job Complete: $(date)"
echo "=================================================="
