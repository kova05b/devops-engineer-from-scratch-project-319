output "network_id" {
  value = yandex_vpc_network.main.id
}

output "subnet_id" {
  value = yandex_vpc_subnet.main.id
}

output "k8s_security_group_id" {
  value = yandex_vpc_security_group.k8s.id
}

output "postgres_security_group_id" {
  value = yandex_vpc_security_group.postgres.id
}

output "k8s_cluster_id" {
  value = yandex_kubernetes_cluster.main.id
}

output "k8s_node_group_id" {
  value = yandex_kubernetes_node_group.main.id
}

output "k8s_public_endpoint" {
  value = yandex_kubernetes_cluster.main.master[0].external_v4_endpoint
}

output "postgres_fqdn" {
  value = yandex_mdb_postgresql_cluster.main.host[0].fqdn
}

output "postgres_connection_string" {
  value     = "jdbc:postgresql://${yandex_mdb_postgresql_cluster.main.host[0].fqdn}:6432/${var.pg_db_name}?prepareThreshold=0"
  sensitive = false
}

output "app_bucket_name" {
  value = yandex_storage_bucket.app.bucket
}

output "app_s3_access_key" {
  value     = yandex_iam_service_account_static_access_key.app_bucket.access_key
  sensitive = true
}

output "app_s3_secret_key" {
  value     = yandex_iam_service_account_static_access_key.app_bucket.secret_key
  sensitive = true
}

output "lockbox_secret_id" {
  value = yandex_lockbox_secret.app.id
}

output "eso_lockbox_service_account_id" {
  value       = yandex_iam_service_account.eso_lockbox.id
  description = "ID SA для ESO (Lockbox); authorized key — см. eso_lockbox_authorized_key_json"
}

# JSON для kubectl create secret ... --from-file=authorized-key=...
# Не коммитьте и не логируйте: terraform output -raw eso_lockbox_authorized_key_json > eso-key.json
output "eso_lockbox_authorized_key_json" {
  value       = yandex_iam_service_account_key.eso_lockbox.private_key
  sensitive   = true
  description = "Authorized key (JSON) для SecretStore yandexlockbox"
}

# kubeconfig как output — удобно для быстрого старта.
# Если kube_token пустой, лучше получить креды через yc managed-kubernetes cluster get-credentials.
output "kubeconfig" {
  sensitive = true
  value = <<-YAML
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

