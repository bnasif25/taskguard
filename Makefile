SHELL := /bin/sh

# Reproducible local environment proven on an Apple Silicon Mac.
APP_NAME                 := taskguard
IMAGE_TAG                := 1.0.0
IMAGE                    := $(APP_NAME):$(IMAGE_TAG)
REGISTRY                ?= ghcr.io/bnasif25
K8S_DIR                  := ./k8s
MINIKUBE_PROFILE        ?= minikube
KUBECTL                  := kubectl --context=$(MINIKUBE_PROFILE)
KUBERNETES_VERSION       := v1.35.1
MINIKUBE_MEMORY         ?= 3072
MINIKUBE_CPUS           ?= 2
PROMETHEUS_RELEASE       := prometheus
PROMETHEUS_NAMESPACE     := monitoring
PROMETHEUS_CHART_VERSION := 88.6.1
LOCAL_PORT              ?= 18080
KUBECONFORM_IMAGE        := ghcr.io/yannh/kubeconform:v0.8.0@sha256:faffaf43f95aa6425306e1ab8d6fcad72acb9049158f38e574c085ea1ec0f64e
TRIVY_IMAGE              := aquasec/trivy:0.74.0@sha256:62b1e65e8869bc4b4c6aa4fa2b21595256c7c2f6018a9d9ad61caf87187c1969
TRIVY_CACHE              := taskguard-trivy-cache

.DEFAULT_GOAL := help
.NOTPARALLEL: deploy
.PHONY: help check-tools cluster monitoring image build test lint validate security \
	deploy verify failure-test container-test clean destroy push

help:
	@echo "TaskGuard commands"
	@echo "  make deploy       Start/verify Minikube, install monitoring, build the image, and deploy"
	@echo "  make verify       Run API and Kubernetes smoke checks"
	@echo "  make test         Run Go tests with the race detector and coverage"
	@echo "  make lint         Check formatting, Go code, and Kustomize rendering"
	@echo "  make validate     Validate rendered Kubernetes resources with Kubeconform"
	@echo "  make security     Scan the source tree and image with Trivy"
	@echo "  make container-test Verify hardened runtime and graceful shutdown"
	@echo "  make failure-test Demonstrate a failed rollout and automatic recovery"
	@echo "  make clean        Remove TaskGuard resources but keep Minikube and monitoring"
	@echo "  make destroy      Delete the entire Minikube profile"

check-tools:
	@for tool in go docker kubectl minikube helm curl; do \
		command -v $$tool >/dev/null 2>&1 || { echo "ERROR: $$tool is required"; exit 1; }; \
	done
	@docker info >/dev/null 2>&1 || { echo "ERROR: Docker Desktop is not running"; exit 1; }

cluster: check-tools
	@if minikube status -p $(MINIKUBE_PROFILE) >/dev/null 2>&1; then \
		echo "==> Minikube profile '$(MINIKUBE_PROFILE)' is running"; \
	else \
		echo "==> Starting Minikube $(KUBERNETES_VERSION) with the Docker driver"; \
		minikube start -p $(MINIKUBE_PROFILE) --driver=docker --kubernetes-version=$(KUBERNETES_VERSION) \
			--memory=$(MINIKUBE_MEMORY) --cpus=$(MINIKUBE_CPUS); \
	fi
	@echo "==> Enabling metrics-server and ingress add-ons"
	@minikube addons enable metrics-server -p $(MINIKUBE_PROFILE) >/dev/null
	@minikube addons enable ingress -p $(MINIKUBE_PROFILE) >/dev/null

monitoring: cluster
	@echo "==> Installing kube-prometheus-stack $(PROMETHEUS_CHART_VERSION)"
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update
	helm upgrade --install $(PROMETHEUS_RELEASE) prometheus-community/kube-prometheus-stack \
		--kube-context $(MINIKUBE_PROFILE) \
		--namespace $(PROMETHEUS_NAMESPACE) \
		--create-namespace \
		--version $(PROMETHEUS_CHART_VERSION) \
		--wait \
		--timeout 10m
	@$(KUBECTL) wait --for=condition=Established \
		crd/servicemonitors.monitoring.coreos.com \
		crd/prometheusrules.monitoring.coreos.com \
		--timeout=120s

image: cluster
	@echo "==> Building $(IMAGE) directly inside Minikube"
	minikube image build -p $(MINIKUBE_PROFILE) -t $(IMAGE) .

build:
	@echo "==> Building Go binary and local container image"
	@mkdir -p bin
	go build -trimpath -o bin/taskguard ./main.go
	docker build -t $(IMAGE) .

test:
	@echo "==> Running Go tests with race detection and coverage"
	go test -race -cover ./...

container-test: build
	@IMAGE=$(IMAGE) ./scripts/container-test.sh

lint:
	@echo "==> Checking Go formatting"
	@test -z "$$(gofmt -l .)" || { echo "ERROR: run gofmt on the files listed above"; gofmt -l .; exit 1; }
	go vet ./...
	@echo "==> Rendering Kubernetes configuration"
	@kubectl kustomize $(K8S_DIR) >/dev/null

validate:
	@echo "==> Validating Kubernetes 1.35 resources with Kubeconform 0.8.0"
	@kubectl kustomize $(K8S_DIR) | docker run --rm -i $(KUBECONFORM_IMAGE) \
		-strict -summary -ignore-missing-schemas -kubernetes-version 1.35.0 -

security: build
	@docker volume create $(TRIVY_CACHE) >/dev/null
	@echo "==> Scanning source, dependencies, secrets, and Kubernetes configuration"
	docker run --rm -v "$(CURDIR):/work" -v $(TRIVY_CACHE):/root/.cache/trivy $(TRIVY_IMAGE) fs \
		--exit-code 1 --severity HIGH,CRITICAL --scanners vuln,misconfig,secret /work
	@echo "==> Scanning the built container image"
	docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v $(TRIVY_CACHE):/root/.cache/trivy $(TRIVY_IMAGE) image \
		--exit-code 1 --severity HIGH,CRITICAL --ignore-unfixed $(IMAGE)

# This is the competition's single deployment entry point.
deploy: monitoring image
	@echo "==> Applying TaskGuard Kubernetes resources"
	$(KUBECTL) apply -k $(K8S_DIR)
	@$(KUBECTL) delete secret taskguard-secrets -n $(APP_NAME) --ignore-not-found=true >/dev/null
	@echo "==> Restarting Pods so ConfigMap values are refreshed"
	$(KUBECTL) rollout restart deployment/$(APP_NAME) -n $(APP_NAME)
	@echo "==> Waiting for the TaskGuard rollout"
	$(KUBECTL) rollout status deployment/$(APP_NAME) -n $(APP_NAME) --timeout=180s
	@echo "==> Deployment complete. Run 'make verify'."

verify:
	@KUBE_CONTEXT=$(MINIKUBE_PROFILE) LOCAL_PORT=$(LOCAL_PORT) ./scripts/smoke-test.sh

failure-test:
	@KUBE_CONTEXT=$(MINIKUBE_PROFILE) LOCAL_PORT=$(LOCAL_PORT) ./scripts/failure-test.sh

clean:
	@echo "==> Removing TaskGuard resources"
	$(KUBECTL) delete -k $(K8S_DIR) --ignore-not-found=true

destroy:
	@echo "==> Deleting Minikube profile '$(MINIKUBE_PROFILE)'"
	minikube delete -p $(MINIKUBE_PROFILE)

push: build
	@echo "==> Pushing $(REGISTRY)/$(APP_NAME):$(IMAGE_TAG)"
	docker tag $(IMAGE) $(REGISTRY)/$(APP_NAME):$(IMAGE_TAG)
	docker push $(REGISTRY)/$(APP_NAME):$(IMAGE_TAG)
