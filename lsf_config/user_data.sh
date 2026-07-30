#!/bin/sh
# =====================================================================
# LSF Resource Connector - GCP Worker Startup Script (user_data.sh)
# =====================================================================

logfile=/tmp/user_data.log
echo "STARTING LSF DYNAMIC WORKER SETUP: $(date)" > $logfile

# 1. Export user data variables defined in the template (injected by LSF)
%EXPORT_USER_DATA%

echo "Injected variables: rc_account=${rc_account}, eda_type=${eda_type}, pricing=${pricing}" >> $logfile

# 2. Disable OS firewall so Master LIM can verify the host
echo "Disabling OS firewall..." >> $logfile
systemctl stop firewalld 2>/dev/null || true
systemctl disable firewalld 2>/dev/null || true

# 3. Configure hosts file to locate the LSF Master and Submit VM
echo "10.10.0.10 master.onprem.local master" >> /etc/hosts
echo "10.10.0.2 submit.onprem.local submit" >> /etc/hosts
local_ip=$(hostname -I | awk '{print $1}')
echo "$local_ip $(hostname)" >> /etc/hosts

# 4. Export PATH to expose pre-installed Conda and EDA tools
export PATH="/opt/conda/envs/eda/bin:/opt/conda/bin:$PATH"

# 6. Mount shared LSF and Home directories from Master with retry loop
echo "Mounting NFS directories from LSF Master..." >> $logfile
mkdir -p /opt/lsf
systemctl start rpcbind || true

until mount -t nfs -o rw,hard,noatime,rsize=1048576,wsize=1048576,timeo=600,retrans=2 10.10.0.10:/opt/lsf /opt/lsf >> $logfile 2>&1; do
    echo "Waiting for NFS /opt/lsf mount from 10.10.0.10..." >> $logfile
    sleep 3
done

until mount -t nfs -o rw,hard,noatime,rsize=1048576,wsize=1048576,timeo=600,retrans=2 10.10.0.10:/home /home >> $logfile 2>&1; do
    echo "Waiting for NFS /home mount from 10.10.0.10..." >> $logfile
    sleep 3
done

# 6.1 Synchronize local user accounts from shared /home
echo "Syncing user accounts from shared /home..." >> $logfile
for udir in /home/*; do
    if [ -d "$udir" ]; then
        uname=$(basename "$udir")
        uid=$(stat -c "%u" "$udir")
        gid=$(stat -c "%g" "$udir")
        groupadd -g $gid $uname 2>/dev/null || true
        useradd -u $uid -g $gid -d $udir -s /bin/bash $uname 2>/dev/null || true
        echo "Synced user: $uname (UID: $uid, GID: $gid)" >> $logfile
    fi
done

# 8. Source LSF profile first to populate paths
. /opt/lsf/conf/profile.lsf

# 7. Set up local LSF configuration override
echo "Configuring local LSF environment..." >> $logfile
mkdir -p /etc/lsf
export LSF_ENVDIR=/etc/lsf

# Copy base lsf.conf to local directory
cp /opt/lsf/conf/lsf.conf /etc/lsf/lsf.conf

# Append dynamic host resources to local lsf.conf
echo "LSF_LOCAL_RESOURCES=\"[resource googlehost] [resourcemap ${rc_account}*rc_account] [resourcemap ${eda_type}*eda_type]\"" >> /etc/lsf/lsf.conf
echo "LSF_ENVDIR=/etc/lsf" >> /etc/lsf/lsf.conf

echo "Local lsf.conf contents:" >> $logfile
cat /etc/lsf/lsf.conf >> $logfile

# 9. Start LSF Daemons
echo "Starting LSF Daemons..." >> $logfile
$LSF_SERVERDIR/lim >> $logfile 2>&1
$LSF_SERVERDIR/res >> $logfile 2>&1
$LSF_SERVERDIR/sbatchd >> $logfile 2>&1

echo "LSF DYNAMIC WORKER SETUP COMPLETE: $(date)" >> $logfile
