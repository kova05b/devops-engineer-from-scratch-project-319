output "network_id" {
  description = "Идентификатор VPC-сети Yandex Cloud."
  value       = yandex_vpc_network.main.id
}

output "subnet_id" {
  description = "Идентификатор подсети для кластера и БД."
  value       = yandex_vpc_subnet.main.id
}

output "k8s_security_group_id" {
  description = "Security group для Managed Kubernetes."
  value       = yandex_vpc_security_group.k8s.id
}

output "postgres_security_group_id" {
  description = "Security group для кластера PostgreSQL (MDB)."
  value       = yandex_vpc_security_group.postgres.id
}

output "k8s_cluster_id" {
  description = "Идентификатор кластера Yandex Managed Service for Kubernetes."
  value       = yandex_kubernetes_cluster.main.id
}

output "k8s_node_group_id" {
  description = "Идентификатор группы узлов Kubernetes."
  value       = yandex_kubernetes_node_group.main.id
}

output "k8s_public_endpoint" {
  description = "Публичный IPv4 endpoint API-сервера Kubernetes."
  value       = yandex_kubernetes_cluster.main.master[0].external_v4_endpoint
}

output "postgres_fqdn" {
  description = "FQDN хоста управляемого PostgreSQL."
  value       = yandex_mdb_postgresql_cluster.main.host[0].fqdn
}

output "postgres_connection_string" {
  description = "JDBC URL для приложения (порт 6432 Odyssey, prepareThreshold=0)."
  sensitive   = false
  value       = "jdbc:postgresql://${yandex_mdb_postgresql_cluster.main.host[0].fqdn}:6432/${var.pg_db_name}?prepareThreshold=0"
}

output "app_bucket_name" {
  description = "Имя бакета Object Storage для загрузок приложения."
  value       = yandex_storage_bucket.app.bucket
}

output "app_s3_access_key" {
  description = "Access key статического ключа SA для бакета приложения."
  sensitive   = true
  value       = yandex_iam_service_account_static_access_key.app_bucket.access_key
}

output "app_s3_secret_key" {
  description = "Secret key статического ключа SA для бакета приложения."
  sensitive   = true
  value       = yandex_iam_service_account_static_access_key.app_bucket.secret_key
}

output "lockbox_secret_id" {
  description = "Идентификатор секрета Lockbox с переменными для приложения."
  value       = yandex_lockbox_secret.app.id
}

output "eso_lockbox_service_account_id" {
  description = "ID SA для ESO (Lockbox); authorized key — см. eso_lockbox_authorized_key_json"
  value       = yandex_iam_service_account.eso_lockbox.id
}

# Не коммитьте и не логируйте: terraform output -raw eso_lockbox_authorized_key_json > eso-key.json
output "eso_lockbox_authorized_key_json" {
  description = "Authorized key (JSON) для SecretStore yandexlockbox"
  sensitive   = true
  value       = yandex_iam_service_account_key.eso_lockbox.private_key
}

# Если kube_token пустой, лучше получить креды через yc managed-kubernetes cluster get-credentials.
output "kubeconfig" {
  description = "Kubeconfig (YAML) для kubectl; токен из var.kube_token."
  sensitive   = true
  value       = <<-YAML
    apiVersion: v1
    kind: Config
    clusters:
    - name: ${yandex_kubernetes_cluster.main.name}
      cluster:
        server: https://${yandex_kubernetes_cluster.main.master[0].external_v4_endpoint}
        certificate-authority-data: ${yandex_kubernetes_cluster.main.master[0].cluster_ca_certificate}
    contexts:
    - name: ${yandex_kubernetes_cluster.main.name}
      context:
        cluster: ${yandex_kubernetes_cluster.main.name}
        user: yc
    current-context: ${yandex_kubernetes_cluster.main.name}
    users:
    - name: yc
      user:
        token: ${var.kube_token}
  YAML
}
