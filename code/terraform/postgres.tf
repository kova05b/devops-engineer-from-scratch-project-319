resource "yandex_mdb_postgresql_cluster" "main" {
  name        = "${local.name_prefix}-pg"
  description = "Managed PostgreSQL for ${var.project_name}"
  labels      = local.labels

  environment = "PRODUCTION"
  network_id  = yandex_vpc_network.main.id

  security_group_ids = [
    yandex_vpc_security_group.postgres.id
  ]

  config {
    version = var.pg_version

    resources {
      resource_preset_id = var.pg_resource_preset_id
      disk_type_id       = var.pg_disk_type_id
      disk_size          = var.pg_disk_size_gb
    }
  }

  host {
    zone             = var.yc_zone
    subnet_id        = yandex_vpc_subnet.main.id
    assign_public_ip = false
  }
}

# Сначала пользователь, потом база с owner — иначе нельзя задать owner у database.
resource "yandex_mdb_postgresql_user" "main" {
  cluster_id = yandex_mdb_postgresql_cluster.main.id
  name       = var.pg_username
  password   = var.pg_password
}

resource "yandex_mdb_postgresql_database" "main" {
  cluster_id = yandex_mdb_postgresql_cluster.main.id
  name       = var.pg_db_name
  owner      = yandex_mdb_postgresql_user.main.name

  depends_on = [yandex_mdb_postgresql_user.main]
}

