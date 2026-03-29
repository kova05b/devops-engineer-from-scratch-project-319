# Сервисный аккаунт для External Secrets Operator: чтение payload Lockbox через API.
# Ключ (authorized key JSON) попадает в state как sensitive — после первого apply
# один раз создайте Kubernetes Secret вручную (см. README / make k8s-eso-auth-secret-apply).

resource "yandex_iam_service_account" "eso_lockbox" {
  name        = "${local.name_prefix}-eso-lockbox-sa"
  description = "External Secrets Operator: read Lockbox secret for bulletin app"
}

resource "yandex_iam_service_account_key" "eso_lockbox" {
  service_account_id = yandex_iam_service_account.eso_lockbox.id
  description        = "Authorized key for ESO Yandex Lockbox provider"
}

resource "yandex_lockbox_secret_iam_member" "eso_payload_viewer" {
  secret_id = yandex_lockbox_secret.app.id
  role      = "lockbox.payloadViewer"
  member    = "serviceAccount:${yandex_iam_service_account.eso_lockbox.id}"
}
