# DevOps Engineer — Project 319

[![hexlet-check](https://github.com/kova05b/devops-engineer-from-scratch-project-319/actions/workflows/hexlet-check.yml/badge.svg)](https://github.com/kova05b/devops-engineer-from-scratch-project-319/actions/workflows/hexlet-check.yml)

## Развёрнутое приложение

**URL:** http://158.160.239.126

Проверка API:

```bash
curl "http://158.160.239.126/api/bulletins?page=1&perPage=1"
```

> Ingress host: `bulletin.local` → внешний IP контроллера `ingress-nginx`.  
> Если открываете в браузере — добавьте в `/etc/hosts`: `158.160.239.126 bulletin.local` и откройте `http://bulletin.local/`.

---

## Состав репозитория

```
code/
  terraform/   # Terraform — инфраструктура Yandex Cloud (Hexlet CI)
  k8s/         # Helm-чарт приложения (Hexlet CI)
terraform/     # Terraform — рабочая копия для локального деплоя
k8s/           # Helm-чарт — рабочая копия для локального деплоя
Makefile       # Команды для Terraform, Helm и kubectl
Dockerfile     # Сборка образа приложения
```

Исходный код приложения: [hexlet-components/project-devops-deploy](https://github.com/hexlet-components/project-devops-deploy).

---

## Инфраструктура (Terraform → Yandex Cloud)

Что создаётся при `terraform apply`:

- VPC: сеть, подсеть, NAT, security groups
- Managed Kubernetes (кластер + группа узлов, 2 ноды)
- Managed PostgreSQL
- Object Storage bucket
- Lockbox secret (DB и S3 credentials)
- SA для External Secrets Operator с ролью `lockbox.payloadViewer`
- Remote state backend в Object Storage

### Быстрый старт

```bash
export YC_TOKEN="$(yc iam create-token)"
export YC_CLOUD_ID="ваш cloud-id"
export YC_FOLDER_ID="ваш folder-id"
export YC_ZONE="ru-central1-a"

export TF_STATE_BUCKET="ваш-tf-state-bucket"
export TF_STATE_KEY="terraform/project-devops-deploy/terraform.tfstate"
export TF_STATE_ACCESS_KEY="***"
export TF_STATE_SECRET_KEY="***"

make tf-init
make tf-apply-auto
```

---

## Kubernetes / Helm

```bash
# Установить ingress-nginx (один раз)
make k8s-ingress-nginx-install

# Установить External Secrets Operator (один раз)
make k8s-eso-install

# Положить authorized key для Lockbox
make k8s-eso-auth-secret-apply

# Задеплоить приложение с Lockbox
export LOCKBOX_SECRET_ID="$(cd terraform && terraform output -raw lockbox_secret_id)"
make k8s-apply-lockbox

# Проверить статус
make k8s-status
make k8s-rollout
make k8s-external-ip
```

Helm-чарт: [`code/k8s/bulletin-board/`](./code/k8s/bulletin-board).

---

## Масштабирование и zero-downtime

- `replicas: 2`, `HorizontalPodAutoscaler` (min 2 / max 4)
- `PodDisruptionBudget` (maxUnavailable: 1)
- `RollingUpdate` (maxSurge: 0, maxUnavailable: 1)
- Внешний трафик: Ingress → ingress-nginx (LoadBalancer)

Rolling update:

```bash
make k8s-set-image IMAGE=ruslangilyazov/project-devops-deploy:0.0.2
make k8s-rollout
```

---

## Мониторинг

Поды приложения аннотированы для Prometheus-скрейпа (`/actuator/prometheus`, порт 9090).  
Логи — структурированный JSON в stdout (Cloud Logging / Yandex Monitoring).

Быстрые проверки:

```bash
make k8s-restarts
make k8s-logs-5xx
make k8s-prom-sample
```
