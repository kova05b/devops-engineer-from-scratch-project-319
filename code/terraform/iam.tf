# Сервисные аккаунты для Managed Kubernetes и Object Storage.
#
# Да, роли можно сделать более "тонкими".
# Здесь мы даём предсказуемый набор, чтобы инфраструктура поднялась без танцев.

resource "yandex_iam_service_account" "k8s_cluster" {
  name        = "${local.name_prefix}-k8s-cluster-sa"
  description = "Service account for Managed Kubernetes control-plane"
}

resource "yandex_iam_service_account" "k8s_node" {
  name        = "${local.name_prefix}-k8s-node-sa"
  description = "Service account for Managed Kubernetes node group"
}

resource "yandex_iam_service_account" "storage" {
  name        = "${local.name_prefix}-storage-sa"
  description = "Service account for Object Storage access (app bucket)"
}

# Самый надёжный для старта вариант — editor на folder.
# Потом можно заменить на более узкий набор ролей.
resource "yandex_resourcemanager_folder_iam_member" "k8s_cluster_editor" {
  folder_id = var.yc_folder_id
  role      = "editor"
  member    = "serviceAccount:${yandex_iam_service_account.k8s_cluster.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "k8s_node_editor" {
  folder_id = var.yc_folder_id
  role      = "editor"
  member    = "serviceAccount:${yandex_iam_service_account.k8s_node.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "storage_editor" {
  folder_id = var.yc_folder_id
  role      = "editor"
  member    = "serviceAccount:${yandex_iam_service_account.storage.id}"
}

# Статические ключи для доступа приложения к bucket.
resource "yandex_iam_service_account_static_access_key" "app_bucket" {
  service_account_id = yandex_iam_service_account.storage.id
  description        = "Static access key for application bucket"
}

