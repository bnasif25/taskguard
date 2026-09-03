# Security Decisions

## Trusted sources and pinned inputs

The Dockerfile pins the official Go builder's readable version and multi-architecture index digest. The runtime has no operating-system package layer:

- `golang:1.26.8-alpine3.24@sha256:34efdd...e564`
- Runtime: Docker's empty `scratch` base; only the binary and CA bundle are copied in.

The monitoring dependency comes from the `prometheus-community` Helm repository and is pinned to kube-prometheus-stack `88.6.1`. GitHub Actions are pinned to immutable commit IDs. Go modules are versioned in `go.mod`, and their content hashes are stored in `go.sum`.

Dependabot proposes version updates. An update is accepted only after the tests, manifest checks, image build and security scans pass.

## Pod Security Standards

The `taskguard` namespace enforces Kubernetes `restricted` Pod Security Standards at version `v1.35`. The Deployment complies by using:

- `runAsNonRoot: true` with UID/GID 1000.
- `seccompProfile.type: RuntimeDefault`.
- `allowPrivilegeEscalation: false`.
- Every Linux capability dropped.
- A read-only root filesystem.
- A size-limited `emptyDir` mounted only at `/tmp`.
- No host namespaces, host paths, privileged mode or host ports.

## ServiceAccount and RBAC

TaskGuard does not call the Kubernetes API. It therefore receives a dedicated ServiceAccount with **no Role or ClusterRole binding**, and `automountServiceAccountToken: false` prevents an unnecessary API token from entering the Pod. Zero permissions is the least-privilege RBAC decision.

## Secrets approach

The current API needs no password, token or private key. The earlier unused Secret template was removed because injecting a pretend secret provides no security value.

If authentication or an external datastore is added, the selected production approach is an external secret store integrated through External Secrets Operator or the platform's native workload identity. A repository may contain only a schema/example with dummy values—never live credentials and never base64 presented as encryption.

## Network controls

The NetworkPolicy allows TCP 8080 only from the monitoring and TaskGuard namespaces. Local administrative access uses port-forwarding; this is not evidence of NetworkPolicy enforcement. Egress remains unrestricted because the application currently makes no outbound calls and future requirements are unknown.

The documented Docker-driver Minikube environment is a learning environment. NetworkPolicy enforcement depends on its CNI. The manifest is validated, but enforcement must be re-tested when deploying to a production CNI such as Cilium or Calico.

## Automated scanning policy

CI uses Trivy for dependency, secret, Kubernetes misconfiguration and container-image scanning. Fixable `HIGH` or `CRITICAL` findings fail the workflow. Unfixed upstream findings do not block this learning build; known exceptions must be recorded in the test report with their source and remediation plan.

The image scan uses `--ignore-unfixed`, so unfixed findings are omitted from that
gate's displayed results. No-finding output is not proof that all severities or
all future vulnerabilities are absent. Re-run without that flag for triage.

## Known limitations

- The API has no user authentication or authorization.
- There is no public edge. Production requires a maintained Gateway/Ingress implementation, managed DNS and TLS.
- The retired ingress-nginx controller is not installed by the deployment workflow. Existing unrelated cluster add-ons are not silently removed.
- The image is built locally into Minikube rather than signed and published.
- There is no admission controller enforcing image signatures or policy-as-code.
- There is no SBOM, SLSA provenance or runtime security sensor.
- Minikube is a single-node environment, so it cannot prove node-failure resilience.

See [THREAT-MODEL.md](THREAT-MODEL.md) for risks and mitigations.
