#!/bin/sh
# This script:
#    - should be called as getRequestStatus.sh -f input.json
#    - exit with 0 if calling succeed and result will be in the stdOut
#    - exit with 1 if calling failed and error message will be in the stdOut
#
inJson=$2
scriptDir=`dirname $0`
homeDir="$(cd "$scriptDir" && cd .. && pwd)"

# check if the required Java version is installed
if [[ -n "$JAVA_HOME" ]] && [[ -x "$JAVA_HOME/bin/java" ]];  then
    _java="$JAVA_HOME/bin/java"
elif type -p java >/dev/null 2>&1; then
    _java=java
else
    echo "Java not installed. Google cloud provider plugin requires Java version 1.8 or up"
    exit 1
fi

if ! which bc > /dev/null; then
   echo -e "Command bc not found! please install \c"
fi
 
if [[ "$_java" ]]; then
    version=$("$_java" -version 2>&1 | awk -F '"' '/version/ {print $2}'|cut -f1-2 -d .)
    if (( $(echo "$version < 1.8" |bc -l) )); then
        echo "Java version error. Google cloud provider plugin requires Java version 1.8 or up"
        exit 1
    fi  
fi

# 1. Execute standard GcloudTool.jar and capture output
raw_output=$("$_java" $SCRIPT_OPTIONS -Dgoogle-home-dir="$homeDir" -jar "$homeDir/lib/GcloudTool.jar" --getRequestStatus "$homeDir" "$inJson" 2>&1)
rc=$?

if [ $rc -ne 0 ]; then
    echo "$raw_output"
    exit $rc
fi

# 2. Post-process JSON output with Python 3 to resolve null/missing status on bulk operations
python3 - "$raw_output" << 'EOF'
import sys
import json
import urllib.request
import urllib.error

raw_output = sys.argv[1]

try:
    data = json.loads(raw_output)
except Exception:
    print(raw_output)
    sys.exit(0)

requests = data.get("requests", [])
token = None
project = None
zone = None

def get_gcp_operation(op_id):
    global token, project, zone
    try:
        if not token:
            tok_req = urllib.request.Request(
                "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token",
                headers={"Metadata-Flavor": "Google"}
            )
            with urllib.request.urlopen(tok_req, timeout=3) as resp:
                token = json.loads(resp.read().decode())["access_token"]
            
            proj_req = urllib.request.Request(
                "http://metadata.google.internal/computeMetadata/v1/project/project-id",
                headers={"Metadata-Flavor": "Google"}
            )
            with urllib.request.urlopen(proj_req, timeout=3) as resp:
                project = resp.read().decode().strip()
                
            zone_req = urllib.request.Request(
                "http://metadata.google.internal/computeMetadata/v1/instance/zone",
                headers={"Metadata-Flavor": "Google"}
            )
            with urllib.request.urlopen(zone_req, timeout=3) as resp:
                zone = resp.read().decode().strip().split("/")[-1]
        
        url = "https://compute.googleapis.com/compute/v1/projects/%s/zones/%s/operations/%s" % (project, zone, op_id)
        op_req = urllib.request.Request(url, headers={"Authorization": "Bearer %s" % token})
        with urllib.request.urlopen(op_req, timeout=5) as resp:
            return json.loads(resp.read().decode())
    except Exception:
        return None

for req in requests:
    status = req.get("status")
    machines = req.get("machines")
    req_id = req.get("requestId", "")
    
    # Inspect GCP operation if status is missing/invalid or marked complete with 0 machines created
    needs_check = (
        not status or 
        status not in ("running", "complete", "complete_with_error") or 
        (status == "complete" and (machines is None or len(machines) == 0))
    )
    
    if needs_check and req_id.startswith("operation-"):
        op = get_gcp_operation(req_id)
        if op:
            op_status = op.get("status")
            if op_status in ("PENDING", "RUNNING"):
                req["status"] = "running"
            elif op_status == "DONE":
                if op.get("error") or op.get("httpErrorStatusCode", 200) >= 400:
                    req["status"] = "complete_with_error"
                    errs = [e.get("message", "") for e in op.get("error", {}).get("errors", [])]
                    req["message"] = "; ".join(errs) or "GCP bulkInsert operation failed"
                else:
                    req["status"] = "complete"
            else:
                req["status"] = "complete_with_error"
        else:
            req["status"] = "complete_with_error"
        
        if "machines" not in req or req["machines"] is None:
            req["machines"] = []

print(json.dumps(data, indent=2))
EOF
