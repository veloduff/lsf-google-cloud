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
# Qwiklabs Assessment 5: Verify EDA Simulation, Synthesis & Regression
# =====================================================================
set -euo pipefail

PROJECT_ID="${1:-${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || true)}}"

if [ -z "$PROJECT_ID" ]; then
    echo "ASSESSMENT FAILED: GCP Project ID could not be determined."
    exit 1
fi

MASTER_ZONE=$(gcloud compute instances list --project="$PROJECT_ID" --filter="name=lsf-master" --format="value(zone)" --limit=1 2>/dev/null || true)
if [ -z "$MASTER_ZONE" ]; then
    echo "ASSESSMENT FAILED: Could not locate 'lsf-master' instance."
    exit 1
fi

# Verify EDA simulation & synthesis artifacts and regression array execution on shared NFS (/home/lsfadmin/eda_workflow)
if ! gcloud compute ssh lsf-master \
    --project="$PROJECT_ID" \
    --zone="$MASTER_ZONE" \
    --tunnel-through-iap \
    --quiet \
    --command="
      test -f /home/lsfadmin/eda_workflow/counter.vcd && \
      test -f /home/lsfadmin/eda_workflow/counter_synth.v && \
      (test -d /home/lsfadmin/eda_workflow/runs/run_1 || grep -q 'eda_regress' /opt/lsf/work/eda_cluster/logdir/lsb.events* 2>/dev/null)
    " &>/dev/null; then
    echo "ASSESSMENT FAILED: EDA simulation/synthesis outputs ('counter.vcd', 'counter_synth.v') or the 100-task regression sweep ('eda_regress') were not found in '/home/lsfadmin/eda_workflow'. Please complete all steps in Task 5."
    exit 1
fi

echo "ASSESSMENT PASSED: Verilog simulation (counter.vcd), Yosys synthesis netlist (counter_synth.v), and the 100-task multi-seed EDA regression sweep are verified!"
exit 0
