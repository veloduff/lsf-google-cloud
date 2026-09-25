# Building the LSF Cloud Worker Golden Image

To optimize VM boot latency and minimize job scheduling delays, the GCE dynamic worker instances use a pre-configured **Golden Image** (`lsf-submit-and-worker-rocky-8-image`). This image has all prerequisites, Miniconda, and the open-source EDA tools stack pre-installed.

Sharing the LSF core configuration and binaries via NFS `/opt/lsf` keeps the image lightweight and ensures that any patches or configuration updates made to the LSF Master are automatically applied to the workers on boot without rebuilding the image.

---

## What is Baked into the Golden Image?
1. **OS Packages**: `nfs-utils`, `ed`, `epel-release`, `libnsl`, `java-1.8.0-openjdk-headless`, `wget`.
2. **Package Manager**: Miniconda3 (installed at `/opt/conda`).
3. **EDA Tools Stack**:
   * **Simulation**: `verilator`, `icarus-verilog`
   * **Synthesis**: `yosys`
   * **Place & Route**: `openroad`
   * **Layout & LVS**: `magic`, `netgen`
   * **Waveform Viewer**: `gtkwave`

---

## Automated Golden Image Creation Process

An automated script `lsf_config/build_golden_image.sh` is provided in the repository to spin up a temporary VM, execute the installations, capture the disk image, and clean up GCE resources.

### Running the Build Script
From your local workspace, run the script. It automatically auto-detects your Project ID, Region, Zone, and Subnet from `terraform/terraform.tfvars` or `gcloud config`:
```bash
./lsf_config/build_golden_image.sh
```
*(You can also override parameters explicitly via CLI flags: `./lsf_config/build_golden_image.sh --project=YOUR_PROJECT --region=YOUR_REGION --zone=YOUR_ZONE`)*

### Script Workflow
1. **Launches Temporary VM**: Creates a temporary instance `lsf-golden-build` in GCE.
2. **Executes Provisioning Tasks**: Runs remote commands via SSH to install the dependencies and EDA packages.
3. **Stops VM & Deletes Old Image**: Stops the VM and removes the previous `lsf-submit-and-worker-rocky-8-image` registration.
4. **Captures Disk Image**: Creates a fresh `lsf-submit-and-worker-rocky-8-image` custom image from the stopped VM's boot disk.
5. **Resource Cleanup**: Deletes the temporary GCE VM and boot disk.

---

## Persisting and Sharing Images Across Projects

If the current GCP project is temporary and will be deleted, you must copy the custom images to a persistent project (e.g., `your-shared-image-project-id`) to prevent them from being lost.

Because corporate GCP environments often enable organization policies restricting direct image copies (`constraints/compute.trustedImageProjects`), you can use GCE snapshots to easily migrate images without violating constraints.

### 1. Migrating Image to a Persistent Project (Workaround for Policy Constraints)
First, source your environment variables from `terraform/terraform.tfvars`:
```bash
source ./set_env.sh
```

Run these commands in your terminal to safely replicate the image:

```bash
# A. Create a temporary disk in the source project from the image
gcloud compute disks create temp-worker-disk \
    --image="lsf-submit-and-worker-rocky-8-image" \
    --project="your-source-project-id" \
    --zone="${TF_VAR_zone:-us-central1-a}"

# B. Create a snapshot from that disk
gcloud compute snapshots create worker-snapshot \
    --source-disk="temp-worker-disk" \
    --source-disk-zone="${TF_VAR_zone:-us-central1-a}" \
    --project="your-source-project-id"

# C. Create a disk in your persistent target project from the snapshot
gcloud compute disks create temp-worker-disk-dest \
    --source-snapshot="projects/your-source-project-id/global/snapshots/worker-snapshot" \
    --project="your-shared-image-project-id" \
    --zone="${TF_VAR_zone:-us-central1-a}"

# D. Register the final Golden Image in your persistent project
gcloud compute images create lsf-submit-and-worker-rocky-8-image \
    --source-disk="temp-worker-disk-dest" \
    --source-disk-zone="${TF_VAR_zone:-us-central1-a}" \
    --project="your-shared-image-project-id" \
    --family="lsf-rocky-8"
```

### 2. Migrating the Master Image to a Persistent Project (Optional)
> [!NOTE]
> `build_golden_image.sh` builds a single consolidated worker/submit image named `lsf-submit-and-worker-rocky-8-image`. If an administrator chooses to manually capture the Master VM disk *after* running `setup_master.sh` into a custom image named `lsf-master-rocky-8-image`, run these commands to replicate it:

```bash
# A. Create a temporary disk in the source project from the master image
gcloud compute disks create temp-master-disk \
    --image="lsf-master-rocky-8-image" \
    --project="your-source-project-id" \
    --zone="${TF_VAR_zone:-us-central1-a}"

# B. Create a snapshot from that disk
gcloud compute snapshots create master-snapshot \
    --source-disk="temp-master-disk" \
    --source-disk-zone="${TF_VAR_zone:-us-central1-a}" \
    --project="your-source-project-id"

# C. Create a disk in your persistent target project from the snapshot
gcloud compute disks create temp-master-disk-dest \
    --source-snapshot="projects/your-source-project-id/global/snapshots/master-snapshot" \
    --project="your-shared-image-project-id" \
    --zone="${TF_VAR_zone:-us-central1-a}"

# D. Register the final Master Image in your persistent project
gcloud compute images create lsf-master-rocky-8-image \
    --source-disk="temp-master-disk-dest" \
    --source-disk-zone="${TF_VAR_zone:-us-central1-a}" \
    --project="your-shared-image-project-id" \
    --family="lsf-rocky-8"
```

### 3. Cleaning Up Temporary Migration Resources
After both worker/submit and master images have been successfully registered in the persistent project, clean up the temporary disks and snapshots from both projects to avoid extra storage charges:

```bash
# --- Clean Up Source Project (your-source-project-id) ---
gcloud compute disks delete temp-worker-disk temp-master-disk \
    --project="your-source-project-id" \
    --zone="${TF_VAR_zone:-us-central1-a}" \
    --quiet

gcloud compute snapshots delete worker-snapshot master-snapshot \
    --project="your-source-project-id" \
    --quiet

# --- Clean Up Destination Project (your-shared-image-project-id) ---
gcloud compute disks delete temp-worker-disk-dest temp-master-disk-dest \
    --project="your-shared-image-project-id" \
    --zone="${TF_VAR_zone:-us-central1-a}" \
    --quiet
```

---

## Using the Shared Images in Other Projects

Once the images are hosted in your persistent project (`your-shared-image-project-id`), you can reference them directly from other projects:

### 1. Grant IAM Permissions (One-Time Setup)
Grant the target project's Compute Engine service account read permissions on the persistent image project:
```bash
gcloud projects add-iam-policy-binding your-shared-image-project-id \
    --member="serviceAccount:TARGET_PROJECT_NUMBER-compute@developer.gserviceaccount.com" \
    --role="roles/compute.imageUser"
```
*(Replace `TARGET_PROJECT_NUMBER` with the numeric project ID of the new project)*

### 2. Reference the Shared Image Paths
Use the full resource URLs to instantiate VMs in your new projects:

* **LSF Dynamic Workers & Submit VM**:
  * **In Terraform**:
    `image = "projects/your-shared-image-project-id/global/images/lsf-submit-and-worker-rocky-8-image"`
  * **In `googleprov_templates.json`**:
    `"imageId": "projects/your-shared-image-project-id/global/images/lsf-submit-and-worker-rocky-8-image"`
  * **In `gcloud` VM Creation**:
    `--image="projects/your-shared-image-project-id/global/images/lsf-submit-and-worker-rocky-8-image"`

* **LSF Master VM**:
  * **In Terraform**:
    `image = "projects/your-shared-image-project-id/global/images/lsf-master-rocky-8-image"`
  * **In `gcloud` VM Creation**:
    `--image="projects/your-shared-image-project-id/global/images/lsf-master-rocky-8-image"`
