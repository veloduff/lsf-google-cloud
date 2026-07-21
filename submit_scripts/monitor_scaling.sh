#!/bin/bash
# =====================================================================
# LSF Scaling Monitor Helper - monitor_scaling.sh
# =====================================================================
# Continuously monitors LSF jobs, host status, and Resource Connector.
# =====================================================================

if [ -z "$LSF_ENVDIR" ]; then
    if [ -f "/opt/lsf/conf/profile.lsf" ]; then
        . /opt/lsf/conf/profile.lsf
    fi
fi

clear
echo "=================================================="
echo "LSF Auto-Scaling Live Monitor (Press Ctrl+C to exit)"
echo "=================================================="

while true; do
    echo "--- [$(date +%T)] LSF Active Jobs ---"
    bjobs -w 2>/dev/null || echo "No active jobs."
    
    echo ""
    echo "--- LSF Cluster Hosts ---"
    bhosts 2>/dev/null
    
    echo ""
    echo "--- Resource Connector Dynamic Allocation Status ---"
    bhosts -rc 2>/dev/null || bhosts -a 2>/dev/null
    
    echo "=================================================="
    sleep 5
    clear
done
