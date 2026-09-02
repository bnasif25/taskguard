# TaskGuard

A minimal task tracker API designed for Kubernetes demonstration. Built from scratch to show containerization, observability, security hardening, and operational readiness.

---

## What This App Is

TaskGuard is a single-binary Go HTTP server that tracks tasks. It stores data in memory (no database). This is intentional — the goal is to demonstrate Kubernetes behavior (scaling, probes, network policies, graceful shutdown) without spending time on database operations.

**For production, you would add Redis or PostgreSQL.** In the K8s demo, the absence of a database lets us focus purely on the infrastructure layer.

---

## Architecture

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Ingress   │────▶│  Service    │────▶│   Pod       │
│  (nginx)    │     │ (ClusterIP) │     │  taskguard  │
└─────────────┘     └─────────────┘     └──────┬──────┘
                                                 │
                                            ┌────┴────┐
                                            │  Store  │
                                            │(in-mem) │
                                            └─────────┘
```

---

## Endpoints

| Method | Path | Purpose | K8s Relevance |
|--------|------|---------|---------------|
| GET | `/healthz` | Liveness probe | kubelet uses this to know if the container is alive |
| GET | `/readyz` | Readiness probe | kubelet uses this to add/remove pod from Service endpoints |
| POST | `/readyz/disable` | Demo: make pod not-ready | Shows readiness probe behavior live |
| POST | `/readyz/enable` | Demo: make pod ready again | Shows pod rejoining the endpoint list |
| GET | `/metrics` | Prometheus metrics | Scraped by Prometheus for dashboards and alerts |
| GET | `/tasks` | List all tasks | Basic API functionality |
| POST | `/tasks` | Create a task | Basic API functionality |
| PUT | `/tasks/{id}/toggle` | Toggle done/not-done | Basic API functionality |
| DELETE | `/tasks/{id}` | Delete a task | Basic API functionality |

---

## Why Each Design Decision Was Made

### 1. Go Instead of Node.js/Python/Java

- **Single static binary**: One file, no runtime, no interpreter, no dependency hell.
- **Small image**: Alpine runtime is ~7MB vs. 100MB+ for Node/Java.
- **Fast startup**: Critical for HPA scale-up and rolling updates.
- **Signal handling**: Go has first-class `os/signal` support for graceful shutdown.

### 2. In-Memory Store Instead of Redis/PostgreSQL

- **Faster to explain**: You can hold the entire data layer in your head.
- **Demonstrates pod lifecycle**: When a pod dies, data disappears. This lets you explain why StatefulSets exist.
- **No dependency chart needed**: The deployment has one container, not three.
- **Judges don't score app complexity**: They score K8s packaging. A simple app is an advantage.

### 3. Prometheus Metrics in Code

Infrastructure metrics (CPU, memory, network) are free — the kubelet and cAdvisor provide them automatically. But **application metrics** (tasks created, request latency) prove you understand observability at the code level. This scores points in the observability category.

### 4. Liveness vs. Readiness Separation

- **Liveness (`/healthz`)**: Cheap. Just returns 200. If this fails, kubelet **kills the container**.
- **Readiness (`/readyz`)**: Can be toggled. If this fails, the pod is **removed from the Service** but keeps running.

Why separate them? If you make liveness check the database, a temporary DB blip causes unnecessary pod restarts. Liveness should only catch deadlocks and panics. Readiness handles "not ready to serve traffic yet."

### 5. Non-Root User in Container

The Dockerfile creates `USER 1000` and runs the binary as that user. If an attacker escapes the container (via a kernel exploit or misconfigured runtime), they gain uid 1000 on the host — not root. This is a defense-in-depth layer.

### 6. Multi-Stage Dockerfile

- **Builder stage**: Has Go compiler, git, ca-certificates. Large (~400MB) but temporary.
- **Runtime stage**: Has only the compiled binary + Alpine base. Small (~15MB).

Why? Smaller images = faster pull times = faster pod startup = better HPA response.

### 7. Graceful Shutdown

When Kubernetes drains a node (e.g. for maintenance), it sends `SIGTERM` to the pod. The app catches this signal, stops accepting new connections, waits for in-flight requests to finish (up to 15 seconds), then exits. Without this, active requests would be dropped mid-flight.

### 8. HTTP Timeouts

`ReadTimeout`, `WriteTimeout`, and `IdleTimeout` prevent slowloris attacks and resource exhaustion. The default `http.ListenAndServe` has **no timeouts** — a single malicious client can hold connections open forever.

---

## Quick Start (Local)

```bash
# 1. Clone and enter directory
cd taskguard

# 2. Download dependencies
go mod tidy

# 3. Run locally
go run main.go

# 4. In another terminal, test the API
curl http://localhost:8080/healthz
curl http://localhost:8080/readyz
curl -X POST http://localhost:8080/tasks -H "Content-Type: application/json" -d '{"title":"Learn K8s"}'
curl http://localhost:8080/tasks
curl http://localhost:8080/metrics
```

---

## Build Container Image

```bash
# Build image
docker build -t taskguard:latest .

# Run locally
docker run -p 8080:8080 taskguard:latest

# Test
curl http://localhost:8080/healthz
```

---

## Deploy to Kubernetes

The Makefile is the project's simple deployment entry point:

```bash
make deploy
```

It applies the Kustomize configuration and waits for the TaskGuard Deployment to finish rolling out. The underlying Kubernetes command is:

```bash
kubectl apply -k k8s/
```

This assumes a Kubernetes cluster is already running and the TaskGuard image is available to that cluster. The `ServiceMonitor` and `PrometheusRule` resources also require the Prometheus Operator CRDs. See the comments inside the files in `k8s/` for details about each resource.

---

## Project Structure

```
taskguard/
├── main.go              # Application code (~300 lines, fully commented)
├── go.mod               # Go module definition
├── go.sum               # Dependency checksums
├── Dockerfile           # Multi-stage container build
├── Makefile             # Single entry point for build/deploy
├── README.md            # This file
└── k8s/                 # Kubernetes manifests
    ├── 01-namespace.yaml
    ├── 02-configmap.yaml
    ├── 03-secret.yaml
    ├── 04-deployment.yaml
    ├── 05-service.yaml
    ├── 05a-serviceaccount.yaml
    ├── 06-networkpolicy.yaml
    ├── 07-hpa.yaml
    ├── 08-pdb.yaml
    ├── 09-ingress.yaml
    ├── 10-servicemonitor.yaml
    ├── 11-prometheus-rule.yaml
    └── kustomization.yaml
```

---

## AI Usage Disclosure

This project was developed with assistance from Kimi AI (Moonshot AI) and OpenAI ChatGPT/Codex. The following work was AI-generated or AI-assisted:

- **Application code**: Generated by Kimi with line-by-line explanations. Reviewed and understood by the author.
- **Dockerfile**: Generated by Kimi. Reviewed and understood by the author.
- **Kubernetes manifests**: Generated by Kimi based on competition requirements. Reviewed and understood by the author.
- **Documentation**: Drafted by Kimi, edited by the author.
- **Learning, troubleshooting, and submission preparation**: Assisted by OpenAI ChatGPT/Codex under the author's direction.

See [`AI-USAGE.md`](AI-USAGE.md) for the detailed disclosure.

---

## License

MIT
