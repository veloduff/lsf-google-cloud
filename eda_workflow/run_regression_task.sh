#!/bin/bash
# =====================================================================
# LSF Task Runner for Multi-seed Regression - run_regression_task.sh
# =====================================================================
# Designed to be run inside an LSF Job Array.
# =====================================================================

# Ensure LSB_JOBINDEX exists (default to 1 if run locally)
INDEX=${LSB_JOBINDEX:-1}
SEED=$((INDEX * 17 + 42)) # Generate a unique seed from array index

RUN_DIR="runs/run_${INDEX}"
mkdir -p "$RUN_DIR"
cd "$RUN_DIR"

echo "=================================================="
echo "Starting Regression Task #$INDEX (Seed: $SEED)"
echo "Host: $(hostname)"
echo "Running in: $(pwd)"
echo "=================================================="

# Compile Verilog simulation binary inside the local run directory
# Note: we reference counter source files from parent directories
iverilog -o counter_sim ../../counter.v ../../counter_tb.v
if [ $? -ne 0 ]; then
    echo "ERROR: Verilog compilation failed for task #$INDEX"
    exit 1
fi

# Execute simulation (passing seed as a runtime argument if testbench supports it)
vvp counter_sim +seed=$SEED
if [ $? -ne 0 ]; then
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

yosys -s synthesis.ys > synthesis.log 2>&1
if [ $? -ne 0 ]; then
    echo "ERROR: Synthesis failed for task #$INDEX (Check synthesis.log)"
    exit 1
fi

echo "Regression task #$INDEX completed successfully!"
echo "Generated counter.vcd and counter_synth.v in $(pwd)"
echo "=================================================="
exit 0
