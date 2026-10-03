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

output "gcp_project_id" {
  description = "The Qwiklabs student GCP Project ID."
  value       = var.gcp_project_id
}

output "gcp_region" {
  description = "The default GCP region for the lab."
  value       = var.gcp_region
}

output "gcp_zone" {
  description = "The default GCP zone for the lab."
  value       = var.gcp_zone
}

output "lsf_source_bucket" {
  description = "The shared GCS bucket hosting the IBM Spectrum LSF 10.1 installer archives."
  value       = var.lsf_source_bucket
}
