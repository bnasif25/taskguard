# Demonstration Script — Target 7 Minutes 30 Seconds

The competition limit is eight minutes. Rehearse this script and stop rather than adding unplanned detail.

## 0:00–0:40 — Purpose and architecture

“TaskGuard is a deliberately small Go API that I productionised for Kubernetes. A client reaches a Service, which routes only to ready Pods. The application emits JSON logs and Prometheus metrics. The in-memory store is an explicit limitation so the demonstration stays focused on Kubernetes operations.”

Show `diagram/taskguard/architecture.svg` and the repository root.

## 0:40–1:30 — Reproducible deployment

```bash
make deploy
```

Explain that the single command verifies Minikube, installs the pinned monitoring stack, builds the correct architecture image inside Minikube, applies Kustomize, and waits for the rollout. Use an already-completed run during the recording so downloads do not consume the video.

## 1:30–2:30 — Workload and security

```bash
kubectl get deployment,pods,service,hpa,pdb -n taskguard
kubectl get deployment taskguard -n taskguard -o jsonpath='{.spec.template.spec.containers[0].securityContext}{"\n"}'
```

Explain two replicas, requests/limits, startup/readiness/liveness, rolling updates, HPA/PDB, non-root UID, dropped capabilities, read-only root filesystem, seccomp and zero RBAC permissions.

## 2:30–3:35 — API and readiness

Start the port-forward before recording:

```bash
kubectl port-forward -n taskguard service/taskguard 8080:8080
```

Use Postman to show:

1. `GET /healthz`
2. `GET /readyz`
3. `POST /tasks` with `{"title":"competition demo"}`
4. `GET /tasks`

Mention that ordinary Service traffic can reach different in-memory stores,
while this port-forward is pinned to one Pod until reconnecting. A production
version needs a shared database.

## 3:35–4:35 — Observability

```bash
kubectl logs -n taskguard deployment/taskguard --tail=10
kubectl get servicemonitor,prometheusrule -n taskguard
```

Show Prometheus `/targets`, then query:

```promql
sum(rate(taskguard_http_requests_total[5m]))
```

Explain the chain: traffic -> application `/metrics` -> ServiceMonitor -> Prometheus history -> PromQL/alerts.

## 4:35–6:20 — Failure and rollback

Use a terminal prepared at the relevant commands from `make failure-test`, or run the script if rehearsed timing is reliable.

Explain:

- A nonexistent image creates a failed new Pod.
- `maxUnavailable: 0` preserves the old ready replicas.
- Pod events identify the image-pull failure.
- `kubectl rollout undo` returns to the known-good revision.
- Service endpoints remain available during the failed rollout.

## 6:20–7:05 — CI and supply chain

Show the green GitHub Actions run. State that it checks formatting, static analysis, race-enabled tests, Kubernetes schemas, container build, secrets, misconfiguration, dependencies and image vulnerabilities. Show pinned base-image digests and pinned action commits briefly.

## 7:05–7:30 — Close honestly

“The strongest parts are reproducibility, least privilege, probes, monitoring and rollback. The largest production limitations are unauthenticated access, per-Pod in-memory state, a single-node lab, no production TLS edge, and no signed release pipeline. Those are documented rather than hidden.”

End recording by 7:30 to preserve a 30-second safety margin.

## Recording checklist

- Close unrelated windows and notifications.
- Increase terminal and browser font size.
- Prepare the port-forwards and browser tabs before starting.
- Never display tokens, passwords, kubeconfig contents or personal notifications.
- Record at 1080p if practical.
- Watch the complete export once and confirm it is under eight minutes.
