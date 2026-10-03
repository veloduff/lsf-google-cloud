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

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
  zone    = var.gcp_zone
}

locals {
  required_apis = [
    "compute.googleapis.com",
    "dns.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "iap.googleapis.com",
    "storage.googleapis.com",
  ]
}

# Pre-enable required Google Cloud APIs so student Terraform runs without propagation delays
resource "google_project_service" "lab_apis" {
  for_each           = toset(local.required_apis)
  project            = var.gcp_project_id
  service            = each.value
  disable_on_destroy = false
}

# Store lab defaults in Compute Engine project metadata so Cloud Shell scripts can auto-discover them
resource "google_compute_project_metadata_item" "lsf_source_bucket" {
  project    = var.gcp_project_id
  key        = "lsf_source_bucket"
  value      = var.lsf_source_bucket
  depends_on = [google_project_service.lab_apis]
}

resource "google_compute_project_metadata_item" "google_compute_default_region" {
  project    = var.gcp_project_id
  key        = "google-compute-default-region"
  value      = var.gcp_region
  depends_on = [google_project_service.lab_apis]
}

resource "google_compute_project_metadata_item" "google_compute_default_zone" {
  project    = var.gcp_project_id
  key        = "google-compute-default-zone"
  value      = var.gcp_zone
  depends_on = [google_project_service.lab_apis]
}
