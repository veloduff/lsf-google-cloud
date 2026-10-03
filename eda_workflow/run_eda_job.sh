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
# EDA Execution Script - run_eda_job.sh
# =====================================================================

# Ensure Conda EDA toolchain is exposed on PATH in non-login batch shells
export PATH="/opt/conda/envs/eda/bin:/opt/conda/bin:$PATH"

echo "=================================================="
echo "Starting EDA Job on Host: $(hostname)"
echo "Current Directory: $(pwd)"
echo "Date/Time: $(date)"
echo "=================================================="

# 1. Print Host Details to verify the VM shape
echo "--- Host Information ---"
lscpu | grep -E "Model name|CPU\(s\):|Thread\(s\) per core"
free -h
echo "------------------------"

# 2. Check for EDA Tool availability
echo "--- Checking EDA Tools ---"
which iverilog
which vvp
which yosys
echo "--------------------------"

# 3. Run Simulation
echo "--- Step 1: Running Verilog Simulation ---"
if ! iverilog -o counter_sim counter.v counter_tb.v; then
    echo "ERROR: Verilog compilation failed!"
    exit 1
fi

if ! vvp counter_sim; then
    echo "ERROR: Simulation execution failed!"
    exit 1
fi
echo "Simulation completed successfully. Generated counter.vcd."

# 4. Run Synthesis
echo "--- Step 2: Running Logic Synthesis ---"
if ! yosys -s synthesis.ys; then
    echo "ERROR: Synthesis failed!"
    exit 1
fi
echo "Synthesis completed successfully. Generated counter_synth.v."

# 5. Display Synthesized Output Netlist
echo "--- Step 3: Gate-Level Netlist Preview ---"
cat counter_synth.v
echo "----------------------------------------"

echo "=================================================="
echo "EDA Job Completed Successfully!"
echo "=================================================="
exit 0
