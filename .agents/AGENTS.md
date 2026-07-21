# Grokking LSF Project Customizations & Lessons Learned

This file defines behavioral rules and critical technical gotchas discovered during the development and scaling of the LSF Hybrid Cloud cluster in this workspace.

---

## 1. LSF Master Configuration & Setup Gotcha
* **Problem**: Running `setup_master.sh` alone in isolation (e.g. by only copying that single file from GCS) causes Step 6 (Applying Hybrid Cloud & Resource Connector Configs) to be silently skipped. This breaks name resolution, domain stripping (`LSF_STRIP_DOMAIN`), and prevents the Submit VM from joining the cluster.
* **Rule**: When executing LSF Master configuration setups or updates, **always** copy the entire `lsf_config/` directory from GCS to a local directory on the Master VM (e.g., `/tmp/lsf_config/`), and execute `/tmp/lsf_config/setup_master.sh` from there.

---

## 2. GCP Image Naming Conventions
* **LSF Dynamic Workers & Submit VM**: `lsf-submit-and-worker-rocky-8-image` (Family: `lsf-rocky-8`)
* **LSF Master VM**: `lsf-master-rocky-8-image` (Family: `lsf-rocky-8`)

---

## 3. Cross-Project Image Migration (Trusted Image Constraint)
* **Problem**: Direct cross-project image copies (`gcloud compute images create ... --source-image`) fail with a policy violation error because the organization policy `constraints/compute.trustedImageProjects` blocks untrusted source projects.
* **Rule**: To migrate images from a sandbox/temporary project to a persistent registry project (e.g., `persistent-project-shared-data`), you must use the **GCE Snapshot Workaround**:
  1. Create a disk from the image in the source project.
  2. Create a snapshot of the disk.
  3. Create a disk in the target project from the shared snapshot.
  4. Create the final image in the target project from the disk.

---

## 4. GCS Image Export Name Collisions (Daisy Scratch Bucket)
* **Problem**: `gcloud compute images export` fails on generic project IDs (like `lsf-testing-001`) because Google's Daisy engine tries to create a scratch bucket named `{project-id}-daisy-bkt-us`, which has a global name collision.
* **Workarounds**:
  * Pass the `--zone="europe-west1-b"` flag to force a non-conflicting regional name (e.g. `daisy-bkt-eu`).
  * Or configure the CLI to use a custom scratch bucket globally before exporting:
    `gcloud config set compute/image_import_scratch_bucket gs://lsf-install-bucket-xxxxxx`
