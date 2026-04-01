# Bucket для приложения (картинки/файлы).
# У yandex_storage_bucket нет аргумента labels в текущем провайдере — метки не задаём.
resource "yandex_storage_bucket" "app" {
  bucket    = var.app_bucket_name
  folder_id = var.yc_folder_id

  anonymous_access_flags {
    read = false
    list = false
  }
}

