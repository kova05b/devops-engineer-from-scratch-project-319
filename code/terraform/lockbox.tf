resource "yandex_lockbox_secret" "app" {
  name        = "${local.name_prefix}-app-secrets"
  description = "DB + S3 credentials for application"
  labels      = local.labels
}

resource "yandex_lockbox_secret_version" "app" {
  secret_id = yandex_lockbox_secret.app.id

  entries {
    key = "SPRING_DATASOURCE_URL"
    # Порт 6432 — Odyssey (пул); прямой 5432 с нод/подов в MKS часто недоступен.
    # prepareThreshold=0 — совместимость JDBC с пулом (без server-side prepared statements).
    text_value = "jdbc:postgresql://${yandex_mdb_postgresql_cluster.main.host[0].fqdn}:6432/${var.pg_db_name}?prepareThreshold=0"
  }

  entries {
    key        = "SPRING_DATASOURCE_USERNAME"
    text_value = var.pg_username
  }

  entries {
    key        = "SPRING_DATASOURCE_PASSWORD"
    text_value = var.pg_password
  }

  entries {
    key        = "STORAGE_S3_BUCKET"
    text_value = yandex_storage_bucket.app.bucket
  }

  entries {
    key        = "STORAGE_S3_REGION"
    text_value = "ru-central1"
  }

  entries {
    key        = "STORAGE_S3_ENDPOINT"
    text_value = "https://storage.yandexcloud.net"
  }

  entries {
    key        = "STORAGE_S3_ACCESSKEY"
    text_value = yandex_iam_service_account_static_access_key.app_bucket.access_key
  }

  entries {
    key        = "STORAGE_S3_SECRETKEY"
    text_value = yandex_iam_service_account_static_access_key.app_bucket.secret_key
  }
}

