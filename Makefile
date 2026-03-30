test:
	./gradlew test

start: run

run:
	./gradlew bootRun

update-gradle:
	./gradlew wrapper --gradle-version 9.2.1

update-deps:
	./gradlew refreshVersions

install:
	./gradlew dependencies

build:
	./gradlew build

lint:
	./gradlew spotlessCheck

lint-fix:
	./gradlew spotlessApply

.PHONY: build

# -----------------------------
# Terraform (Yandex Cloud)
# -----------------------------
# Все параметры для backend (bucket/keys) задаём через переменные окружения:
# TF_STATE_BUCKET, TF_STATE_KEY, TF_STATE_ACCESS_KEY, TF_STATE_SECRET_KEY
#
# Зеркало провайдеров (если registry.terraform.io недоступен):
# terraform/terraform_mirror.tfrc подключается через TF_CLI_CONFIG_FILE.

TF_CLI_CONFIG_FILE := $(CURDIR)/terraform/terraform_mirror.tfrc
export TF_CLI_CONFIG_FILE

# Провайдер Terraform ждёт var.yc_* — это переменные Terraform, их задают как TF_VAR_yc_*.
# Удобно экспортировать YC_* из yc init (YC_CLOUD_ID, YC_FOLDER_ID, …) — пробросим в TF_VAR_*.
TF_VAR_yc_cloud_id ?= $(YC_CLOUD_ID)
TF_VAR_yc_folder_id ?= $(YC_FOLDER_ID)
TF_VAR_yc_zone ?= $(YC_ZONE)
TF_VAR_yc_token ?= $(YC_TOKEN)
export TF_VAR_yc_cloud_id TF_VAR_yc_folder_id TF_VAR_yc_zone TF_VAR_yc_token

tf-init:
	cd terraform && terraform init \
		-backend-config="bucket=$(TF_STATE_BUCKET)" \
		-backend-config="key=$(TF_STATE_KEY)" \
		-backend-config="access_key=$(TF_STATE_ACCESS_KEY)" \
		-backend-config="secret_key=$(TF_STATE_SECRET_KEY)"

tf-fmt:
	cd terraform && terraform fmt -recursive

tf-validate:
	cd terraform && terraform validate

tf-plan:
	cd terraform && terraform plan

tf-apply:
	cd terraform && terraform apply

# Без вопроса yes (удобно, если make «глотает» stdin в WSL)
tf-apply-auto:
	cd terraform && terraform apply -auto-approve

# Apply точечно (например, только security group), чтобы не трогать остальное.
tf-apply-auto-target:
	cd terraform && terraform apply -auto-approve -target="$(TARGET)"

tf-destroy:
	cd terraform && terraform destroy

.PHONY: tf-init tf-fmt tf-validate tf-plan tf-apply tf-apply-auto tf-apply-auto-target tf-destroy

# -----------------------------
# Kubernetes / Helm (app deploy)
# -----------------------------
K8S_DIR ?= k8s
K8S_NAMESPACE ?= bulletin
K8S_APP_LABEL ?= app=bulletin-app
K8S_LOCAL_PORT ?= 8088

HELM_CHART ?= k8s/bulletin-board
HELM_RELEASE ?= bulletin-board
# Пример переопределения: HELM_VALUES="-f k8s/bulletin-board/values.yaml -f k8s/bulletin-board/values-dev.yaml"
HELM_VALUES ?= -f $(HELM_CHART)/values.yaml
# Первый выкат: pull образа на двух нодах + старт JVM иногда дольше 10m.
HELM_TIMEOUT ?= 25m

k8s-apply: helm-upgrade

helm-lint:
	helm lint $(HELM_CHART)

helm-template:
	helm template $(HELM_RELEASE) $(HELM_CHART) -n $(K8S_NAMESPACE) $(HELM_VALUES)

helm-upgrade:
	helm upgrade --install $(HELM_RELEASE) $(HELM_CHART) \
		-n $(K8S_NAMESPACE) --create-namespace \
		--wait --timeout $(HELM_TIMEOUT) \
		$(HELM_VALUES)

# То же без --wait: если снова deadline, смотри `make k8s-diagnose`, потом `kubectl rollout status ...`.
helm-upgrade-nowait:
	helm upgrade --install $(HELM_RELEASE) $(HELM_CHART) \
		-n $(K8S_NAMESPACE) --create-namespace \
		$(HELM_VALUES)

k8s-diagnose:
	kubectl get pods,svc,hpa,pdb -n $(K8S_NAMESPACE) -o wide
	kubectl describe pod -n $(K8S_NAMESPACE) -l $(K8S_APP_LABEL) | tail -n 80
	kubectl logs -n $(K8S_NAMESPACE) -l $(K8S_APP_LABEL) --tail=60 --all-containers=true 2>&1 | tail -n 60

# Снять ресурсы, созданные раньше через kubectl (без меток Helm) — иначе helm upgrade ругается на ownership.
k8s-remove-legacy-app:
	kubectl delete pdb bulletin-app -n $(K8S_NAMESPACE) --ignore-not-found
	kubectl delete hpa bulletin-app -n $(K8S_NAMESPACE) --ignore-not-found
	kubectl delete ingress bulletin-app -n $(K8S_NAMESPACE) --ignore-not-found
	kubectl delete deploy bulletin-app -n $(K8S_NAMESPACE) --ignore-not-found
	kubectl delete svc bulletin-app -n $(K8S_NAMESPACE) --ignore-not-found
	kubectl delete cm bulletin-config -n $(K8S_NAMESPACE) --ignore-not-found
	kubectl delete secret bulletin-secret -n $(K8S_NAMESPACE) --ignore-not-found

helm-uninstall:
	helm uninstall $(HELM_RELEASE) -n $(K8S_NAMESPACE)

# Пример: make helm-rollback REVISION=1
helm-rollback:
	@test -n "$(REVISION)" || (echo "REVISION is required (helm history $(HELM_RELEASE) -n $(K8S_NAMESPACE))"; exit 1)
	helm rollback $(HELM_RELEASE) $(REVISION) -n $(K8S_NAMESPACE)

helm-history:
	helm history $(HELM_RELEASE) -n $(K8S_NAMESPACE)

# Репозитории чартов (ingress-nginx, external-secrets) — по необходимости.
# Версия чарта ESO (пин для воспроизводимости; см. https://github.com/external-secrets/external-secrets/releases )
EXTERNAL_SECRETS_CHART_VERSION ?= 0.14.2
# Чарт ingress-nginx (пин; см. https://github.com/kubernetes/ingress-nginx/releases )
INGRESS_NGINX_CHART_VERSION ?= 4.12.1
INGRESS_NGINX_NS ?= ingress-nginx

helm-repo-add:
	helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
	helm repo add external-secrets https://charts.external-secrets.io
	helm repo update

# Ingress NGINX controller (один раз на кластер; в Yandex MKS по умолчанию Service контроллера — LoadBalancer с EXTERNAL-IP).
k8s-ingress-nginx-install: helm-repo-add
	helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
		-n $(INGRESS_NGINX_NS) --create-namespace \
		--version $(INGRESS_NGINX_CHART_VERSION) \
		--set controller.service.type=LoadBalancer \
		--wait --timeout 15m

k8s-ingress-controller-ip:
	@echo "Ожидаемый сервис контроллера: ingress-nginx-controller в namespace $(INGRESS_NGINX_NS)"
	kubectl get svc -n $(INGRESS_NGINX_NS) -o wide

# External Secrets Operator (кластерный компонент; один раз на кластер).
k8s-eso-install: helm-repo-add
	helm upgrade --install external-secrets external-secrets/external-secrets \
		-n external-secrets --create-namespace \
		--version $(EXTERNAL_SECRETS_CHART_VERSION) \
		--set installCRDs=true \
		--wait --timeout 10m

# JSON authorized key SA для Lockbox (не коммитить). Создать файл:
#   cd terraform && terraform output -raw eso_lockbox_authorized_key_json > ../eso-authorized-key.json
# Альтернатива: yc iam key create --service-account-id "$(terraform output -raw eso_lockbox_service_account_id)" -o eso-authorized-key.json
ESO_KEY_FILE ?= eso-authorized-key.json

k8s-eso-auth-secret-apply:
	@test -f "$(ESO_KEY_FILE)" || (echo "Missing $(ESO_KEY_FILE). See Makefile comment above k8s-eso-auth-secret-apply."; exit 1)
	kubectl create secret generic yc-lockbox-authorized-key -n $(K8S_NAMESPACE) \
		--from-file=authorized-key=$(ESO_KEY_FILE) \
		--dry-run=client -o yaml | kubectl apply -f -

# Выкат приложения с Lockbox + ExternalSecret (LOCKBOX_SECRET_ID обязателен).
k8s-apply-lockbox:
	@test -n "$(LOCKBOX_SECRET_ID)" || (echo "LOCKBOX_SECRET_ID is required (cd terraform && terraform output -raw lockbox_secret_id)"; exit 1)
	helm upgrade --install $(HELM_RELEASE) $(HELM_CHART) \
		-n $(K8S_NAMESPACE) --create-namespace \
		--wait --timeout $(HELM_TIMEOUT) \
		-f $(HELM_CHART)/values.yaml \
		-f $(HELM_CHART)/values-lockbox.yaml \
		--set lockbox.secretId="$(LOCKBOX_SECRET_ID)"

k8s-secret-apply:
	@test -n "$(SPRING_DATASOURCE_URL)" || (echo "SPRING_DATASOURCE_URL is required"; exit 1)
	@test -n "$(SPRING_DATASOURCE_USERNAME)" || (echo "SPRING_DATASOURCE_USERNAME is required"; exit 1)
	@test -n "$(STORAGE_S3_ACCESSKEY)" || (echo "STORAGE_S3_ACCESSKEY is required"; exit 1)
	@test -n "$(STORAGE_S3_SECRETKEY)" || (echo "STORAGE_S3_SECRETKEY is required"; exit 1)
	kubectl -n $(K8S_NAMESPACE) create secret generic bulletin-secret \
		--from-literal=SPRING_DATASOURCE_URL="$(SPRING_DATASOURCE_URL)" \
		--from-literal=SPRING_DATASOURCE_USERNAME="$(SPRING_DATASOURCE_USERNAME)" \
		--from-literal=SPRING_DATASOURCE_PASSWORD="$(SPRING_DATASOURCE_PASSWORD)" \
		--from-literal=STORAGE_S3_ACCESSKEY="$(STORAGE_S3_ACCESSKEY)" \
		--from-literal=STORAGE_S3_SECRETKEY="$(STORAGE_S3_SECRETKEY)" \
		--dry-run=client -o yaml | kubectl apply -f -

k8s-delete: helm-uninstall

k8s-status:
	kubectl get ns $(K8S_NAMESPACE)
	kubectl get deploy,po,svc -n $(K8S_NAMESPACE)

k8s-rollout:
	kubectl rollout status deploy/bulletin-app -n $(K8S_NAMESPACE)

k8s-logs:
	kubectl logs -n $(K8S_NAMESPACE) -l $(K8S_APP_LABEL) --tail=200

k8s-port-forward:
	kubectl port-forward -n $(K8S_NAMESPACE) svc/bulletin-app $(K8S_LOCAL_PORT):80

k8s-external-ip:
	@echo "Сервис приложения (при ingress по умолчанию — ClusterIP, без внешнего IP):"
	kubectl get svc bulletin-app -n $(K8S_NAMESPACE) -o wide
	@echo ""
	@echo "Внешний IP для HTTP — у контроллера ingress-nginx (см. make k8s-ingress-controller-ip):"
	kubectl get svc -n $(INGRESS_NGINX_NS) -l app.kubernetes.io/component=controller -o wide 2>/dev/null || true

k8s-hpa:
	kubectl get hpa -n $(K8S_NAMESPACE)

k8s-pdb:
	kubectl get pdb -n $(K8S_NAMESPACE)

# Пример: make k8s-set-image IMAGE=ruslangilyazov/project-devops-deploy:0.0.2
k8s-set-image:
	@test -n "$(IMAGE)" || (echo "IMAGE is required"; exit 1)
	kubectl -n $(K8S_NAMESPACE) set image deploy/bulletin-app app=$(IMAGE)

# Быстрые проверки для шага мониторинга (метрики/рестарты/5xx в логах).
k8s-restarts:
	kubectl get pods -n $(K8S_NAMESPACE) -l $(K8S_APP_LABEL) \
		-o custom-columns=NAME:.metadata.name,RESTARTS:.status.containerStatuses[0].restartCount

k8s-prom-sample:
	kubectl logs -n $(K8S_NAMESPACE) -l $(K8S_APP_LABEL) --tail=200 | grep -E 'actuator/health|http.server.requests' || true

k8s-logs-5xx:
	kubectl logs -n $(K8S_NAMESPACE) -l $(K8S_APP_LABEL) --since=30m | grep -E '"status":5[0-9]{2}| 5[0-9]{2} ' || true

.PHONY: k8s-apply k8s-secret-apply k8s-delete k8s-status k8s-rollout k8s-logs k8s-port-forward k8s-external-ip k8s-hpa k8s-pdb k8s-set-image k8s-restarts k8s-prom-sample k8s-logs-5xx
.PHONY: k8s-ingress-nginx-install k8s-ingress-controller-ip
.PHONY: helm-lint helm-template helm-upgrade helm-upgrade-nowait helm-uninstall helm-rollback helm-history helm-repo-add k8s-remove-legacy-app k8s-diagnose
.PHONY: k8s-eso-install k8s-eso-auth-secret-apply k8s-apply-lockbox
