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

output "lsf_rc_sa_email" {
  description = "The email of the Service Account created for LSF Resource Connector."
  value       = google_service_account.lsf_rc_sa.email
}
