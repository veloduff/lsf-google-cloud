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

output "project_id" {
  description = "The GCP Project ID where the LSF hybrid environment is deployed."
  value       = var.project_id
}

output "region" {
  description = "The GCP region where the LSF hybrid environment is deployed."
  value       = var.region
}

output "zone" {
  description = "The GCP zone where the LSF Master and Submit VMs are deployed."
  value       = local.zone
}

output "lsf_master_private_ip" {
  description = "The private IP of the LSF Master VM."
  value       = google_compute_instance.lsf_master.network_interface[0].network_ip
}

output "lsf_submit_private_ip" {
  description = "The private IP of the LSF Submit VM."
  value       = google_compute_instance.lsf_submit.network_interface[0].network_ip
}

output "lsf_install_bucket_name" {
  description = "The name of the GCS bucket created for LSF installers."
  value       = google_storage_bucket.lsf_install_bucket.name
}

output "lsf_source_bucket" {
  description = "Optional shared source GCS bucket containing LSF installer archives."
  value       = var.lsf_source_bucket
}

output "lsf_rc_sa_email" {
  description = "The email of the Service Account created for LSF Resource Connector."
  value       = google_service_account.lsf_rc_sa.email
}
