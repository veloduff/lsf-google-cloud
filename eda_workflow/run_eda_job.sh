#!/bin/bash
# =====================================================================
# EDA Execution Script - run_eda_job.sh
# =====================================================================

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
iverilog -o counter_sim counter.v counter_tb.v
if [ $? -ne 0 ]; then
    echo "ERROR: Verilog compilation failed!"
    exit 1
fi

vvp counter_sim
if [ $? -ne 0 ]; then
    echo "ERROR: Simulation execution failed!"
    exit 1
fi
echo "Simulation completed successfully. Generated counter.vcd."

# 4. Run Synthesis
echo "--- Step 2: Running Logic Synthesis ---"
yosys -s synthesis.ys
if [ $? -ne 0 ]; then
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
