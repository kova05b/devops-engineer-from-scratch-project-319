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
# Kubernetes (app deploy)
# -----------------------------
K8S_DIR ?= k8s
K8S_NAMESPACE ?= bulletin
K8S_APP_LABEL ?= app=bulletin-app
K8S_LOCAL_PORT ?= 8088

k8s-apply:
	kubectl apply -k $(K8S_DIR)

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

k8s-delete:
	kubectl delete -k $(K8S_DIR)

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
	kubectl get svc bulletin-app -n $(K8S_NAMESPACE) -o wide

k8s-hpa:
	kubectl get hpa -n $(K8S_NAMESPACE)

k8s-pdb:
	kubectl get pdb -n $(K8S_NAMESPACE)

# Пример: make k8s-set-image IMAGE=ruslangilyazov/project-devops-deploy:0.0.2
k8s-set-image:
	@test -n "$(IMAGE)" || (echo "IMAGE is required"; exit 1)
	kubectl -n $(K8S_NAMESPACE) set image deploy/bulletin-app app=$(IMAGE)

.PHONY: k8s-apply k8s-secret-apply k8s-delete k8s-status k8s-rollout k8s-logs k8s-port-forward k8s-external-ip k8s-hpa k8s-pdb k8s-set-image
