variable "project_id" {
  description = "The GCP Project ID where resources will be deployed."
  type        = string
}

variable "region" {
  description = "The default GCP region to deploy resources."
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "The default GCP zone to deploy the LSF master and submit VMs. Defaults to <region>-a if not specified."
  type        = string
  default     = null
}

variable "onprem_cidr" {
  description = "The CIDR range for the simulated on-premise VPC network."
  type        = string
  default     = "10.10.0.0/16"
}

variable "cloud_cidr" {
  description = "The CIDR range for the GCP cloud bursting VPC network."
  type        = string
  default     = "10.20.0.0/16"
}

variable "master_machine_type" {
  description = "Machine type for the LSF Master/Management VM."
  type        = string
  default     = "n2-standard-4"
}

variable "submit_machine_type" {
  description = "Machine type for the LSF Submit/Login VM."
  type        = string
  default     = "n2-standard-2"
}

variable "master_image" {
  description = "The boot disk image name or family for the LSF Master VM."
  type        = string
  default     = "rocky-linux-cloud/rocky-linux-8-optimized-gcp"
}

variable "submit_image" {
  description = "The boot disk image name or family for the LSF Submit/Login VM."
  type        = string
  default     = "rocky-linux-cloud/rocky-linux-8-optimized-gcp"
}

variable "worker_image" {
  description = "The GCE custom image name used by dynamic cloud workers."
  type        = string
  default     = "lsf-submit-and-worker-rocky-8-image"
}

variable "bucket_name" {
  description = "Optional custom name for the GCS installation bucket. Defaults to lsf-install-bucket-<random_id> if not specified."
  type        = string
  default     = null
}

variable "bucket_location" {
  description = "The GCS location (region or multi-region) for the installation bucket."
  type        = string
  default     = "US"
}

