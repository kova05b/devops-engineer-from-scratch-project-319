resource "yandex_kubernetes_cluster" "main" {
  name        = "${local.name_prefix}-k8s"
  description = "Managed Kubernetes cluster for ${var.project_name}"
  labels      = local.labels

  network_id = yandex_vpc_network.main.id

  service_account_id      = yandex_iam_service_account.k8s_cluster.id
  node_service_account_id = yandex_iam_service_account.k8s_node.id

  master {
    version = var.k8s_version

    zonal {
      zone      = var.yc_zone
      subnet_id = yandex_vpc_subnet.main.id
    }

    public_ip = true

    security_group_ids = [
      yandex_vpc_security_group.k8s.id
    ]
  }

  depends_on = [
    yandex_resourcemanager_folder_iam_member.k8s_cluster_editor,
    yandex_resourcemanager_folder_iam_member.k8s_node_editor
  ]
}

resource "yandex_kubernetes_node_group" "main" {
  name        = "${local.name_prefix}-nodes"
  description = "Default node group"
  labels      = local.labels

  cluster_id = yandex_kubernetes_cluster.main.id
  version    = var.k8s_version

  instance_template {
    platform_id = var.node_platform_id

    resources {
      cores  = var.node_cores
      memory = var.node_memory_gb
    }

    boot_disk {
      type = "network-ssd"
      size = var.node_disk_gb
    }

    network_interface {
      subnet_ids         = [yandex_vpc_subnet.main.id]
      nat                = true
      security_group_ids = [yandex_vpc_security_group.k8s.id]
    }

    scheduling_policy {
      preemptible = false
    }
  }

  scale_policy {
    fixed_scale {
      size = var.node_count
    }
  }

  allocation_policy {
    location {
      zone = var.yc_zone
    }
  }
}

