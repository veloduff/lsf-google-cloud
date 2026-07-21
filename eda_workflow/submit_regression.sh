#!/bin/bash
# =====================================================================
# LSF Submission Wrapper - submit_regression.sh
# =====================================================================
# Submits a regression suite as an LSF Job Array.
# =====================================================================

if [ -z "$LSF_ENVDIR" ]; then
    if [ -f "/opt/lsf/conf/profile.lsf" ]; then
        . /opt/lsf/conf/profile.lsf
    else
        echo "ERROR: LSF profile not found. Sourcing profile failed."
        exit 1
    fi
fi

# Submit a 100-job array to the eda queue
# -J "eda_regress[1-100]": Creates a 100-index job array
# -R "select[googlehost] rusage[mem=4096]": Targets cloud worker nodes with 4GB memory reservation
# -o logs/out_%J_%I.log: Directs output stdout to logs/out_<JOBID>_<INDEX>.log
# -e logs/err_%J_%I.log: Directs stderr output
mkdir -p logs

echo "Submitting 100-task EDA regression sweep to LSF..."
bsub -q eda \
     -R "select[googlehost] rusage[mem=4096]" \
     -J "eda_regress[1-100]" \
     -o "logs/out_%J_%I.log" \
     -e "logs/err_%J_%I.log" \
     ./run_regression_task.sh

echo "Use 'bjobs' to monitor the job array tasks."
echo "Outputs will be written to eda_workflow/runs/run_<INDEX>/"
