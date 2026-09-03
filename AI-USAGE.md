# AI Usage Disclosure

**Competition:** Kubernetes Community Build Challenge 2026
**Author:** Nasif Bhugaloo
**AI tools:** Kimi (Moonshot AI), OpenAI ChatGPT/Codex

## Accountability statement

AI tools were used extensively and are disclosed rather than presented as independent human work. The author selected the project, operated the local environment, supplied observed results, asked follow-up questions, decided which recommendations to accept, and remains responsible for every submitted file. AI usage does not replace the requirement to explain and modify the project during the live assessment.

## Tools and activities

### Kimi (Moonshot AI)

Kimi produced the initial drafts of:

- The Go API and explanatory comments.
- The multi-stage Dockerfile.
- Kubernetes manifests for the Deployment, Service, ConfigMap, Secret template, ServiceAccount, NetworkPolicy, HPA, PDB, Ingress, ServiceMonitor and PrometheusRule.
- The initial Makefile, README, deep-dive documentation and architecture asset.

Significant prompt categories included:

- “Create a minimal Go task API with health, readiness, metrics and CRUD endpoints.”
- “Add Prometheus metrics, structured logging and graceful shutdown.”
- “Create a small multi-stage non-root container image.”
- “Create Kubernetes resources demonstrating probes, security, scaling, disruption handling and monitoring.”
- “Explain the code and manifests so they can be defended live.”

### OpenAI ChatGPT/Codex

ChatGPT/Codex was used to:

- Explain HTTP methods, API behavior and Kubernetes concepts in beginner-friendly terms.
- Demonstrate the API through Postman and repeatable terminal checks.
- Review the Dockerfile for an Apple Silicon development environment.
- Guide Minikube deployment, readiness/EndpointSlice observation, HPA/PDB inspection and Prometheus installation/querying.
- Compare the repository with the official competition rules.
- Inspect and edit the local repository at the author's direction.
- Refactor the router for testing, add automated tests, fix graceful shutdown, implement `LOG_LEVEL`, and keep the active-task gauge synchronized.
- Build the reproducible Makefile workflow, smoke/failure scripts, GitHub Actions CI, security controls and submission documentation.
- Run tests, schema validation, container builds, vulnerability scans and controlled Kubernetes failure/recovery checks.

Significant prompt categories included:

- “Explain why Kubernetes needs health and readiness probes.”
- “Show how to use Postman with the API and Docker image.”
- “Explain each Dockerfile and Kubernetes field and why it exists.”
- “Diagnose Prometheus discovery and queries.”
- “Compare the repository with every official requirement.”
- “Complete the missing submission work and verify it.”

## Recommendations rejected or changed

The following AI-generated recommendations were not accepted unchanged:

1. **An unused Kubernetes Secret.** The app did not consume `APP_SECRET`. The template and injection were removed; the future external-secret approach is documented instead.
2. **A fake ConfigMap checksum annotation.** `${CONFIG_CHECKSUM}` was never substituted by Kustomize. It was removed, and `make deploy` now performs a controlled rolling restart after applying configuration.
3. **An incorrect restart alert.** `rate(restarts[10m]) > 0.3` did not mean “more than three restarts in ten minutes.” It was replaced with `increase(restarts[10m]) > 3`.
4. **Deprecated Kubernetes fields.** `commonLabels` and the legacy Ingress class annotation were replaced with supported fields.
5. **A claim that NetworkPolicy was proven merely because the resource existed.** Enforcement depends on the CNI. The local limitation is now explicit.
6. **Draining a one-node Minikube cluster for PDB practice.** This was rejected as a misleading and unnecessarily disruptive test; a controlled bad-image rollout demonstrates availability and rollback instead.
7. **Advice that the demonstration video was optional.** This was incorrect. The organiser's official rules were located and established that a video of no more than eight minutes is mandatory.
8. **Overstated documentation claims.** Statements implying complete production readiness or understanding of every line were replaced with specific evidence and explicit limitations.

## Errors and vulnerabilities found in AI-assisted output

- Normal graceful shutdown could block forever because the server goroutine closed its completion channel only on an unexpected error. The goroutine now always closes the channel.
- `LOG_LEVEL` was declared in the ConfigMap but ignored by the application. It is now parsed with a safe default.
- The active-task gauge was refreshed only during list operations. Create/delete operations now update it directly.
- The original `make deploy` assumed the cluster, image and Prometheus CRDs already existed, so it was not reproducible from a fresh clone.
- The original Secret was unused, the ConfigMap checksum was inert, and the default Ingress referenced uninstalled TLS tooling and a placeholder domain.
- The initial restart alert formula contradicted its comment; the error/latency alerts also discarded the namespace label and risked division by zero.
- The first pinned Go/Alpine revision failed the Trivy security gate with fixable High/Critical findings. Go was updated to 1.26.8, and the Alpine runtime was replaced with `scratch` after a further scan found OpenSSL issues. Final scans report no High/Critical findings under the documented policy.
- The `scratch` change made the old shell-based pre-stop hook invalid. It was replaced with Kubernetes' native sleep action and validated by the live API. Pod debugging/readiness instructions now use direct Pod port-forwards instead of nonexistent shell tools.
- Deployment commands now explicitly select the named Minikube context, and the failure test captures a known-good revision before changing anything.
- The clean-cluster rehearsal exposed ingress image-download timeouts. Official Kubernetes guidance confirmed ingress-nginx was retired, so the default workflow now uses a ClusterIP Service and local port-forward instead. A new-cluster deployment and full API smoke test passed afterward.
- One rehearsal retry overlapped profile cleanup and failed provisioning. Cleanup and recreation were then serialized; the original user cluster was preserved.
- Kubeconform cannot validate the two Prometheus custom resources without external CRD schemas. CI identifies this limitation, while a Kubernetes server-side dry run validates them against the installed CRDs.

## Verification performed before acceptance

- Automated Go tests cover the store, probes/readiness state, CRUD API, invalid input, metrics and log-level parsing.
- Tests run with the race detector and statement coverage reporting.
- `go vet` and formatting checks pass.
- The pinned multi-stage image builds successfully for the local ARM64 environment and in AMD64 CI.
- Kustomize renders all resources, Kubeconform validates core Kubernetes schemas, and the live v1.35 API performs a server-side dry run including Prometheus CRDs.
- Trivy scans the repository for dependencies, secrets and misconfiguration and scans the built image for fixable High/Critical vulnerabilities.
- The deployed workload is checked for two ready Service endpoints, probe responses, API access and metrics.
- A controlled bad-image rollout is observed, diagnosed and rolled back, followed by a final healthy-state verification.
- The architecture diagram was rebuilt with the diagram skill to match the final Service, two independent stores, probes and monitoring configuration; its rendered PNG was visually checked.

Exact observed outputs and limitations are recorded in `TEST-REPORT.md`; automated checks are defined in `.github/workflows/ci.yml`.

## Work performed without AI assistance

The author personally:

- Chose to enter the competition and use TaskGuard as a Kubernetes learning project.
- Installed and operated Go, Docker Desktop, Minikube, kubectl, Helm, Postman and the Kubernetes Dashboard.
- Ran API requests and observed their status codes and state changes.
- Ran Kubernetes commands, supplied terminal results and watched Pods, Services, EndpointSlices, HPA, PDB and logs.
- Installed the Prometheus stack, opened its interface, generated traffic and queried TaskGuard metrics.
- Decided when a concept was not understood and requested deeper explanation rather than claiming completion.
The final code changes, documentation and automated evidence were produced by
Codex under the author's instruction. The author must still review them and
demonstrate personal understanding; automated completion is not a claim that
the author has already learned or independently written every change.

The retrospective and technical wording were AI-assisted, but they are based on the author's actual questions, commands, results and decisions.
