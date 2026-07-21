#!/bin/bash
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
echo "Executing on hosts: ${LSB_MCPU_HOSTS}"
echo "=================================================="

# Run parallel workload (in this case, sleep 900)
sleep 900

echo "=================================================="
echo "LSF Parallel Job Complete: $(date)"
echo "=================================================="
