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

variable "gcp_project_id" {
  description = "The Qwiklabs student GCP Project ID."
  type        = string
}

variable "gcp_region" {
  description = "Default GCP region allocated to the Qwiklabs student project."
  type        = string
  default     = "us-central1"
}

variable "gcp_zone" {
  description = "Default GCP zone allocated to the Qwiklabs student project."
  type        = string
  default     = "us-central1-a"
}

variable "lsf_source_bucket" {
  description = "Shared GCS bucket hosting the 4 IBM Spectrum LSF 10.1 installer archives for the lab."
  type        = string
  default     = "qwiklabs-lsf-installers"
}
