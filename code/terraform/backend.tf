# Remote state в Object Storage (S3).
#
# Важно: backend не умеет брать значения из переменных Terraform,
# поэтому bucket/ключи мы передаём через -backend-config при terraform init.
# Этот файл задаёт только "тип" бекенда и параметры совместимости с Yandex Object Storage.
#
# Пример init есть в README и в Makefile таргете tf-init.

terraform {
  backend "s3" {
    # Yandex Object Storage совместим с S3 API. Нужен полный URL со схемой https://
    # (иначе Terraform 1.6+ даёт "unsupported protocol scheme").
    endpoints = { s3 = "https://storage.yandexcloud.net" }
    region    = "ru-central1"

    skip_region_validation      = true
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true

    # bucket/key/access_key/secret_key задаются через -backend-config
  }
}

