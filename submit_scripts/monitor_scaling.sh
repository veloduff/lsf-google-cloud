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
# LSF Scaling Monitor Helper - monitor_scaling.sh
# =====================================================================
# Continuously monitors LSF jobs, host status, and Resource Connector.
# =====================================================================

if [ -z "${LSF_ENVDIR:-}" ]; then
    if [ -f "/opt/lsf/conf/profile.lsf" ]; then
        # shellcheck disable=SC1091
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
