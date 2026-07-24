# Hybrid LSF EDA Environment: On-Premise to GCP Cloud Bursting

This repository serves as a blueprint and configuration reference to help customers launch and configure a hybrid Electronic Design Automation (EDA) environment. It demonstrates how an on-premises semiconductor design team can leverage **IBM Spectrum LSF** and the **LSF Resource Connector** to burst EDA workloads into **Google Cloud Platform (GCP)**.

The environment is configured to run a complete, modern open-source EDA toolchain on dynamically provisioned GCP Compute Engine instances:
*   **Icarus Verilog (`iverilog`)**: Simulation & verification.
*   **Yosys**: RTL synthesis.
*   **Verilator**: High-performance cycle-accurate simulation.
*   **OpenROAD**: Automated RTL-to-GDSII physical design (placement & routing).
*   **Magic**: VLSI layout editor and Design Rule Checking (DRC).
*   **Netgen**: Layout vs. Schematic (LVS) netlist comparison.
*   **GTKWave**: Waveform viewer for analyzing simulation VCD dumps.

---

## Table of Contents
1. [IBM Spectrum LSF Licensed Software Requirements](#1-ibm-spectrum-lsf-licensed-software-requirements)
2. [Hybrid Cloud Architecture](#2-hybrid-cloud-architecture)
3. [Environment Blueprint](#3-environment-blueprint)
4. [Deployment & Setup Guide](#4-deployment--setup-guide)
5. [Cluster Verification & Functional Demonstrations](#5-cluster-verification--functional-demonstrations)
6. [Production Optimization: Pre-Baking Golden Images](#6-production-optimization-pre-baking-golden-images)
7. [Teardown & Clean-Up Guide](#7-teardown--clean-up-guide)

---

## 1. IBM Spectrum LSF Licensed Software Requirements

> [!IMPORTANT]
> **IBM Spectrum LSF is proprietary licensed software owned by IBM**. 
> 
> **No LSF installer packages, distribution binaries, or license entitlement files are bundled in this repository.** Customers and users are responsible for obtaining their own valid IBM Spectrum LSF 10.1 software packages and cluster entitlement files from their IBM Passport Advantage account or authorized IBM representative.

If you are performing a fresh installation from scratch (rather than deploying from pre-built Golden Images), you must create a local `Install_Files/` directory in the root of this repository and supply the following 4 customer-provided archives before running the upload and setup scripts:

<table width="100%">
  <thead>
    <tr>
      <th align="left" width="50%" style="min-width: 420px; white-space: nowrap;" nowrap>Customer-Supplied Filename</th>
      <th align="left" width="20%">Required / Optional</th>
      <th align="left" width="30%">Description</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td style="white-space: nowrap;" nowrap><strong><code>lsf_std_entitlement.dat</code></strong></td>
      <td><strong>Required</strong></td>
      <td>Customer's Standard Edition cluster license entitlement file.</td>
    </tr>
    <tr>
      <td style="white-space: nowrap;" nowrap><strong><code>lsf10.1_lsfinstall_linux_x86_64.tar.Z</code></strong></td>
      <td><strong>Required</strong></td>
      <td>LSF 10.1 base installer execution scripts and configuration wizards.</td>
    </tr>
    <tr>
      <td style="white-space: nowrap;" nowrap><strong><code>lsf10.1_lnx310-lib217-x86_64.tar.Z</code></strong></td>
      <td><strong>Required</strong></td>
      <td>Core LSF 10.1 distribution binaries for Linux (x86_64).</td>
    </tr>
    <tr>
      <td style="white-space: nowrap;" nowrap><strong><code>lsf10.1_lnx310-lib217-x86_64-602430.tar.Z</code></strong></td>
      <td><strong>Required</strong></td>
      <td>Cumulative LSF Service Pack 15 (SP15) update package (provides the LSF Resource Connector for GCP).</td>
    </tr>
  </tbody>
</table>

*(Note: If you are deploying the cluster using pre-built **Golden Images** where LSF binaries have already been pre-installed into the VM disk image, the `Install_Files/` directory is not needed.)*

---

## 2. Hybrid Cloud Architecture

The hybrid cloud environment replicates a classic enterprise setup:
- **On-Premise (Simulated)**: A dedicated VPC (`onprem-vpc`) hosting the LSF Management (Master) node and an LSF Submission/Login host. This represents the physical data center.
- **GCP Cloud**: A separate VPC (`cloud-vpc`) where the LSF Resource Connector dynamically provisions worker nodes in response to pending jobs.
- **Connectivity**: The two VPCs are connected via **VPC Network Peering**, enabling private, secure, low-latency communication.

```mermaid
flowchart TD
    subgraph onprem_vpc ["On-Premises VPC (Simulated)"]
        submit_host["LSF Submit Host<br>(submit.onprem.local)"]
        master_host["LSF Management Host<br>(master.onprem.local)<br>- mbatchd, mbschd, ebrokerd"]
        nfs_server["NFS Server<br>(Shared /opt/lsf & /home)"]
    end

    subgraph cloud_vpc ["GCP Cloud VPC"]
        subgraph worker_pool ["Dynamic Worker Pool"]
            worker_1["LSF Worker 1<br>(c2-standard-4 - Spot)"]
            worker_2["LSF Worker 2<br>(n2-standard-8 - Spot)"]
            worker_n["LSF Worker N<br>(n2-highmem-16 - On-Demand)"]
        end
        gcs_bucket[("GCS Bucket<br>(lsf-install-bucket)")]
    end

    %% Communications
    submit_host -- "bsub -q eda" --> master_host
    master_host -- "LSF Resource Connector<br>(GCP API Call)" --> worker_1
    master_host -- "LSF Resource Connector" --> worker_2
    
    %% Peering / NFS Mounts
    nfs_server -. "Mount /home & /opt/lsf<br>(via VPC Peering)" .-> worker_1
    nfs_server -. "Mount /home & /opt/lsf" .-> worker_2
    
    %% Worker startup
    worker_1 -- "Download EDA Tools" --> gcs_bucket
    worker_2 -- "Download EDA Tools" --> gcs_bucket
```

### 2.1 Provisioned Infrastructure & Cluster Components

When you deploy this environment, the Terraform configurations and LSF setup scripts automatically build the following components:

*   **LSF Management Host (`master`)**: A virtual machine in the simulated on-prem network running the LSF core scheduling daemons (`lim`, `res`, `sbatchd`, `mbatchd`, `mbschd`) and the Resource Connector broker daemon (`ebrokerd`).
*   **LSF Submission Host (`submit`)**: A virtual machine serving as the user login node from which design engineers submit and monitor batch workloads.
*   **Shared NFS Server**: Configured directly on the Master VM, this exports and shares the `/opt/lsf` binaries and `/home` directories across peered VPC networks to all dynamic workers.
*   **GCS Storage Bucket**: A secure Google Cloud Storage bucket that holds the LSF installation packages and setup configs for worker node provisioning.
*   **Dynamic Worker Pool**: GCE virtual machines (e.g. `compute-*`) spun up on-demand by the LSF Resource Connector, running Rocky Linux 8 and pre-configured to mount `/opt/lsf` and `/home` over the network on boot.
*   **VPC Peering & Cloud DNS Peering**: Peers the simulated on-prem and cloud VPCs together with private IP routing. It also configures Cloud DNS Peering (forward and reverse zones) to enable private hostname resolution between the networks, allowing dynamic cloud workers to resolve and communicate with the on-prem Master (and vice-versa) over secure firewall rules mapped to LSF ports (`7869`, `6878`, `6882`) and NFS (`2049`).

---

### 3. Environment Blueprint

To set up and validate this environment, the repository provides two core functional testing suites and supporting infrastructure:
1. **Terraform Infrastructure** ([terraform/](terraform)): Automates VPCs, Subnets, VPC Peering, Cloud NAT, Cloud DNS Peering, IAM Service Accounts, GCS Buckets, and simulated On-Premises LSF Master and Submit VMs.
2. **LSF Configurations** ([lsf_config/](lsf_config)): Configurations for the LSF cluster, including Resource Connector templates customized for dynamic GCP cloud bursting.
3. **Component 1: Cloud Auto-Scaling Suite** ([submit_scripts/](submit_scripts)): Contains job submission scripts and real-time monitoring tools designed to test concurrent dynamic scaling limits (such as launching 10 instances / 20 slots simultaneously and watching them terminate when idle).
4. **Component 2: Parallel EDA Workloads & Regressions** ([eda_workflow/](eda_workflow)): A sample semiconductor digital design project (Verilog counter, self-checking testbench, Yosys synthesis, and 100-task parallel regression sweep) to verify real hardware design tools across the cluster.
5. **Golden Image Guide** ([GOLDEN_IMAGE.md](GOLDEN_IMAGE.md)): Complete instructions and automation scripts to build the custom GCE worker image pre-loaded with open-source EDA toolchains.

---

## 4. Deployment & Setup Guide

### Step 4.0: Google Cloud Authentication & Environment Setup
1. Authenticate your local `gcloud` CLI and Application Default Credentials (ADC) sessions:
   ```bash
   gcloud auth login
   gcloud auth application-default login
   ```
2. **Persist your environment parameters in code**: Copy `terraform/terraform.tfvars.example` to `terraform/terraform.tfvars` and set your GCP Project ID, region, zone, and custom bucket details:
   ```bash
   cp terraform/terraform.tfvars.example terraform/terraform.tfvars
   ```
   Edit `terraform/terraform.tfvars` to set your desired parameters (these will automatically persist across all Terraform commands and helper scripts):
   ```hcl
   project_id      = "your-gcp-project-id"
   region          = "us-central1"
   zone            = "us-central1-a"
   bucket_name     = "your-custom-gcs-bucket-name" # Optional
   bucket_location = "US"                        # Optional
   ```
   *(Alternatively, you can export environment variables such as `export TF_VAR_project_id="your-gcp-project-id"`, `export TF_VAR_region="your-region"`, `export TF_VAR_bucket_name="your-bucket"`).*

### Step 4.0b: Run Pre-Flight Checks
Next, run our automated pre-flight check script to verify that your CLI tools, active authentication sessions (CLI & ADC), project APIs, and LSF installer archives are ready (it automatically reads from `terraform/terraform.tfvars`):
```bash
./preflight.sh
```
Example successful output:
```text
==================================================
LSF Hybrid Cloud: Pre-Flight Check
==================================================
1. Checking required CLI tools (terraform, gcloud)... PASSED
2. Checking Google Cloud authentication & ADC token... PASSED
3. Checking access to GCP Project 'your-gcp-project-id'... PASSED
4. Verifying required GCP APIs (compute, iam, storage)...
   -> API enabled: compute.googleapis.com
   -> API enabled: iam.googleapis.com
   -> API enabled: storage.googleapis.com
   -> API enabled: iamcredentials.googleapis.com
5. Checking for customer-supplied LSF installer archives in Install_Files/... PASSED (or SKIPPED if using Golden Images)
==================================================
ALL PRE-FLIGHT CHECKS PASSED!
You are ready to deploy: cd terraform && terraform apply
==================================================
```
*If your credentials have expired or required APIs are disabled, the script will catch it immediately and instruct you on how to resolve it before running Terraform.*

### Step 4.1: Deploy the Cloud Infrastructure
1. Navigate to the `terraform` directory:
   ```bash
   cd terraform
   ```
2. Initialize Terraform and apply the plan (Terraform automatically reads `terraform.tfvars`):
   ```bash
   terraform init
   terraform apply
   ```
   *This automatically provisions the VPC networks, Cloud NAT, GCS Bucket, and launches the initial Master and Submit VMs using standard public Rocky Linux 8 base images.*

### Step 4.1b: Using Existing VPCs (Optional)
By default, the provided Terraform scripts automatically **create two new VPCs from scratch** (`lsf-onprem-vpc` and `lsf-cloud-vpc`) and peer them together. If you prefer to deploy into **existing VPC networks**, make the following 3 adjustments before running:
1. **In LSF Resource Connector Templates ([`lsf_config/googleprov_templates.json`](lsf_config/googleprov_templates.json))**:
   Update the `"vpc"` and `"subnetId"` fields across all templates to match your existing GCP network and subnetwork names:
   ```json
   "vpc": "your-existing-vpc-name",
   "subnetId": "your-existing-subnet-name"
   ```
2. **In LSF Cluster Address Rules ([`lsf_config/lsf.cluster.eda_cluster`](lsf_config/lsf.cluster.eda_cluster))**:
   Update `LSF_HOST_ADDR_RANGE` to include the CIDR range of your existing subnet(s) so LSF allows dynamic worker VMs from that network to join:
   ```ini
   LSF_HOST_ADDR_RANGE = 10.0.* 192.168.*
   ```
3. **In Firewall Rules**:
   Ensure your existing VPC has firewall rules allowing TCP/UDP port `7869` (LIM), TCP port `6878` (RES), TCP port `6882` (sbatchd), and TCP port `2049` (NFS) between your LSF Master/Submit hosts and the cloud worker subnet.

### Step 4.2: Upload LSF Installers & Configs to GCS Bucket
We have provided an automated upload script ([`upload_assets.sh`](upload_assets.sh)) that retrieves the bucket name directly from Terraform and handles the entire upload process using the fast Google Cloud Storage CLI.
From the project root directory (navigate back from the `terraform` directory first), run:
```bash
cd ..
./upload_assets.sh
```
Example successful output:
```text
==================================================
LSF Hybrid Cloud: Uploading Assets to GCS
==================================================
Retrieving GCS bucket name from Terraform state...
Target bucket: gs://lsf-install-bucket-xxxxxx
Verifying local installer files...
Uploading customer-supplied LSF installers...
Copying file://Install_Files/lsf_std_entitlement.dat to gs://lsf-install-bucket-xxxxxx/lsf_std_entitlement.dat
Copying file://Install_Files/lsf10.1_lsfinstall_linux_x86_64.tar.Z to gs://lsf-install-bucket-xxxxxx/lsf10.1_lsfinstall_linux_x86_64.tar.Z
Copying file://Install_Files/lsf10.1_lnx310-lib217-x86_64.tar.Z to gs://lsf-install-bucket-xxxxxx/lsf10.1_lnx310-lib217-x86_64.tar.Z
Copying file://Install_Files/lsf10.1_lnx310-lib217-x86_64-602430.tar.Z to gs://lsf-install-bucket-xxxxxx/lsf10.1_lnx310-lib217-x86_64-602430.tar.Z
Uploading LSF configuration directory...
Copying file://lsf_config/user_data.sh to gs://lsf-install-bucket-xxxxxx/lsf_config/user_data.sh
Copying file://lsf_config/lsb.resources to gs://lsf-install-bucket-xxxxxx/lsf_config/lsb.resources
Copying file://lsf_config/lsb.hosts to gs://lsf-install-bucket-xxxxxx/lsf_config/lsb.hosts
Copying file://lsf_config/lsf.conf to gs://lsf-install-bucket-xxxxxx/lsf_config/lsf.conf
Copying file://lsf_config/lsb.modules to gs://lsf-install-bucket-xxxxxx/lsf_config/lsb.modules
Copying file://lsf_config/lsb.queues to gs://lsf-install-bucket-xxxxxx/lsf_config/lsb.queues
Copying file://lsf_config/googleprov_templates.json to gs://lsf-install-bucket-xxxxxx/lsf_config/googleprov_templates.json
Copying file://lsf_config/googleprov_config.json to gs://lsf-install-bucket-xxxxxx/lsf_config/googleprov_config.json
Copying file://lsf_config/build_golden_image.sh to gs://lsf-install-bucket-xxxxxx/lsf_config/build_golden_image.sh
Copying file://lsf_config/lsf.shared to gs://lsf-install-bucket-xxxxxx/lsf_config/lsf.shared
Copying file://lsf_config/hostProviders.json to gs://lsf-install-bucket-xxxxxx/lsf_config/hostProviders.json
Copying file://lsf_config/lsf.cluster.eda_cluster to gs://lsf-install-bucket-xxxxxx/lsf_config/lsf.cluster.eda_cluster
Copying file://lsf_config/setup_master.sh to gs://lsf-install-bucket-xxxxxx/lsf_config/setup_master.sh
Uploading EDA sample workflow directory...
Copying file://eda_workflow/submit_regression.sh to gs://lsf-install-bucket-xxxxxx/eda_workflow/submit_regression.sh
Copying file://eda_workflow/synthesis.ys to gs://lsf-install-bucket-xxxxxx/eda_workflow/synthesis.ys
Copying file://eda_workflow/submit_eda_job.sh to gs://lsf-install-bucket-xxxxxx/eda_workflow/submit_eda_job.sh
Copying file://eda_workflow/run_eda_job.sh to gs://lsf-install-bucket-xxxxxx/eda_workflow/run_eda_job.sh
Copying file://eda_workflow/run_regression_task.sh to gs://lsf-install-bucket-xxxxxx/eda_workflow/run_regression_task.sh
Copying file://eda_workflow/counter.v to gs://lsf-install-bucket-xxxxxx/eda_workflow/counter.v
Copying file://eda_workflow/counter_tb.v to gs://lsf-install-bucket-xxxxxx/eda_workflow/counter_tb.v
Uploading Submit & Scaling test scripts directory...
Copying file://submit_scripts/scale_10_job.sh to gs://lsf-install-bucket-xxxxxx/submit_scripts/scale_10_job.sh
Copying file://submit_scripts/submit_scale_10.sh to gs://lsf-install-bucket-xxxxxx/submit_scripts/submit_scale_10.sh
Copying file://submit_scripts/monitor_scaling.sh to gs://lsf-install-bucket-xxxxxx/submit_scripts/monitor_scaling.sh
==================================================
ALL ASSETS UPLOADED SUCCESSFULLY TO:
gs://lsf-install-bucket-xxxxxx/
==================================================
```

### Step 4.3: Install & Configure the LSF Master (On-Prem)
We have provided an automated installation script ([`lsf_config/setup_master.sh`](lsf_config/setup_master.sh)) that silently installs LSF, applies the EDA and GCP Resource Connector configurations, and starts the cluster daemons.
1. SSH into the LSF Master VM using our automated helper script (auto-detects project & zone from `terraform/terraform.tfvars` or GCE):
   ```bash
   ./ssh_master.sh
   ```
   *(Or manually with auto-detected zone: `gcloud compute ssh lsf-master --zone=$(gcloud compute instances list --filter="name=lsf-master" --format="value(zone)") --tunnel-through-iap`)*
2. Download the configuration folder from GCS and run the automated setup script:
   ```bash
   BUCKET_NAME=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/attributes/lsf_bucket)
   gcloud storage cp -r gs://$BUCKET_NAME/lsf_config ./
   sudo bash ./lsf_config/setup_master.sh
   ```
3. Once the script finishes, source your LSF environment and verify that the master host is up and accepting jobs:
   ```bash
   source /opt/lsf/conf/profile.lsf
   lsid
   bhosts
   ```

#### About the `setup_master.sh` Script & Daemon Management

The [`lsf_config/setup_master.sh`](lsf_config/setup_master.sh) script handles the complete bootstrapping of the LSF Master node:
1.  **Extracts LSF binaries**: Automates the base installation and applies cumulative Service Pack 15 patches silently.
2.  **Applies Cluster Configurations**: Configures queues, resource limits, host metrics, and dynamically substitutes GCE template metadata.
3.  **Sanitizes Event History**: Wipes historical job logs and accounting records under `/opt/lsf/work` to guarantee a clean scheduler state starting at Job ID 1.
4.  **Configures eauth SUID permissions**: Grants root ownership and SUID execute permissions to the `eauth` authentication binary.
5.  **Initializes LSF Cluster Daemons**: Starts the core cluster services (`lim`, `res`, and `sbatchd`).

---

## 5. Cluster Verification & Functional Demonstrations

Once your LSF Master and Submit VMs are up, log into the Submit host to execute the two functional demonstration components:

```bash
./ssh_submit.sh
```
*(Both `submit_scripts/` and `eda_workflow/` are automatically populated in `/home/lsfadmin/` during Master VM setup and shared to the Submit host via NFS.)*

---

### Component 1: Dynamic Cloud Auto-Scaling (Spinning Instances Up & Down)

This component demonstrates pure cloud bursting elasticity: requesting concurrent execution slots, watching LSF Resource Connector provision GCE worker VMs dynamically in GCP, and observing automatic instance termination when the workload completes.

#### 1. Submit a Scaling Job Request
Navigate to the `submit_scripts` directory and launch a 20-slot parallel batch job:
```bash
cd /home/lsfadmin/submit_scripts
./submit_scale_10.sh
```
*This requests 20 concurrent slots on the `eda` queue (`-n 20`). Since each `c2-standard-4` template exposes 2 slots, LSF triggers the simultaneous provisioning of 10 dynamic worker VMs in GCP.*

#### 2. Visual GCP Console Progression
Watch the Compute Engine Console as LSF automatically scales the dynamic worker pool:

* **Idle Cluster Baseline**: Only the static `lsf-master` and `lsf-submit` VMs are active in the on-premises subnet (`10.10.0.0/16`):
![Idle Cluster Baseline in GCP Console](docs/images/gcp_console_idle.png)

* **Dynamically Scaled Cluster**: When the parallel workload is submitted, the LSF Resource Connector automatically provisions 10 dynamic `c2-standard-4` worker instances (`compute-*`) in the cloud worker subnet (`10.20.0.0/16`):
![Scaled-Up Dynamic Worker Pool in GCP Console](docs/images/gcp_console_scaled.png)

#### 3. Live Dashboard & CLI Monitoring
We provide a live terminal dashboard script to monitor job queueing, VM provisioning, and host registrations in real time:
```bash
./monitor_scaling.sh
```

You can also monitor the scaling lifecycle via standard LSF and GCP commands:
*   **Check Queued Demand**: `bjobs -p` (*Shows `Queue's resource connector demand is triggering host allocation`*).
*   **Check Resource Connector Status**: `bhosts -rc` (*Shows instances currently being requested from GCP*).
*   **Watch GCP VM Provisioning**: In your local machine terminal, run `gcloud compute instances list` to watch `lsf-gcp-eda-sim-spot-xxxx` VMs transition from `PROVISIONING` to `RUNNING`.
*   **Watch Scale-Down**: Once the job finishes, the instances remain idle for 2 minutes (`provHostIdleDelay`) and are automatically deleted by LSF Resource Connector.

#### 4. Example Auto-Scaling Lifecycle Output
Here is the expected terminal output showing the complete auto-scaling progression—from initial queue demand (`PEND`), dynamic provisioning across 10 GCE cloud worker hosts (`compute-worker001` .. `compute-worker010`), parallel workload execution (`RUN`), and automatic cloud scale-down back to only the static master host:

```text
[lsfadmin@submit submit_scripts]$ bjobs
JOBID   USER    STAT  QUEUE      FROM_HOST   EXEC_HOST   JOB_NAME   SUBMIT_TIME
1       lsfadmi PEND  eda        submit                  *_10_hosts Jul 21 18:48

[lsfadmin@submit submit_scripts]$ bjobs
JOBID   USER    STAT  QUEUE      FROM_HOST   EXEC_HOST   JOB_NAME   SUBMIT_TIME
1       lsfadmi RUN   eda        submit      compute-wor *_10_hosts Jul 21 18:48
                                             compute-worker008
                                             compute-worker007
                                             compute-worker007
                                             compute-worker003
                                             compute-worker003
                                             compute-worker004
                                             compute-worker004
                                             compute-worker005
                                             compute-worker005
                                             compute-worker009
                                             compute-worker009
                                             compute-worker002
                                             compute-worker002
                                             compute-worker001
                                             compute-worker001
                                             compute-worker006
                                             compute-worker006
                                             compute-worker010
                                             compute-worker010

[lsfadmin@submit submit_scripts]$ bhosts
HOST_NAME          STATUS       JL/U    MAX  NJOBS    RUN  SSUSP  USUSP    RSV
compute-worker001  closed          -      2      2      2      0      0      0
compute-worker002  closed          -      2      2      2      0      0      0
compute-worker003  closed          -      2      2      2      0      0      0
compute-worker004  closed          -      2      2      2      0      0      0
compute-worker005  closed          -      2      2      2      0      0      0
compute-worker006  closed          -      2      2      2      0      0      0
compute-worker007  closed          -      2      2      2      0      0      0
compute-worker008  closed          -      2      2      2      0      0      0
compute-worker009  closed          -      2      2      2      0      0      0
compute-worker010  closed          -      2      2      2      0      0      0
master             ok              -      4      0      0      0      0      0

[lsfadmin@submit submit_scripts]$ bqueues
QUEUE_NAME      PRIO STATUS          MAX JL/U JL/P JL/H NJOBS  PEND   RUN  SUSP
eda              30  Open:Active       -    -    -    -    20     0    20     0
normal           20  Open:Active       -    -    -    -     0     0     0     0

# Once the job completes and the idle timeout expires (automatic scale-down):
[lsfadmin@submit submit_scripts]$ bhosts
HOST_NAME          STATUS       JL/U    MAX  NJOBS    RUN  SSUSP  USUSP    RSV
master             ok              -      4      0      0      0      0      0
```

---

### Component 2: Parallel EDA Workloads & Multi-Seed Regressions

This component demonstrates real semiconductor workflows: hardware simulation, logic synthesis, and large-scale parallel regression test sweeps across the dynamic cloud cluster.

#### 1. Test the EDA Tools Locally
Verify that the open-source EDA toolchain (`iverilog`, `vvp`, `yosys`) operates correctly on the submit host:
```bash
cd /home/lsfadmin/eda_workflow
./run_eda_job.sh
```
*Confirms that the Verilog counter testbench passes (generating `counter.vcd`) and Yosys performs logic synthesis (generating `counter_synth.v` with a gate-level netlist preview).*

#### 2. Submit a Single Cloud-Bursted EDA Job
Submit an individual simulation and synthesis job to the cluster:
```bash
./submit_eda_job.sh
```
*Queues a job reserving 8 GB RAM (`rusage[mem=8192]`). LSF spins up a dynamic cloud worker, runs the workflow, and writes the output logs to `eda_job_<JOBID>.out`.*

#### 3. Run a 100-Task Parallel Regression Sweep
Run an industry-standard multi-seed regression suite using an LSF Job Array (`-J "eda_regress[1-100]"`):
```bash
./submit_regression.sh
```
*How it works*:
*   LSF creates a 100-task job array, distributing tasks across the dynamically provisioned cloud workers.
*   Each task executes `run_regression_task.sh`, reading `$LSB_JOBINDEX` to generate a unique random test seed.
*   Outputs for each task are isolated in separate sandboxes (`runs/run_1/` through `runs/run_100/`), preventing file collisions on the shared NFS storage.
*   Monitor array progress using `bjobs` or `bjobs -A`.

---

## 6. Production Optimization: Pre-Baking Golden Images

In the baseline deployment above, dynamic cloud workers download configuration assets and install tools during their initial startup. For enterprise production clusters, you can eliminate on-boot package downloads and significantly accelerate worker launch times by **pre-baking custom Google Compute Engine Golden Images**.

### Benefits of Pre-Baking Golden Images
*   **Faster Cloud Bursting**: Dynamic worker instances boot and join the LSF cluster in seconds.
*   **Air-Gapped & Deterministic**: Guarantees fixed tool versions (`iverilog`, `yosys`, `openroad`, `verilator`, `magic`, `netgen`) without relying on external repositories during worker startup.

### 1. Build the Golden Image
Run the automated image builder pipeline from the repository root:
```bash
./lsf_config/build_golden_image.sh
```
*This launches a temporary build VM, installs all OS dependencies, Miniconda, and the open-source EDA suite, creates the custom image `lsf-submit-and-worker-rocky-8-image` (Family: `lsf-rocky-8`), and cleans up the temporary builder VM.*
*(For detailed manual steps, see the [Golden Image Guide](GOLDEN_IMAGE.md).)*

### 2. Redeploy Terraform with Golden Images
Once your Golden Images exist in your GCP project, specify them as variables during the Terraform apply stage to boot both the Master/Submit VMs and dynamic cloud workers directly from your pre-baked images:
```bash
cd terraform
terraform apply \
  -var="master_image=lsf-submit-and-worker-rocky-8-image" \
  -var="submit_image=lsf-submit-and-worker-rocky-8-image" \
  -var="worker_image=lsf-submit-and-worker-rocky-8-image"
```

---

## 7. Teardown & Clean-Up Guide

Once your testing is complete, follow these steps to destroy all provisioned GCP resources and avoid ongoing cloud infrastructure charges.

### Step 7.1: Terminate Active Jobs & Dynamic Cloud Workers
Before destroying the core infrastructure, ensure any active workloads are stopped so LSF Resource Connector can release dynamic worker VMs:

1. SSH into the Submit VM (or Master VM) as `lsfadmin` and cancel any running or queued jobs:
   ```bash
   bkill 0
   ```
2. Wait a couple of minutes for LSF to automatically terminate idle cloud worker VMs (`compute-*`), or list active instances from your local terminal to verify:
   ```bash
   gcloud compute instances list
   ```
   *(If dynamic worker instances remain active, you can force-delete them via `gcloud compute instances delete <instance-name> --zone=<zone>`)*

### Step 7.2: Destroy Infrastructure via Terraform
1. Navigate to the `terraform` directory in your local workspace:
   ```bash
   cd terraform
   ```
2. Run `terraform destroy` to tear down all provisioned resources (VPCs, Subnets, Routers, Cloud NAT, Firewall Rules, Service Accounts, Master/Submit VMs, and GCS Bucket):
   ```bash
   terraform destroy
   ```
   *(When prompted, type `yes` to confirm resource deletion.)*

> [!NOTE]
> The GCS installation bucket (`google_storage_bucket.lsf_install_bucket`) has `force_destroy = true` enabled in Terraform. Running `terraform destroy` automatically removes the bucket along with all uploaded LSF software archives and configuration files.

### Step 7.3: (Optional) Delete Custom Golden Images
If you created pre-baked GCE Golden Images using `build_golden_image.sh`, delete them if they are no longer required to prevent storage costs:
```bash
gcloud compute images delete lsf-submit-and-worker-rocky-8-image
```
