# Провайдер Yandex Cloud.
# Удобнее всего передавать креды через переменные окружения:
# - YC_TOKEN
# - YC_CLOUD_ID
# - YC_FOLDER_ID

provider "yandex" {
  token     = var.yc_token
  cloud_id  = var.yc_cloud_id
  folder_id = var.yc_folder_id
  zone      = var.yc_zone
}

