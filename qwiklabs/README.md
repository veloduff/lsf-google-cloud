# Google Cloud Skills Boost (Qwiklabs) Workshop Bundle: LSF on Google Cloud

This directory (`qwiklabs/`) contains the complete **Google Cloud Skills Boost (Qwiklabs)** self-paced workshop bundle for **Bursting Semiconductor EDA Workloads to Google Cloud with IBM Spectrum LSF**.

---

## Directory Structure

```text
qwiklabs/
├── QL_OWNER                            # Qwiklabs GitWhisperer staging lab owner (mduffield@google.com)
├── qwiklabs.yaml                       # Qwiklabs v2 lab manifest (metadata, resources, outputs, assessments)
├── instructions/
│   ├── en.md                           # Step-by-step student lab manual (5 hands-on tasks + checkpoints)
│   └── img/                            # Embedded console screenshots for the instruction manual
│       ├── gcp_console_idle.png
│       └── gcp_console_scaled.png
├── tf/                                 # Qwiklabs environment startup Terraform (runs before lab starts)
│   ├── main.tf                         # Pre-enables GCP APIs and sets project metadata (lsf_source_bucket)
│   ├── variables.tf                    # Qwiklabs platform input variables (gcp_project_id, gcp_region, gcp_zone)
│   ├── outputs.tf                      # Student-visible outputs in the Qwiklabs lab panel
│   ├── versions.tf                     # Terraform & Google provider version constraints
│   └── runtime.yaml                    # Qwiklabs Terraform runtime version specification
└── assessments/                        # Automated "Check my progress" activity tracking scripts
    ├── check_task1_infra.rb            # Qwiklabs Ruby Activity Tracking: Task 1 (20 pts)
    ├── check_task1_infra.sh            # CLI / Cloud Shell Self-Check: Task 1 (20 pts)
    ├── check_task2_golden_image.rb     # Qwiklabs Ruby Activity Tracking: Task 2 (20 pts)
    ├── check_task2_golden_image.sh     # CLI / Cloud Shell Self-Check: Task 2 (20 pts)
    ├── check_task3_lsf_master.rb       # Qwiklabs Ruby Activity Tracking: Task 3 (20 pts)
    ├── check_task3_lsf_master.sh       # CLI / Cloud Shell Self-Check: Task 3 (20 pts)
    ├── check_task4_autoscaling.rb      # Qwiklabs Ruby Activity Tracking: Task 4 (20 pts)
    ├── check_task4_autoscaling.sh      # CLI / Cloud Shell Self-Check: Task 4 (20 pts)
    ├── check_task5_eda_regression.rb   # Qwiklabs Ruby Activity Tracking: Task 5 (20 pts)
    └── check_task5_eda_regression.sh   # CLI / Cloud Shell Self-Check: Task 5 (20 pts)
```

---

## Prerequisites for Lab Hosting (Staging the Shared LSF Installer Bucket)

Because **IBM Spectrum LSF 10.1** is licensed software and Qwiklabs learners do not have local `Install_Files/` archives on their laptops, the lab performs a fresh LSF installation by copying the 4 LSF installer archives from a shared Google Cloud Storage bucket (`lsf_source_bucket`, defaulting to `gs://qwiklabs-lsf-installers`).

### 1. Stage the 4 IBM Spectrum LSF 10.1 Archives in Your Shared GCS Bucket

Upload the following 4 archives into your shared lab hosting GCS bucket (e.g., `gs://qwiklabs-lsf-installers/`):

1. `lsf_std_entitlement.dat`
2. `lsf10.1_lsfinstall_linux_x86_64.tar.Z`
3. `lsf10.1_linux2.6-glibc2.3-x86_64.tar.Z`
4. `lsf10.1_linux2.6-glibc2.3-x86_64-601088.tar.Z`

```bash
SHARED_BUCKET="gs://qwiklabs-lsf-installers"
gcloud storage cp Install_Files/lsf_std_entitlement.dat "${SHARED_BUCKET}/"
gcloud storage cp Install_Files/lsf10.1_lsfinstall_linux_x86_64.tar.Z "${SHARED_BUCKET}/"
gcloud storage cp Install_Files/lsf10.1_linux2.6-glibc2.3-x86_64.tar.Z "${SHARED_BUCKET}/"
gcloud storage cp Install_Files/lsf10.1_linux2.6-glibc2.3-x86_64-601088.tar.Z "${SHARED_BUCKET}/"
```

### 2. Configure Bucket Name (If Different from `qwiklabs-lsf-installers`)

If your shared GCS bucket uses a different name, update the default value of `lsf_source_bucket` in [`qwiklabs/tf/variables.tf`](tf/variables.tf):

```hcl
variable "lsf_source_bucket" {
  description = "Shared GCS bucket hosting the 4 IBM Spectrum LSF 10.1 installer archives for the lab."
  type        = string
  default     = "your-custom-shared-lsf-bucket"
}
```

### 3. Grant Read Access to Qwiklabs Student Accounts

Ensure the shared bucket grants `roles/storage.objectViewer` to your Qwiklabs student group or organization domain so `upload_assets.sh` can copy the 4 archives into each ephemeral `qwiklabs-gcp-*` student project bucket during Task 3.

---

## Testing the Assessment Scripts Locally

You can run any of the 5 CLI assessment scripts directly from Cloud Shell or your workstation against an active lab project by passing the GCP Project ID as the first argument:

```bash
./qwiklabs/assessments/check_task1_infra.sh <YOUR_GCP_PROJECT_ID>
./qwiklabs/assessments/check_task2_golden_image.sh <YOUR_GCP_PROJECT_ID>
./qwiklabs/assessments/check_task3_lsf_master.sh <YOUR_GCP_PROJECT_ID>
./qwiklabs/assessments/check_task4_autoscaling.sh <YOUR_GCP_PROJECT_ID>
./qwiklabs/assessments/check_task5_eda_regression.sh <YOUR_GCP_PROJECT_ID>
```
