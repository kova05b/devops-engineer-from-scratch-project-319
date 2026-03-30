# Project DevOps Deploy

[![Actions Status](https://github.com/RuslanGilyazov83/devops-engineer-from-scratch-project-319/actions/workflows/hexlet-check.yml/badge.svg)](https://github.com/RuslanGilyazov83/devops-engineer-from-scratch-project-319/actions)

**Развёрнутое приложение (Ingress + ingress-nginx):** по умолчанию чарт создаёт **Ingress** с хостом `bulletin.local`, а сервис приложения — **ClusterIP**. Внешний **EXTERNAL-IP** выдаётся сервису контроллера `ingress-nginx-controller` в namespace `ingress-nginx`. Дальше: либо пропиши в `/etc/hosts` строку `<EXTERNAL-IP> bulletin.local`, либо проверяй через `curl -H "Host: bulletin.local" http://<EXTERNAL-IP>/api/bulletins?page=1&perPage=1`. Для сдачи зафиксируй в README свой URL или IP + хост.

Исходное приложение: [hexlet-components/project-devops-deploy](https://github.com/Hexlet-components/project-devops-deploy).

## Состав проекта

- `Dockerfile`, `.dockerignore` — контейнеризация приложения
- `terraform/` — инфраструктура в Yandex Cloud
- `k8s/bulletin-board/` — Helm-чарт приложения (`Chart.yaml`, `values*.yaml`, `templates/`)
- `k8s/secret.example.env` — пример переменных для Secret вне Helm
- `Makefile` — команды для Terraform, Helm и kubectl

## Требования

- Docker и доступ к **реестру образов** (например `docker login` для Docker Hub перед `docker push`)
- kubectl
- Terraform >= 1.6
- Yandex Cloud: **CLI `yc`** (часто с `yc iam create-token`) **или** аутентификация провайдера через **ключ сервисного аккаунта** (JSON), см. [документацию провайдера](https://registry.terraform.io/providers/yandex-cloud/yandex/latest/docs)
- Helm
- JDK 21 (для локальной сборки приложения)
- Node.js 20+ (для локальной фронтенд-разработки)

## Docker: сборка и публикация образа

### Сборка и локальный запуск

```bash
docker build -t bulletin-board:local .
docker run --rm -p 8080:8080 -p 9090:9090 bulletin-board:local
```

Проверка:

- `http://localhost:8080/`
- `http://localhost:9090/actuator/health`

### Публикация в Docker Hub

```bash
docker login
docker tag bulletin-board:local ruslangilyazov/project-devops-deploy:0.0.1
docker push ruslangilyazov/project-devops-deploy:0.0.1
```

Для обновления версии:

```bash
docker tag bulletin-board:local ruslangilyazov/project-devops-deploy:0.0.2
docker push ruslangilyazov/project-devops-deploy:0.0.2
```

## Terraform (Yandex Cloud)

### Переменные окружения

```bash
export YC_TOKEN="$(yc iam create-token)"
export YC_CLOUD_ID="your-cloud-id"
export YC_FOLDER_ID="your-folder-id"
export YC_ZONE="ru-central1-a"

export TF_STATE_BUCKET="your-tf-state-bucket"
export TF_STATE_KEY="terraform/project-devops-deploy/terraform.tfstate"
export TF_STATE_ACCESS_KEY="***"
export TF_STATE_SECRET_KEY="***"
```

### Команды Terraform

```bash
make tf-init
make tf-fmt
make tf-validate
make tf-plan
make tf-apply-auto
```

Проверка:

```bash
cd terraform && terraform output
```

### Что создаётся

- VPC (сеть, подсеть, NAT, security groups)
- Managed Kubernetes (cluster + node group)
- Managed PostgreSQL
- Object Storage bucket
- Lockbox secret (все чувствительные ключи приложения в payload)
- Сервисный аккаунт для External Secrets Operator с ролью `lockbox.payloadViewer` на этот секрет и authorized key (JSON) в Terraform output (sensitive)
- Remote state backend в Object Storage

## Kubernetes: деплой приложения

Манифесты собраны в Helm-чарт `k8s/bulletin-board/`. Базовый выкат:

```bash
make k8s-apply
make k8s-rollout
make k8s-status
```

### Ingress и ingress-nginx (приёмка: обязателен Ingress)

Чарт по умолчанию включает ресурс **Ingress** (`ingress.className: nginx`) и ожидает в кластере контроллер с тем же IngressClass. Рекомендуемый вариант — официальный чарт **ingress-nginx**.

**Порядок действий (один раз на кластер + выкат приложения):**

1. Убедись, что `kubectl` смотрит на нужный контекст Managed Kubernetes (`kubectl config current-context`).
2. Установи контроллер:  
   `make k8s-ingress-nginx-install`  
   (добавляет репозиторий Helm, ставит релиз `ingress-nginx` в namespace `ingress-nginx`, сервис контроллера — **LoadBalancer** с внешним IP в Yandex Cloud).
3. Дождись адреса:  
   `make k8s-ingress-controller-ip`  
   или `kubectl get svc -n ingress-nginx ingress-nginx-controller -o wide` — колонка **EXTERNAL-IP**.
4. Выкати приложение (создастся Ingress на хост из `values.yaml`, по умолчанию `bulletin.local`):  
   `make k8s-apply` → `make k8s-rollout`.
5. Проверь Ingress:  
   `kubectl get ingress -n bulletin`.
6. С хоста, с которого идёт проверка, либо добавь в **`/etc/hosts`** (Linux/macOS) или **`C:\Windows\System32\drivers\etc\hosts`** строку  
   `<EXTERNAL-IP> bulletin.local`,  
   либо вызови API без правки hosts:  
   `curl -sS -o /dev/null -w "%{http_code}\n" -H "Host: bulletin.local" "http://<EXTERNAL-IP>/api/bulletins?page=1&perPage=1"`  
   (ожидается `200`).
7. Для своего домена (prod): переопредели при установке Helm, например  
   `--set ingress.host=app.example.com`  
   и при необходимости включи TLS в `values.yaml` / `values-prod.yaml` (`ingress.tls` + Secret с сертификатом).

**Отключить Ingress и снова открыть приложение напрямую через LoadBalancer у сервиса** (не для сценария «обязателен Ingress»): в Helm задай `ingress.enabled=false` и `service.type=LoadBalancer`.

### Секреты (локально, без хранения в git)

```bash
cp k8s/secret.example.env .env.local-k8s
set -a
source .env.local-k8s
set +a
make k8s-secret-apply
```

### Yandex Lockbox и External Secrets Operator

Цель: чувствительные данные только в [Lockbox](https://yandex.cloud/ru/docs/lockbox/); в Git — только манифесты без значений. Синхронизация в кластер — [External Secrets Operator](https://external-secrets.io/latest/) и провайдер [Yandex Lockbox](https://external-secrets.io/latest/provider/yandex-lockbox/).

**ID секрета Lockbox** (после `terraform apply`):

```bash
cd terraform && terraform output lockbox_secret_id
```

**Инфраструктура (Terraform):** секрет `yandex_lockbox_secret.app` и его версия с полями `SPRING_DATASOURCE_*`, `STORAGE_S3_*` задаются в `terraform/lockbox.tf`. Отдельный SA `eso_lockbox` и привязка `lockbox.payloadViewer` — в `terraform/lockbox_eso.tf`. Authorized key для API (sensitive):

```bash
cd terraform && terraform output -raw eso_lockbox_authorized_key_json > ../eso-authorized-key.json
```

Файл `eso-authorized-key.json` в `.gitignore`. Если аутентификация с ключом из Terraform не проходит (известны нюансы с переносами строк в `private_key`), создайте ключ через CLI: `yc iam key create --service-account-id "$(terraform output -raw eso_lockbox_service_account_id)" -o eso-authorized-key.json`.

**Кластер:**

1. Установить оператор: `make k8s-eso-install` (чарт `external-secrets`, CRD).
2. Положить ключ в namespace приложения: `make k8s-eso-auth-secret-apply` (ожидается `eso-authorized-key.json` в корне репозитория).
3. Выкатить приложение с Lockbox: задать `LOCKBOX_SECRET_ID` и выполнить `make k8s-apply-lockbox`.

Пример с подстановкой ID из Terraform:

```bash
export LOCKBOX_SECRET_ID="$(cd terraform && terraform output -raw lockbox_secret_id)"
make k8s-apply-lockbox
```

Helm при этом использует `k8s/bulletin-board/values-lockbox.yaml`: `secret.create: false`, `secret.existingSecretName: bulletin-lockbox`, а также `k8s/bulletin-board/templates/lockbox-external-secrets.yaml` (`SecretStore` + `ExternalSecret`). Интервал опроса Lockbox — `lockbox.refreshInterval` (по умолчанию `1m`). Версия API CRD задаётся `lockbox.externalSecretsApiVersion` (по умолчанию `external-secrets.io/v1beta1`; если в кластере доступен только `v1`, переопределите на `external-secrets.io/v1`).

**Ротация значения в Lockbox (проверка на стенде):**

1. Добавьте новую **версию** секрета с обновлённым payload (консоль Yandex Cloud, `yc lockbox secret add-version` или изменение `yandex_lockbox_secret_version` в Terraform с последующим `terraform apply`).
2. Дождитесь следующего цикла `refreshInterval` или уменьшите интервал в values и выполните `helm upgrade`.
3. Убедитесь, что объект Kubernetes Secret обновился:  
   `kubectl get secret bulletin-lockbox -n bulletin -o jsonpath='{.data.SPRING_DATASOURCE_PASSWORD}' | base64 -d` (подставьте нужный ключ).
4. Spring Boot не подхватывает новые переменные окружения без перезапуска процесса. Для подтверждения нового пароля БД без простоя сервиса выполните rolling-перезапуск:  
   `kubectl rollout restart deployment/bulletin-app -n bulletin`  
   при `maxUnavailable: 0` в Deployment запросы обрабатываются оставшимися подами.

Так фиксируется цепочка: Lockbox → ESO обновляет Secret → при необходимости контролируемый rollout подов.

## Масштабирование, балансировка, обновления

### Масштабирование нод

- В Terraform по умолчанию `node_count = 2` (минимум две worker-ноды).

Проверка:

```bash
kubectl get nodes -o wide
```

### Балансировка и устойчивость

- Внешний HTTP-трафик: **`Ingress`** → сервис приложения; контроллер **ingress-nginx** (см. раздел выше) публикуется как `LoadBalancer` с **EXTERNAL-IP**.
- `Service` приложения по умолчанию **`ClusterIP`** (порт 80 → 8080 в поде).
- `PodDisruptionBudget` (`k8s/bulletin-board/templates/pdb.yaml`)
- `HorizontalPodAutoscaler` (`k8s/bulletin-board/templates/hpa.yaml`)
- `Deployment` c `RollingUpdate` (по умолчанию `maxSurge: 0`, `maxUnavailable: 1` — не требует третьего пода на двух нодах; строгий вариант — `-f k8s/bulletin-board/values-rolling-strict.yaml`)

Проверка:

```bash
make k8s-external-ip
make k8s-pdb
make k8s-hpa
kubectl get endpoints -n bulletin bulletin-app -o wide
```

### Rolling update

```bash
make k8s-set-image IMAGE=ruslangilyazov/project-devops-deploy:0.0.2
make k8s-rollout
kubectl get pods -n bulletin -l app=bulletin-app -o wide
```

Проверка без `5xx` (подставь **EXTERNAL-IP ingress-nginx** и хост из Ingress, по умолчанию `bulletin.local`):

```bash
EXT_IP=<INGRESS_CONTROLLER_EXTERNAL_IP>
INGRESS_HOST=bulletin.local
for i in $(seq 1 30); do
  code=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: $INGRESS_HOST" "http://$EXT_IP/api/bulletins?page=1&perPage=1")
  echo "$i -> $code"
done
```

## Мониторинг и логирование (Yandex Cloud)

### Что в репозитории

- В `k8s/bulletin-board/templates/deployment.yaml` добавлены аннотации Prometheus scrape:
  - `prometheus.io/scrape: "true"`
  - `prometheus.io/port: "9090"`
  - `prometheus.io/path: "/actuator/prometheus"`
- В `Makefile` добавлены проверки:
  - `make k8s-restarts`
  - `make k8s-prom-sample`
  - `make k8s-logs-5xx`

### Managed Prometheus

В workspace добавлены:

- Recording rules (`rules-step5.yml`)
- Alerting rules (`alerts-step5.yml`)

Запросы для дашборда:

```promql
sum(rate(http_server_requests_seconds_count{application="bulletins"}[5m]))
```

```promql
histogram_quantile(0.95, sum by (le) (rate(http_server_requests_seconds_bucket{application="bulletins"}[5m])))
```

```promql
sum(rate(http_server_requests_seconds_count{application="bulletins",status=~"5.."}[5m]))
```

```promql
sum(rate(container_cpu_usage_seconds_total{namespace="bulletin",container!="",image!=""}[5m]))
```

```promql
sum(container_memory_working_set_bytes{namespace="bulletin",container!="",image!=""})
```

```promql
sum(kube_pod_container_status_restarts_total{namespace="bulletin"})
```

### Cloud Logging

В облаке настраиваются отдельно: log group для логов кластера, retention, фильтры по `namespace=bulletin` и `app=bulletin-app`.

## Helm

Ссылки: [Helm](https://helm.sh/docs/), [best practices](https://helm.sh/docs/chart_best_practices/), опционально [Helmfile](https://helmfile.readthedocs.io/).

### Репозитории чартов (по необходимости)

```bash
make helm-repo-add
```

Подключает репозитории `ingress-nginx` и `external-secrets`. Контроллер Ingress ставится целевой командой `make k8s-ingress-nginx-install` (см. раздел «Ingress и ingress-nginx»).

### Структура чарта

- `k8s/bulletin-board/Chart.yaml`
- `k8s/bulletin-board/values.yaml` — базовые значения
- `k8s/bulletin-board/values-dev.yaml`, `values-prod.yaml` — примеры окружений
- `k8s/bulletin-board/templates/` — Deployment, Service (**ClusterIP** по умолчанию), ConfigMap, Secret, PDB, HPA, **Ingress** (включён по умолчанию, нужен ingress-nginx)

### Переопределение values (порядок слабее → сильнее)

1. `values.yaml` в чарте
2. Дополнительные файлы: `-f values-dev.yaml` (через `HELM_VALUES` в `Makefile`)
3. `--set` / `--set-string` в командной строке
4. Переменные окружения для CI не подставляются автоматически — передавай секреты через GitHub Secrets и `helm upgrade` с `--set` или временный файл (не коммитить)

Пример:

```bash
export HELM_VALUES="-f k8s/bulletin-board/values.yaml -f k8s/bulletin-board/values-dev.yaml"
make helm-upgrade
```

Проверка манифестов без кластера:

```bash
make helm-template
make helm-lint
```

Если `make k8s-apply` падает с `context deadline exceeded`, поды не успели стать Ready: `make k8s-diagnose`, при необходимости увеличь ожидание (`HELM_TIMEOUT=40m make k8s-apply`) или выкати без `--wait`: `make helm-upgrade-nowait`, затем `kubectl rollout status deploy/bulletin-app -n bulletin`.

### Релиз и откат

```bash
make helm-upgrade
helm history bulletin-board -n bulletin
make helm-rollback REVISION=1
```

`helm rollback` возвращает ресурсы к состоянию выбранной ревизии релиза (образы, replicas и т.д. — как в истории Helm).

### CI/CD (опционально)

Workflow [`.github/workflows/helm-deploy.yml`](./.github/workflows/helm-deploy.yml): ручной запуск (`workflow_dispatch`). Секрет `KUBE_CONFIG` — kubeconfig в **base64**. Если секрета нет, job завершается без ошибки.

Если приложение раньше ставилось через `kubectl apply` без Helm, перед первым `helm upgrade --install` сними старые объекты (иначе будет ошибка ownership): `make k8s-remove-legacy-app`, затем снова `make k8s-apply`. Либо удали namespace и создай заново.

## Полезные ссылки

- [Yandex Monitoring](https://cloud.yandex.ru/docs/monitoring)
- [Managed Service for Prometheus](https://yandex.cloud/ru/services/managed-prometheus)
- [Cloud Logging](https://yandex.cloud/ru/docs/logging/)
### Hexlet tests and linter status

Статус CI см. бейдж в начале файла.

# Project DevOps Deploy

Bulletin board service.

Этот репозиторий — рабочий форк для учебного DevOps-проекта. Исходное приложение: [hexlet-components/project-devops-deploy](https://github.com/Hexlet-components/project-devops-deploy).

> **Про апстрим**: репозиторий Hexlet только для чтения; свои Dockerfile, CI/CD и инфраструктуру держим в этом форке.

The default `dev` profile uses an in-memory H2 database and seeds 10 sample bulletins through `DataInitializer`, so the API works immediately after startup.

API documentation is available via Swagger UI at `http://localhost:8080/swagger-ui/index.html`.

## Project layout

- Backend (Spring Boot) lives in the repository root.
- Frontend (React Admin + Vite) is located in `frontend/`.
- Shared static assets for the backend are served from `src/main/resources/static` (populated by the frontend build when needed).

Keep this structure in mind when running commands—backend tooling (`gradlew`, `make run`, tests) run from the root, frontend tooling (`npm`, `vite`) runs from `frontend/`.

## Environment variables

Key variables are read directly by Spring Boot (see `src/main/resources/application.yml` and `application-prod.yml` for defaults):

| Variable                     | Description                                                   | Default                                      |
|------------------------------|---------------------------------------------------------------|----------------------------------------------|
| `SPRING_PROFILES_ACTIVE`     | Active Spring profile (`dev`, `prod`, etc.)                   | `dev`                                        |
| `SPRING_DATASOURCE_URL`      | JDBC URL for PostgreSQL in `prod`                             | `jdbc:postgresql://localhost:5432/bulletins` |
| `SPRING_DATASOURCE_USERNAME` | DB username                                                   | `postgres`                                   |
| `SPRING_DATASOURCE_PASSWORD` | DB password                                                   | `postgres`                                   |
| `STORAGE_S3_BUCKET`          | Bucket name for bulletin images                               | empty                                        |
| `STORAGE_S3_REGION`          | Region for the S3-compatible storage                          | empty                                        |
| `STORAGE_S3_ENDPOINT`        | Optional custom endpoint                                      | empty                                        |
| `STORAGE_S3_ACCESSKEY`       | Access key ID                                                 | empty                                        |
| `STORAGE_S3_SECRETKEY`       | Secret key                                                    | empty                                        |
| `STORAGE_S3_CDNURL`          | Optional public CDN prefix                                    | empty                                        |
| `MANAGEMENT_SERVER_PORT`     | Port for Spring Actuator endpoints (health, metrics, etc.)    | `9090`                                       |
| `JAVA_OPTS`                  | Extra JVM parameters (heap, `-Dspring.profiles.active`, etc.) | empty                                        |

All other variables supported by Spring Boot can be overridden the same way; check the application configuration files if you need to confirm a property name.

## Requirements

- JDK 21+.
- Gradle 9.2.1.
- PostgreSQL only if you run the `prod` profile with an external database.
- Make.
- NodeJS 20+

## Terraform infrastructure (Yandex Cloud)

Инфраструктура описана в директории [`terraform/`](./terraform) и включает:

- VPC (subnet + NAT + security groups)
- Managed Kubernetes (cluster + node group)
- Managed PostgreSQL
- Object Storage bucket для приложения
- Lockbox secret (DB/S3)
- Remote state Terraform в Object Storage (S3 backend)

### Требования к машине, с которой запускаем Terraform

- Yandex Cloud CLI `yc` (установка и quickstart: `https://yandex.cloud/ru/docs/cli/quickstart#install`)
- Terraform \(>= 1.6\)
- Доступ в интернет (Terraform будет скачивать провайдеры)
- Доступы в Yandex Cloud: `cloud_id`, `folder_id`, IAM token

### Быстрый старт: креды для Terraform

1. Авторизуйся в YC CLI и выбери cloud/folder:

```bash
yc init
```

2. Экспортируй переменные окружения (пример):

```bash
export YC_TOKEN="$(yc iam create-token)"
export YC_CLOUD_ID="your-cloud-id"
export YC_FOLDER_ID="your-folder-id"
export YC_ZONE="ru-central1-a"
```

### Bootstrap: bucket для Terraform state (делается один раз)

Terraform backend использует S3 bucket **до** `terraform apply`, поэтому bucket для state нужно создать заранее.
Проще всего — отдельным сервисным аккаунтом и статическим ключом.

Примерный сценарий (выполни в терминале, подставив свои значения):

1) Создай сервисный аккаунт (например `tf-state-sa`) и дай ему роль `editor` на folder.  
2) Создай static access key для этого аккаунта.  
3) Создай bucket для state (например `ruslangilyazov-tf-state`).  
4) Сохрани `access_key/secret_key` **в менеджере паролей**, не в репозитории.

Дальше для работы с Terraform в этом репозитории понадобятся переменные:

- `TF_STATE_BUCKET` — bucket для state
- `TF_STATE_KEY` — путь до state файла внутри bucket
- `TF_STATE_ACCESS_KEY` / `TF_STATE_SECRET_KEY` — ключи для backend

### Команды Terraform (через Makefile)

Перед выполнением команд экспортируй backend-переменные:

```bash
export TF_STATE_BUCKET="your-tf-state-bucket"
export TF_STATE_KEY="terraform/project-devops-deploy/terraform.tfstate"
export TF_STATE_ACCESS_KEY="***"
export TF_STATE_SECRET_KEY="***"
```

Дальше:

```bash
make tf-init
make tf-plan
make tf-apply
```

Если в WSL при `make tf-apply` ввод **`yes`** не срабатывает и пишет **Apply cancelled**, запусти без интерактива: **`make tf-apply-auto`** (это `terraform apply -auto-approve`). Либо зайди в каталог `terraform/` и выполни там `terraform apply` вручную.

Если при `terraform init` появляется ошибка **`Invalid provider registry host`** для `registry.terraform.io` — это значит, что прямой доступ к реестру HashiCorp из твоей сети недоступен. В репозитории уже подключено **зеркало** [`terraform-mirror.yandexcloud.net`](https://terraform-mirror.yandexcloud.net/) через файл `terraform/terraform_mirror.tfrc` и переменную `TF_CLI_CONFIG_FILE` в `Makefile`. Запускай команды через `make tf-*` из корня репозитория (не забудь `export` для `TF_STATE_*` перед `make tf-init`).

### Если apply упал на середине (403 на state, Lockbox, VPC, bucket)

1. **403 при сохранении state в S3 (`PutObject` / `Access Denied`)** — у сервисного аккаунта, чьи ключи стоят в `TF_STATE_*`, должна быть роль на каталог, например **`storage.admin`** (или минимум права на запись в этот bucket):

   ```bash
   yc resource-manager folder add-access-binding "$(yc config get folder-id)" \
     --role storage.admin \
     --subject serviceAccount:ajeijer50vi6ed2klosi
   ```

   (подставь свой `folder-id` и **ID** своего `tf-state-sa` из `yc iam service-account list`).

2. **`Permission denied` на Lockbox** — пользователю, от имени которого идёт `YC_TOKEN`, нужна роль **`lockbox.editor`** (или `editor` на каталог, если в вашей организации так принято) на тот же `folder`.

3. **`Operation is not permitted in the folder` для VPC** — проверь в консоли YC роли пользователя на каталог: нужны права на создание сетей (**`vpc.admin`** или **`editor`** на `folder`). Если ролей мало — добавь через IAM.

4. **Bucket 400 / folder_id** — для `yandex_storage_bucket` в конфиге задано `folder_id` (см. `terraform/storage.tf`): при создании бакета от имени пользователя без привязки к каталогу это обязательно.

5. **Файл `errored.tfstate`** после ошибки — после исправления прав на state попробуй загрузить состояние в бекенд:

   ```bash
   cd terraform
   terraform state push errored.tfstate
   ```

   Если Terraform предупредит о расхождении — напиши в поддержку курса или сделай `terraform plan` и при необходимости импорт уже созданных ресурсов (`terraform import ...`).

Форматирование/валидация:

```bash
make tf-fmt
make tf-validate
```

Outputs можно посмотреть так:

```bash
cd terraform && terraform output
```

## Kubernetes manifests and first deploy

Helm-чарт: [`k8s/bulletin-board/`](./k8s/bulletin-board) (`templates/`, `values.yaml`). Пример env для Secret вне чарта: `k8s/secret.example.env`.

## Scaling, load balancing and zero-downtime releases

В репозитории уже добавлено:

- масштаб нод в Terraform (`terraform/variables.tf`: `node_count = 2`)
- Внешний доступ через **Ingress** и контроллер **ingress-nginx** (`make k8s-ingress-nginx-install`); сервис приложения — **ClusterIP**
- `PodDisruptionBudget` (`k8s/bulletin-board/templates/pdb.yaml`)
- `HorizontalPodAutoscaler` (`k8s/bulletin-board/templates/hpa.yaml`, min=2, max=4)
- `Deployment` с `replicas: 2` и `RollingUpdate` (базово `maxSurge: 0`, `maxUnavailable: 1`; при запасе ресурсов — `values-rolling-strict.yaml`: `maxSurge: 1`, `maxUnavailable: 0`)

Если приложение уходит в `CrashLoopBackOff` или Deployment не успевает за **progress deadline**, сначала смотри события и логи: `make k8s-diagnose`. Частая причина — Secret с реальными `SPRING_DATASOURCE_*` под PostgreSQL, который перекрывает H2 из ConfigMap (переменные из `secretRef` идут после `configMapRef` и перезаписывают их). В чарте пустые поля `secret.stringData` **не попадают** в Secret, чтобы дефолтный dev (H2) не ломался. Если ты вручную создавал `bulletin-secret` со старыми значениями — пересоздай Secret под нужный профиль или удали лишние ключи.

### 1) Масштабировать кластер до 2+ нод

```bash
cd /mnt/c/GIT/devops-engineer-from-scratch-project-319
make tf-plan
make tf-apply-auto
```

Проверка:

```bash
kubectl get nodes -o wide
```

Должно быть минимум 2 `Ready` worker-ноды.

### 2) Применить манифесты балансировки и устойчивости

```bash
make k8s-apply
make k8s-rollout
make k8s-status
make k8s-pdb
make k8s-hpa
make k8s-external-ip
```

Когда у сервиса **ingress-nginx-controller** появится `EXTERNAL-IP`, приложение доступно по HTTP с заголовком `Host`, совпадающим с `ingress.host` (по умолчанию `bulletin.local`), либо после записи в `/etc/hosts`: `http://bulletin.local/` (см. раздел «Ingress и ingress-nginx» в начале README).

### 3) Проверить rolling update новой версии образа

```bash
# Подставь свой новый тег
make k8s-set-image IMAGE=ruslangilyazov/project-devops-deploy:0.0.2
make k8s-rollout
kubectl get pods -n bulletin -o wide
```

### 4) Проверить трафик и отсутствие 5xx

```bash
for i in $(seq 1 20); do curl -s -o /dev/null -w "%{http_code}\n" -H "Host: bulletin.local" "http://EXTERNAL-IP/api/bulletins"; done
```

Ожидаемо: коды `200`/`304` без `5xx` в серии запросов.

### Итог по масштабированию и HA

- Worker node group is scaled to 2+ nodes via Terraform (`terraform/variables.tf`, `node_count`).
- External access uses **Ingress** plus **ingress-nginx** (LoadBalancer on the controller service); the app `Service` defaults to **ClusterIP** (`service.yaml`, `ingress.yaml`).
- Zero-downtime baseline is configured:
  - `Deployment` with `RollingUpdate` (default `maxSurge: 0`, `maxUnavailable: 1`; optional `values-rolling-strict.yaml` for `maxSurge: 1`, `maxUnavailable: 0`)
  - `PodDisruptionBudget` (`k8s/bulletin-board/templates/pdb.yaml`, `maxUnavailable: 1`)
  - `HorizontalPodAutoscaler` (`k8s/bulletin-board/templates/hpa.yaml`, min 2 / max 4)
- Rolling update is validated with `kubectl rollout status`.
- Service checks are validated:
  - burst requests to `/api/bulletins` without `5xx`
  - logs confirm traffic/health checks are served by both pods (`instance` differs).

### Быстрые проверки

```bash
kubectl get nodes -o wide
kubectl get svc -n bulletin -o wide
kubectl get pdb -n bulletin
kubectl get hpa -n bulletin
kubectl rollout status deploy/bulletin-app -n bulletin
kubectl logs -n bulletin -l app=bulletin-app --since=10m | grep 'instance":"bulletin-app-'
```

## Monitoring and logging

Задача: метрики кластера и приложения, централизованные логи в Yandex Cloud и базовые алерты.

Что подготовлено в репозитории:

- В `k8s/bulletin-board/templates/deployment.yaml` добавлены аннотации для Prometheus-скрейпа:
  - `prometheus.io/scrape: "true"`
  - `prometheus.io/port: "9090"`
  - `prometheus.io/path: "/actuator/prometheus"`
- В `Makefile` добавлены быстрые проверки:
  - `make k8s-restarts` — рестарты pod-ов
  - `make k8s-prom-sample` — следы health/metrics в логах
  - `make k8s-logs-5xx` — поиск 5xx в логах приложения

### 1) Метрики (Yandex Monitoring / Managed Service for Prometheus)

1. Применить манифесты (чтобы аннотации скрейпа попали в pod template):

```bash
make k8s-apply
make k8s-rollout
```

2. Убедиться, что endpoints и pod-ы приложения готовы:

```bash
kubectl get pods -n bulletin -l app=bulletin-app -o wide
kubectl get endpoints -n bulletin bulletin-app -o wide
```

3. В Yandex Cloud открыть Monitoring / Managed Prometheus и проверить метрики:
   - CPU / Memory pod-ов
   - количество pod-ов
   - HTTP latency (например `http_server_requests` из Spring Boot actuator)

### 2) Логи (Cloud Logging)

1. В Cloud Logging создать/использовать log group для k8s-логов и настроить retention.
2. Подключить поток логов из Managed Kubernetes в этот log group.
3. Проверить фильтры:
   - по namespace `bulletin`
   - по приложению `bulletin-app`
   - по ошибкам `5xx` / `ERROR`

Локальные проверки перед Cloud Logging:

```bash
make k8s-logs
make k8s-logs-5xx
make k8s-restarts
```

### 3) Дашборды и алерты (базовый набор)

Рекомендуемый минимум:

- Availability:
  - readiness/liveness status
  - доля `5xx` ответов
- Performance:
  - latency p95/p99
  - RPS
- Stability:
  - restarts по pod
  - CPU/memory saturation

Алерты (база):

- `5xx rate > threshold` (например > 1-2% 5 минут)
- `p95 latency` выше SLA
- `restartCount` растёт
- pod не `Ready` дольше N минут

### Перед первым apply

1. Проверь контекст кластера:

```bash
kubectl config current-context
```

2. Создай локальный env-файл с секретами (в git не попадёт):

```bash
cp k8s/secret.example.env .env.local-k8s
```

Заполни `.env.local-k8s` реальными значениями DB/S3.

3. Загрузи переменные и создай/обнови Secret в кластере:

```bash
set -a
source .env.local-k8s
set +a
make k8s-secret-apply
```

### Деплой в кластер

```bash
make k8s-apply
make k8s-rollout
make k8s-status
```

Проверка подов:

```bash
kubectl get pods -n bulletin
kubectl get svc -n bulletin
```

### Проверка сервиса через port-forward

```bash
make k8s-port-forward
```

Пока команда активна, в новом терминале:

```bash
curl -i http://127.0.0.1:8088/api/bulletins
curl -i http://127.0.0.1:8088/swagger-ui/index.html
```

Логи:

```bash
make k8s-logs
```

### Быстрые команды

- `make k8s-apply` — применить все манифесты
- `make k8s-secret-apply` — создать/обновить Secret из env-переменных
- `make k8s-status` — показать namespace/deploy/pod/service
- `make k8s-rollout` — дождаться готовности deployment
- `make k8s-port-forward` — локальный доступ к service
- `make k8s-delete` / `make helm-uninstall` — удалить Helm-релиз в namespace

## Running

### Backend (local dev profile)

1. Install prerequisites from the **Requirements** section.
2. From the repository root start the backend:

    ```bash
    make run
    ```

3. Explore the API:
   - `GET http://localhost:8080/api/bulletins`
   - `GET http://localhost:8080/api/bulletins?page=1&perPage=9&sort=createdAt&order=DESC&state=PUBLISHED&search=laptop`
   - Swagger UI: `http://localhost:8080/swagger-ui/index.html`

`/api/bulletins` accepts pagination (`page`, `perPage`), sorting (`sort`, `order`) and filters (`state`, `search`). Filters are processed via JPA Specifications so the same contract is available to the React Admin frontend.

### Frontend (development build)

1. Open a second terminal and move into the frontend directory:

    ```bash
    cd frontend
    make install   # npm install
    make start     # Vite dev server on http://localhost:5173
    ```

2. The dev server proxies `/api` requests to `http://localhost:8080`, so keep the backend running.

### Production profile on a single host

1. Export the environment variables from the table above (DB access, S3 storage, `JAVA_OPTS`, etc.). The defaults in `application-prod.yml` show the exact property names if you need to double-check.
2. Build and launch the backend:

    ```bash
    make build
    java -jar build/libs/project-devops-deploy-0.0.1-SNAPSHOT.jar
    ```

3. Serve the frontend either from the same JVM (see **Build and serve from the Java app**) or deploy it separately (any static hosting/CDN works once `frontend/dist` is uploaded).

`JAVA_OPTS` can be used to control heap size, GC, or add any `-D` system properties without editing the manifest.

### Useful commands

See [Makefile](./Makefile)

## Frontend

### Development

1. Install Node.js 24 LTS (or newer) and npm.
2. Install dependencies and start the Vite dev server:

    ```bash
    cd frontend
    make install
    make start
    ```

3. The dev server proxies `/api` requests to `http://localhost:8080`, so keep the backend running via `make run` (or `./gradlew bootRun`) in another terminal.

### Image upload flow

1. Upload files via `POST /api/files/upload` (multipart form field named `file`).
2. The response contains `key` and a temporary `url`. Persist the `key` in the `imageKey` field when creating or updating bulletins; the backend stores only that identifier.
3. When you need a fresh link, call `GET /api/files/view?key=...` to receive a new URL (the backend issues presigned links on demand).

### Build and serve from the Java app

1. Build the production bundle:

    ```bash
    cd frontend
    make install      # run once
    make build    # outputs to frontend/dist
    ```

2. Copy the compiled assets into Spring Boot’s static resources (served from `src/main/resources/static`):

    ```bash
    rm -rf src/main/resources/static
    mkdir -p src/main/resources/static
    cp -R frontend/dist/* src/main/resources/static/
    ```

3. Restart the backend (`make run`) and open `http://localhost:8080/` — the React app will now be served directly by the Java application.

### Docker-образ: сборка, локальный запуск, публикация в реестр

В корне лежит [`Dockerfile`](./Dockerfile): внутри собирается фронт (`npm ci` / `npm run build`), результат кладётся в `src/main/resources/static`, затем `./gradlew bootJar` (тесты на этапе образа пропускаются, `-x test`). Финальный слой — JRE 21 и один JAR, приложение под непривилегированным пользователем `spring`.

**Сборка образа** (из корня репозитория):

```bash
docker build -t bulletin-board:local .
```

**Проверка без внешней БД** (профиль `dev` по умолчанию — H2 в памяти, UI на порту 8080):

```bash
docker run --rm -p 8080:8080 -p 9090:9090 bulletin-board:local
```

Открой `http://localhost:8080/` (админка + API), Swagger: `http://localhost:8080/swagger-ui/index.html`, actuator: `http://localhost:9090/actuator/health`.

**Прод-профиль в контейнере** — передай переменные окружения (Postgres, S3 и т.д., см. таблицу выше) и активный профиль, плюс при желании лимиты кучи через `JAVA_OPTS`:

```bash
docker run --rm -p 8080:8080 -p 9090:9090 \
  -e SPRING_PROFILES_ACTIVE=prod \
  -e SPRING_DATASOURCE_URL=jdbc:postgresql://host.docker.internal:5432/bulletins \
  -e SPRING_DATASOURCE_USERNAME=postgres \
  -e SPRING_DATASOURCE_PASSWORD=postgres \
  -e JAVA_OPTS="-Xms256m -Xmx512m" \
  bulletin-board:local
```

Полезные JVM-флаги: `-Xms/-Xmx`, `-Dspring.profiles.active=prod`, любые `SPRING_*` / `STORAGE_S3_*` из таблицы переменных.

---

#### Публикация образа в реестр

Сначала залогинься в выбранный реестр, затем пометь образ своим именем репозитория и запушь тег.

**Docker Hub**

1. Зарегистрируйся на [hub.docker.com](https://hub.docker.com), при необходимости создай репозиторий (например `bulletin-board`).
2. В терминале: `docker login` — введи Docker ID и пароль (или access token из *Account Settings → Security*).
3. Тег и push (подставь свой логин и имя репозитория):

    ```bash
    docker tag bulletin-board:local YOUR_DOCKERHUB_LOGIN/bulletin-board:0.0.1
    docker push YOUR_DOCKERHUB_LOGIN/bulletin-board:0.0.1
    ```

Документация: [docker image push](https://docs.docker.com/reference/cli/docker/image/push/).

**GitHub Container Registry (ghcr.io)**

1. В GitHub: *Settings → Developer settings → Personal access tokens* — создай token с правом `write:packages` (и при приватном репо — `read:package`).
2. Логин (подставь свой ник и токен):

    ```bash
    echo YOUR_GITHUB_TOKEN | docker login ghcr.io -u YOUR_GITHUB_USERNAME --password-stdin
    ```

3. Имя образа обычно в нижнем регистре: `ghcr.io/<owner>/<repo>:<tag>`:

    ```bash
    docker tag bulletin-board:local ghcr.io/your-github-user/bulletin-board:0.0.1
    docker push ghcr.io/your-github-user/bulletin-board:0.0.1
    ```

После первого push для публичного пакета можно выставить видимость в *GitHub → Packages → package settings*.

---

Ссылки по теме: [Dockerfile reference](https://docs.docker.com/reference/dockerfile/), [docker push](https://docs.docker.com/reference/cli/docker/image/push/).

## Monitoring / management ports

- Application traffic still uses port `8080` by default. Actuator endpoints (health, metrics, Prometheus scrape, logfile) listen on `MANAGEMENT_SERVER_PORT` (defaults to `9090` for every profile). Override it via env vars when you need a different port.
- If your deployment does **not** include Prometheus/Grafana yet, you can ignore the management port entirely; the application starts normally even if nothing scrapes `/actuator`. Simply avoid publishing the management port in Docker/Kubernetes until you need it.
- When monitoring is enabled, expose both ports, e.g. `docker run -p 8080:8080 -p 9090:9090 ...` and point Prometheus to `http://<host>:9090/actuator/prometheus`.
- Health probes are available at `/actuator/health/liveness` and `/actuator/health/readiness`; Grafana/Loki integrations should use the same port/env variable.

## Actuator endpoints (local check)

With the app running locally (`make run`), the management port defaults to `http://localhost:9090`. Useful URLs:

- `http://localhost:9090/actuator` — index of exposed endpoints.
- `http://localhost:9090/actuator/health`, `/actuator/health/liveness`, `/actuator/health/readiness` — readiness/liveness probes.
- `http://localhost:9090/actuator/metrics` and `http://localhost:9090/actuator/metrics/http.server.requests` — raw Micrometer metrics.
- `http://localhost:9090/actuator/prometheus` — Prometheus scrape output (open in browser or `curl` to confirm it renders).
- `http://localhost:9090/actuator/logfile` — current application log (same JSON that goes to stdout).

Override the host/port with `MANAGEMENT_SERVER_PORT` if you changed it; no Prometheus or Grafana instance is needed just to inspect these endpoints.

## Logging

- The backend ships with `src/main/resources/logback-spring.xml`, which writes structured JSON events to `stdout`. Every record contains `timestamp`, `app`, `environment`, `instance`, `logger`, `thread`, message arguments, MDC, and stack traces so Promtail/Loki (or any log shipper) can parse them without extra processing.
- No extra variables are required, but you can supply a different configuration via Spring Boot’s standard options (`LOGGING_CONFIG`, `logging.config`, or by overriding `logback-spring.xml` on the classpath).
- Container runtimes should forward `stdout`/`stderr` to your logging pipeline. Avoid redirecting logs to files unless your platform explicitly demands it.

## Image Upload Checks

### Local (dev profile, H2 + temp storage)

1. Start backend: `make run` (uses in-memory H2 and local filesystem storage under `/tmp/bulletin-images`).
2. Start frontend dev server: `cd frontend && npm install && npm run dev`.
3. In React Admin:
    - Create a bulletin or edit an existing one.
    - Use the “Upload image” field; after save, the image preview should load via the generated `imageUrl`.
4. Verify backend log: look for `Stored image` entries or check `/tmp/bulletin-images` for a new file. Refresh the bulletin show page to ensure the presigned/local URL still renders.

### Production / S3

1. Ensure the S3-related variables from the table above (bucket, region, access/secret keys, optional endpoint/CDN URL) are exported alongside the `prod` profile settings.
2. Deploy backend (e.g., `java -jar build/libs/project-devops-deploy-0.0.1-SNAPSHOT.jar`).
3. In the frontend (local or deployed), upload an image for a bulletin.
4. Confirm expected behavior:
    - Response from `/api/files/upload` contains a non-empty `key`.
    - Image shows up in bulletin show view (URL should either point to CDN or be a presigned S3 link).
    - Object exists in S3 bucket (check via AWS console or `aws s3 ls s3://your-bucket/bulletins/...`).
5. Optional: run `curl -I "$(curl -s .../api/files/view?key=... | jq -r .url)"` to ensure the presigned URL is valid from the production environment.
