terraform {
  required_version = ">= 1.0.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

locals {
  zone = coalesce(var.zone, "${var.region}-a")
}

# Resource for generating unique names
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# ==========================================
# NETWORKING: VPCs, SUBNETS, & PEERING
# ==========================================

# Simulated On-Premises VPC
resource "google_compute_network" "onprem_vpc" {
  name                    = "lsf-onprem-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "onprem_subnet" {
  name                     = "lsf-onprem-subnet"
  ip_cidr_range            = var.onprem_cidr
  region                   = var.region
  network                  = google_compute_network.onprem_vpc.id
  private_ip_google_access = true
}

# GCP Cloud Bursting VPC
resource "google_compute_network" "cloud_vpc" {
  name                    = "lsf-cloud-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "cloud_subnet" {
  name                     = "lsf-cloud-subnet"
  ip_cidr_range            = var.cloud_cidr
  region                   = var.region
  network                  = google_compute_network.cloud_vpc.id
  private_ip_google_access = true
}

# VPC Network Peering: On-Prem to Cloud
resource "google_compute_network_peering" "onprem_to_cloud" {
  name         = "onprem-to-cloud-peering"
  network      = google_compute_network.onprem_vpc.id
  peer_network = google_compute_network.cloud_vpc.id
}

# VPC Network Peering: Cloud to On-Prem
resource "google_compute_network_peering" "cloud_to_onprem" {
  name         = "cloud-to-onprem-peering"
  network      = google_compute_network.cloud_vpc.id
  peer_network = google_compute_network.onprem_vpc.id
}

# ==========================================
# OUTBOUND INTERNET ACCESS: ROUTERS & NATs
# ==========================================

# Cloud Router for On-Prem VPC
resource "google_compute_router" "onprem_router" {
  name    = "lsf-onprem-router"
  region  = var.region
  network = google_compute_network.onprem_vpc.id
}

# Cloud NAT for On-Prem VPC (Allows private Master VM to update packages)
resource "google_compute_router_nat" "onprem_nat" {
  name                               = "lsf-onprem-nat"
  router                             = google_compute_router.onprem_router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

# Cloud Router for Cloud VPC
resource "google_compute_router" "cloud_router" {
  name    = "lsf-cloud-router"
  region  = var.region
  network = google_compute_network.cloud_vpc.id
}

# Cloud NAT for Cloud VPC (Allows private Worker VMs to download EDA tools)
resource "google_compute_router_nat" "cloud_nat" {
  name                               = "lsf-cloud-nat"
  router                             = google_compute_router.cloud_router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

# ==========================================
# FIREWALL RULES
# ==========================================

# On-Prem Firewall Rules
resource "google_compute_firewall" "onprem_allow_internal" {
  name    = "onprem-allow-internal"
  network = google_compute_network.onprem_vpc.name

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  source_ranges = [var.onprem_cidr]
}

resource "google_compute_firewall" "onprem_allow_ssh" {
  name    = "onprem-allow-ssh"
  network = google_compute_network.onprem_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
}

resource "google_compute_firewall" "onprem_allow_cloud" {
  name    = "onprem-allow-cloud"
  network = google_compute_network.onprem_vpc.name

  # Allow LSF ports and NFS from cloud workers
  allow {
    protocol = "tcp"
    ports    = ["7869", "6878", "6881", "6882", "2049"]
  }

  allow {
    protocol = "udp"
    ports    = ["7869"]
  }

  source_ranges = [var.cloud_cidr]
}

# Cloud VPC Firewall Rules
resource "google_compute_firewall" "cloud_allow_internal" {
  name    = "cloud-allow-internal"
  network = google_compute_network.cloud_vpc.name

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  source_ranges = [var.cloud_cidr]
}

resource "google_compute_firewall" "cloud_allow_ssh" {
  name    = "cloud-allow-ssh"
  network = google_compute_network.cloud_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
}

resource "google_compute_firewall" "cloud_allow_onprem" {
  name    = "cloud-allow-onprem"
  network = google_compute_network.cloud_vpc.name

  # Allow LSF ports and NFS from on-prem master/submit
  allow {
    protocol = "tcp"
    ports    = ["7869", "6878", "6881", "6882", "2049"]
  }

  allow {
    protocol = "udp"
    ports    = ["7869"]
  }

  source_ranges = [var.onprem_cidr]
}

# ==========================================
# IAM & SERVICE ACCOUNTS
# ==========================================

# Service Account for LSF Resource Connector
resource "google_service_account" "lsf_rc_sa" {
  account_id   = "lsf-resource-connector-sa"
  display_name = "LSF Resource Connector Service Account"
}

# Wait 30 seconds for IAM eventual consistency across Google's global systems
resource "time_sleep" "wait_for_sa" {
  depends_on      = [google_service_account.lsf_rc_sa]
  create_duration = "30s"
}

# Assign roles to the service account
resource "google_project_iam_member" "compute_admin" {
  project    = var.project_id
  role       = "roles/compute.admin"
  member     = "serviceAccount:${google_service_account.lsf_rc_sa.email}"
  depends_on = [time_sleep.wait_for_sa]
}

resource "google_project_iam_member" "sa_user" {
  project    = var.project_id
  role       = "roles/iam.serviceAccountUser"
  member     = "serviceAccount:${google_service_account.lsf_rc_sa.email}"
  depends_on = [time_sleep.wait_for_sa]
}

# ==========================================
# CLOUD STORAGE (GCS) BUCKET
# ==========================================

resource "google_storage_bucket" "lsf_install_bucket" {
  name                        = var.bucket_name != null && var.bucket_name != "" ? var.bucket_name : "lsf-install-bucket-${random_id.bucket_suffix.hex}"
  location                    = var.bucket_location
  force_destroy               = true
  uniform_bucket_level_access = true
}

# Grant the SA access to read the bucket
resource "google_storage_bucket_iam_member" "bucket_viewer" {
  bucket     = google_storage_bucket.lsf_install_bucket.name
  role       = "roles/storage.objectViewer"
  member     = "serviceAccount:${google_service_account.lsf_rc_sa.email}"
  depends_on = [time_sleep.wait_for_sa]
}

# ==========================================
# VIRTUAL MACHINES (ON-PREM SIMULATION)
# ==========================================

# LSF Master (Management Host)
resource "google_compute_instance" "lsf_master" {
  name         = "lsf-master"
  machine_type = var.master_machine_type
  zone         = local.zone
  depends_on   = [time_sleep.wait_for_sa]

  boot_disk {
    initialize_params {
      image = var.master_image
      size  = 50
    }
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  network_interface {
    subnetwork = google_compute_subnetwork.onprem_subnet.id
    network_ip = "10.10.0.10"
    # access_config removed to comply with compute.vmExternalIpAccess org policy
  }

  service_account {
    email  = google_service_account.lsf_rc_sa.email
    scopes = ["cloud-platform"]
  }

  metadata = {
    lsf_bucket   = google_storage_bucket.lsf_install_bucket.name
    worker_image = var.worker_image
  }

  metadata_startup_script = <<-EOT
    #!/bin/bash
    # Set system hostname
    hostnamectl set-hostname master.onprem.local || true

    # Stop and disable OS firewall
    systemctl stop firewalld || true
    systemctl disable firewalld || true

    # Update system and install NFS server, ed (required by LSF), and utilities
    yum update -y
    yum install -y nfs-utils ed wget git gcc make libnsl java-1.8.0-openjdk-headless

    # Set up NFS exports for shared /opt/lsf and /home
    mkdir -p /opt/lsf
    echo "/opt/lsf *(rw,sync,no_root_squash,no_all_squash)" >> /etc/exports
    echo "/home *(rw,sync,no_root_squash,no_all_squash)" >> /etc/exports

    systemctl enable rpcbind nfs-server
    systemctl start rpcbind nfs-server

    # Set up a local DNS/Hosts mapping
    echo "10.10.0.10 master.onprem.local master" >> /etc/hosts
    echo "10.10.0.2 submit.onprem.local submit" >> /etc/hosts
    echo "127.0.0.1 localhost" >> /etc/hosts
  EOT

  tags = ["lsf-master"]
}

# LSF Submit Host
resource "google_compute_instance" "lsf_submit" {
  name         = "lsf-submit"
  machine_type = var.submit_machine_type
  zone         = local.zone

  boot_disk {
    initialize_params {
      image = var.submit_image
      size  = 30
    }
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  network_interface {
    subnetwork = google_compute_subnetwork.onprem_subnet.id
    network_ip = "10.10.0.2"
    # access_config removed to comply with compute.vmExternalIpAccess org policy
  }

  metadata_startup_script = <<-EOT
    #!/bin/bash
    # Set system hostname
    hostnamectl set-hostname submit.onprem.local || true

    # Stop and disable OS firewall
    systemctl stop firewalld || true
    systemctl disable firewalld || true

    yum update -y
    yum install -y nfs-utils ed wget git libnsl java-1.8.0-openjdk-headless

    # Install Miniconda & EDA Tools locally on the Submit Host if not already pre-baked in the image
    if [ ! -d "/opt/conda" ]; then
      echo "Installing Miniconda and EDA tools..."
      wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O /tmp/miniconda.sh
      bash /tmp/miniconda.sh -b -p /opt/conda
      rm -f /tmp/miniconda.sh

      echo "export PATH=\"/opt/conda/envs/eda/bin:/opt/conda/bin:\$PATH\"" > /etc/profile.d/conda.sh
      /opt/conda/bin/conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main || true
      /opt/conda/bin/conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r || true
      /opt/conda/bin/conda config --add channels litex-hub || true
      /opt/conda/bin/conda config --add channels conda-forge || true
      /opt/conda/bin/conda create -y -n eda -c litex-hub -c conda-forge python=3.10 yosys openroad magic netgen verilator iverilog gtkwave || true
    fi

    # Wait for master NFS to be available, then mount
    mkdir -p /opt/lsf
    echo "master.onprem.local:/opt/lsf /opt/lsf nfs defaults 0 0" >> /etc/fstab
    echo "master.onprem.local:/home /home nfs defaults 0 0" >> /etc/fstab
    
    # Configure local hosts
    echo "10.10.0.10 master.onprem.local master" >> /etc/hosts
    echo "10.10.0.2 submit.onprem.local submit" >> /etc/hosts
    
    # Mount loop
    until mount -a; do
      echo "Waiting for NFS mount..."
      sleep 5
    done

    # Create the lsfadmin user locally with explicit UID/GID mapping if not already present
    id -u lsfadmin &>/dev/null || {
      groupadd -g 1000 lsf || true
      useradd -u 1000 -g lsf -d /home/lsfadmin -s /bin/bash lsfadmin || true
    }
  EOT

  depends_on = [google_compute_instance.lsf_master]
}

# ==========================================
# CLOUD DNS PEERING (Forward and Reverse)
# ==========================================

resource "google_dns_managed_zone" "cloud_dns_peering" {
  name        = "cloud-dns-peering"
  dns_name    = "c.${var.project_id}.internal."
  description = "Peer forward DNS from onprem VPC to cloud VPC"
  visibility  = "private"

  private_visibility_config {
    networks {
      network_url = google_compute_network.onprem_vpc.id
    }
  }

  peering_config {
    target_network {
      network_url = google_compute_network.cloud_vpc.id
    }
  }
}

resource "google_dns_managed_zone" "cloud_reverse_dns_peering" {
  name        = "cloud-reverse-dns-peering"
  dns_name    = "20.10.in-addr.arpa."
  description = "Peer reverse DNS from onprem VPC to cloud VPC"
  visibility  = "private"

  private_visibility_config {
    networks {
      network_url = google_compute_network.onprem_vpc.id
    }
  }

  peering_config {
    target_network {
      network_url = google_compute_network.cloud_vpc.id
    }
  }
}



