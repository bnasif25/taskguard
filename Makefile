# Single entry point for the entire project.
# The competition rules require: "A single entry point (e.g., Makefile or script) for deployment."

.PHONY: all build test push deploy clean

# ---------------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------------
IMAGE_NAME ?= taskguard
IMAGE_TAG  ?= latest
REGISTRY   ?= ghcr.io/yourusername
K8S_DIR    := ./k8s

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
all: build

build:
	@echo "==> Building Go binary..."
	go build -o taskguard main.go
	@echo "==> Building container image..."
	docker build -t $(IMAGE_NAME):$(IMAGE_TAG) .

test:
	@echo "==> Running unit tests..."
	go test -v ./...
	@echo "==> Testing endpoints..."
	go run main.go &
	@sleep 2
	@curl -sf http://localhost:8080/healthz > /dev/null && echo "healthz: OK" || echo "healthz: FAIL"
	@curl -sf http://localhost:8080/readyz > /dev/null && echo "readyz: OK" || echo "readyz: FAIL"
	@pkill -f "go run main.go" || true

# ---------------------------------------------------------------------------
# Push
# ---------------------------------------------------------------------------
push:
	@echo "==> Tagging and pushing image..."
	docker tag $(IMAGE_NAME):$(IMAGE_TAG) $(REGISTRY)/$(IMAGE_NAME):$(IMAGE_TAG)
	docker push $(REGISTRY)/$(IMAGE_NAME):$(IMAGE_TAG)

# ---------------------------------------------------------------------------
# Deploy
# ---------------------------------------------------------------------------
deploy:
	@echo "==> Deploying to Kubernetes..."
	kubectl apply -k $(K8S_DIR)
	@echo "==> Waiting for rollout..."
	kubectl rollout status deployment/taskguard -n taskguard --timeout=120s
	@echo "==> Deployment complete."
	@echo "==> Run 'make verify' to test endpoints."

# ---------------------------------------------------------------------------
# Verify
# ---------------------------------------------------------------------------
verify:
	@echo "==> Getting pod name..."
	@POD=$$(kubectl get pod -n taskguard -l app.kubernetes.io/component=api -o jsonpath='{.items[0].metadata.name}') && \
	echo "Testing pod: $$POD" && \
	kubectl port-forward -n taskguard $$POD 8080:8080 &
	@sleep 3
	@echo "==> Testing /healthz..."
	@curl -sf http://localhost:8080/healthz && echo "  OK" || echo "  FAIL"
	@echo "==> Testing /readyz..."
	@curl -sf http://localhost:8080/readyz && echo "  OK" || echo "  FAIL"
	@echo "==> Testing /metrics..."
	@curl -sf http://localhost:8080/metrics | head -3
	@echo "==> Testing /tasks..."
	@curl -sf http://localhost:8080/tasks && echo "  OK" || echo "  FAIL"
	@pkill -f "kubectl port-forward" || true

# ---------------------------------------------------------------------------
# Teardown
# ---------------------------------------------------------------------------
clean:
	@echo "==> Deleting Kubernetes resources..."
	kubectl delete -k $(K8S_DIR) --ignore-not-found=true
	@echo "==> Cleanup complete."

# ---------------------------------------------------------------------------
# Lint / Validate
# ---------------------------------------------------------------------------
lint:
	@echo "==> Linting Go code..."
	gofmt -d main.go
	@echo "==> Validating Kubernetes manifests..."
	kustomize build $(K8S_DIR) | kubeval
	@echo "==> Lint complete."
