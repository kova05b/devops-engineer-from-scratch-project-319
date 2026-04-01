variable "yc_token" {
  description = "Yandex Cloud IAM token. Обычно: export YC_TOKEN=$(yc iam create-token)"
  type        = string
  sensitive   = true
}

variable "yc_cloud_id" {
  description = "Yandex Cloud cloud_id"
  type        = string
}

variable "yc_folder_id" {
  description = "Yandex Cloud folder_id"
  type        = string
}

variable "yc_zone" {
  description = "Зона по умолчанию"
  type        = string
  default     = "ru-central1-a"
}

variable "project_name" {
  description = "Префикс имён ресурсов"
  type        = string
  default     = "project-devops-deploy"
}

variable "network_cidr" {
  description = "CIDR для подсети"
  type        = string
  default     = "10.10.0.0/24"
}

# Pod-сеть кластера (overlay). Трафик к Postgres идёт с IP вида 10.112.x.x, не из network_cidr.
# Если у тебя другой диапазон — посмотри в консоли кластера или: yc managed-kubernetes cluster get --id ...
variable "k8s_pod_cidr" {
  description = "CIDR pod-сети Kubernetes (для SG Postgres: разрешить 5432 с подов)"
  type        = string
  default     = "10.112.0.0/16"
}

# Если после pod CIDR всё ещё timeout — включи true: проверим, что дело именно в SG (в проде выключи и сузь CIDR).
variable "postgres_allow_anywhere_ingress" {
  description = "Разрешить TCP 5432 на Postgres SG с 0.0.0.0/0 (только для отладки/учебы)"
  type        = bool
  default     = false
}

variable "k8s_version" {
  description = "Версия Managed Kubernetes (см. актуальные в консоли / yc managed-kubernetes list-versions)"
  type        = string
  default     = "1.32"
}

variable "node_count" {
  description = "Количество воркер-нод"
  type        = number
  default     = 2
}

variable "node_platform_id" {
  description = "Платформа виртуалок для нод"
  type        = string
  default     = "standard-v3"
}

variable "node_cores" {
  description = "vCPU на ноде"
  type        = number
  default     = 2
}

variable "node_memory_gb" {
  description = "RAM на ноде (GiB)"
  type        = number
  default     = 4
}

variable "node_disk_gb" {
  description = "Размер диска ноды (GiB)"
  type        = number
  default     = 30
}

variable "pg_version" {
  description = "Версия PostgreSQL"
  type        = string
  default     = "16"
}

variable "pg_db_name" {
  description = "Имя базы данных приложения"
  type        = string
  default     = "bulletins"
}

variable "pg_username" {
  description = "Пользователь базы данных"
  type        = string
  default     = "bulletins"
}

variable "pg_password" {
  description = "Пароль пользователя БД"
  type        = string
  sensitive   = true
}

variable "pg_resource_preset_id" {
  description = "Пресет ресурсов для Managed PostgreSQL"
  type        = string
  default     = "s2.micro"
}

variable "pg_disk_type_id" {
  description = "Тип диска для Postgres"
  type        = string
  default     = "network-ssd"
}

variable "pg_disk_size_gb" {
  description = "Размер диска Postgres (GiB)"
  type        = number
  default     = 20
}

variable "app_bucket_name" {
  description = "Bucket для картинок/файлов приложения (Object Storage)"
  type        = string
}

# Ключи для S3-backend state задаются только при terraform init (см. Makefile: TF_STATE_*),
# отдельные Terraform-переменные для них не нужны — иначе plan будет спрашивать лишнее.

variable "kube_token" {
  description = "IAM token для kubeconfig (используется только чтобы сгенерить kubeconfig output). Можно оставить пустым и получать креды через yc managed-kubernetes cluster get-credentials."
  type        = string
  sensitive   = true
  default     = ""
}

