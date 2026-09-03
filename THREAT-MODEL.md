# TaskGuard Threat Model

Last reviewed: 2 September 2026

## Scope

This model covers the TaskGuard Go process, its container, Kubernetes resources, the Service/local-port-forward path, and Prometheus scraping in the documented local Minikube environment. Docker Desktop, Minikube, Helm, the Kubernetes control plane, and the host computer are trusted platform dependencies.

## Assets

- Availability of the API and its health endpoints.
- Integrity of the container image and Kubernetes configuration.
- Integrity of the in-memory task data while a Pod is running.
- Cluster credentials and any future application secrets.
- Metrics and logs used to diagnose the service.

## Trust boundaries

```text
In-cluster client -> ClusterIP Service -> ready TaskGuard Pods
Local operator -> kubectl port-forward -> one selected TaskGuard Pod
Prometheus namespace -------------------------------> /metrics
Developer workstation -> kubectl/Helm -> Kubernetes API
Public registries -> pinned image/chart inputs -> local cluster
```

## Threats and controls

| Threat | Impact | Current controls | Residual risk or next production step |
|---|---|---|---|
| Unauthenticated task modification | Any reachable client can create, toggle, or delete tasks | ClusterIP Service, loopback-bound local port-forward, NetworkPolicy | Accepted demo limitation. Add authentication/authorization before real use. |
| Malicious or vulnerable dependency/image | Code execution or compromised build | Official Go builder and scratch runtime, digest-pinned base images, pinned CI actions, Go checksums, Dependabot, Trivy | Add signed release images, SBOM and provenance for production. |
| Container escape or privilege escalation | Node/cluster compromise | Non-root UID/GID, default seccomp, all capabilities dropped, no privilege escalation, read-only root filesystem | Container isolation is not a security boundary against kernel vulnerabilities; patch the host/runtime. |
| Kubernetes API credential theft | Cluster API access from a compromised Pod | Dedicated ServiceAccount, no Role/RoleBinding, token automount disabled | Admission policies should enforce the same restrictions cluster-wide. |
| Secret exposure in Git | Credential theft and possible disqualification | The app needs no secret; no Secret is deployed; `.env*` is ignored; CI scans for secrets | Use External Secrets, Sealed Secrets or Vault if future features require secrets. Never commit raw/base64 credentials. |
| Network access from an unexpected Pod | Unauthorized API or metrics access | NetworkPolicy restricts named namespaces and TCP 8080 | NetworkPolicy is effective only with an enforcing CNI. The default local Minikube networking was not treated as proof of enforcement. |
| Denial of service | Slow or unavailable API | HTTP timeouts, resource limits, two replicas, HPA, readiness routing | Request bodies and task counts are not application-bounded; raw task paths can create many metric labels. Production needs explicit bounds, normalized metric labels, abuse controls and multi-node capacity. |
| Bad application rollout | New Pods fail and service becomes unavailable | Two replicas, readiness probe, `maxUnavailable: 0`, rollout status, rollback runbook | A severely constrained cluster may lack capacity for `maxSurge: 1`. |
| Data loss or inconsistent task views | Tasks disappear or differ between requests | Limitation is prominently documented | Accepted demo limitation. Use PostgreSQL/Redis and design migrations/backups for production. |
| Misleading monitoring | Operators miss or misread a failure | Application metrics, ServiceMonitor, three reviewed alert rules, SLI/SLO definitions | Alert delivery is local only and no production paging integration is configured. |

## Out of scope

- Protection of persistent user data, because the demo has no persistent store.
- Internet-grade identity, TLS and abuse prevention.
- Host, Docker Desktop and Minikube compromise.
- Multi-region disaster recovery.

These are explicit boundaries, not claims that the system is production-ready.
