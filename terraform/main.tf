terraform {
  required_version = ">= 1.0"
  backend "local" {}  # Can change from "local" to "gcs" (for google) or "s3" (for aws), if you would like to preserve your tf-state online
  required_providers {
    google = {
      source  = "hashicorp/google"
    }
  }
}

provider "google" {
  project = var.project
  region = var.region
  zone = var.zone
  // credentials = file(var.credentials)  # Use this if you do not want to set env-var GOOGLE_APPLICATION_CREDENTIALS
}


resource "google_compute_instance" "airflow_vm_instance" {
  name = "streamify-airflow-instance"
  machine_type = "e2-standard-4"
  zone = var.zone
  boot_disk {
    initialize_params {
      image = var.vm_image
    }
  }

  network_interface {
    network = var.network
    access_config {
    }
  }
}

resource "google_compute_instance" "kafka_vm_instance" {
  name = "streamify-kafka-instance"
  machine_type = "e2-standard-4"
  tags = ["kafka"]
  zone = var.zone
  boot_disk {
    initialize_params {
      image = var.vm_image
    }
  }

  network_interface {
    network = var.network
    access_config {
    }
  }
}

resource "google_compute_firewall" "port_rules" {
  project     = var.project
  name        = "kafka-broker-port"
  network     = var.network
  description = "Opens port 9092 in the Kafka VM for Spark cluster to connect"

  allow {
    protocol = "tcp"
    ports    = ["9092"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["kafka"]

}

resource "google_storage_bucket" "bucket" {
  name          = var.bucket
  location      = var.region
  force_destroy = true

  lifecycle_rule {
    condition {
      age = 50
    }
    action {
      type = "Delete"
    }
  }
}


resource "google_dataproc_cluster" "mulitnode_spark_cluster" {
  name   = "streamify-multinode-spark-cluster"
  region = var.region

  cluster_config {

    staging_bucket = var.bucket

    gce_cluster_config {
      network = var.network
      zone    = var.zone

      shielded_instance_config {
        enable_secure_boot = true
      }
    }

    master_config {
      num_instances = 1
      machine_type  = "e2-standard-2"
      disk_config {
        boot_disk_type    = "pd-ssd"
        boot_disk_size_gb = 30
      }
    }

    worker_config {
      num_instances = 2
      machine_type  = "e2-medium"
      disk_config {
        boot_disk_size_gb = 30
      }
    }

    software_config {
      image_version = "2.0-debian10"
      override_properties = {
        "dataproc:dataproc.allow.zero.workers" = "true"
      }
      optional_components = ["JUPYTER"]
    }

  }

}

resource "google_bigquery_dataset" "stg_dataset" {
  dataset_id                 = var.stg_bq_dataset
  project                    = var.project
  location                   = var.region
  delete_contents_on_destroy = true
}

resource "google_bigquery_dataset" "prod_dataset" {
  dataset_id                 = var.prod_bq_dataset
  project                    = var.project
  location                   = var.region
  delete_contents_on_destroy = true
}