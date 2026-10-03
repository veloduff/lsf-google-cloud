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
# LSF Task Runner for Multi-seed Regression - run_regression_task.sh
# =====================================================================
# Designed to be run inside an LSF Job Array.
# =====================================================================

# Ensure Conda EDA toolchain is exposed on PATH in non-login batch shells
export PATH="/opt/conda/envs/eda/bin:/opt/conda/bin:$PATH"

# Ensure LSB_JOBINDEX exists (default to 1 if run locally)
INDEX=${LSB_JOBINDEX:-1}
SEED=$((INDEX * 17 + 42)) # Generate a unique seed from array index

RUN_DIR="runs/run_${INDEX}"
mkdir -p "$RUN_DIR"
cd "$RUN_DIR" || exit 1

echo "=================================================="
echo "Starting Regression Task #$INDEX (Seed: $SEED)"
echo "Host: $(hostname)"
echo "Running in: $(pwd)"
echo "=================================================="

# Compile Verilog simulation binary inside the local run directory
# Note: we reference counter source files from parent directories
if ! iverilog -o counter_sim ../../counter.v ../../counter_tb.v; then
    echo "ERROR: Verilog compilation failed for task #$INDEX"
    exit 1
fi

# Execute simulation (passing seed as a runtime argument if testbench supports it)
if ! vvp counter_sim "+seed=$SEED"; then
    echo "ERROR: Simulation failed for task #$INDEX"
    exit 1
fi

# Run logic synthesis and save synthesized netlist locally
# Generate a local synthesis script that points to the correct Verilog source files
cat <<EOT > synthesis.ys
read_verilog ../../counter.v
hierarchy -check -top counter
synth
write_verilog counter_synth.v
EOT

if ! yosys -s synthesis.ys > synthesis.log 2>&1; then
    echo "ERROR: Synthesis failed for task #$INDEX (Check synthesis.log)"
    exit 1
fi

echo "Regression task #$INDEX completed successfully!"
echo "Generated counter.vcd and counter_synth.v in $(pwd)"
echo "=================================================="
exit 0
