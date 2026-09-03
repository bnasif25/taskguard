# Learning Retrospective

Participant review required: these AI-assisted notes summarize the learning
conversation. The final autonomous implementation changes still need to be
reviewed and explained by the participant before submission.

## What I knew before starting

I had used command-line tools and APIs, but I was new to Go, container-image construction, Kubernetes probes, Services, EndpointSlices, autoscaling, disruption budgets and Prometheus. Initially, commands such as `curl`, `kubectl apply`, and PromQL felt disconnected because I could run them without seeing the system relationship behind them.

## What I learned

- An HTTP method describes an action: `GET` reads, `POST` creates or triggers, `PUT` updates, and `DELETE` removes.
- A Docker image packages the application; a container is a running instance of that image.
- A Deployment maintains Pods, while a Service supplies a stable address and routes only to ready endpoints.
- Liveness answers “should Kubernetes restart this container?” Readiness answers “should this Pod receive traffic?”
- Resource requests drive scheduling and HPA utilization calculations; limits bound consumption.
- A PDB controls voluntary eviction, not crashes, direct deletion or node failure.
- Prometheus is a collector and time-series store: TaskGuard exposes metrics, a ServiceMonitor describes how to collect them, and PromQL asks questions about the stored history.
- Observability is useful only when an operator has a diagnosis and recovery path.
- A Kubernetes manifest existing in Git is not proof that its behavior was enforced; the live cluster and its CNI/controllers matter.

## Decisions that changed

1. **API exploration moved from curl-only to Postman plus curl.** Postman made methods, bodies, status codes and responses visible; curl remained useful for repeatable checks.
2. **The Docker build was made architecture-aware and then pinned.** The project was developed on an M2 Mac. The final official Go builder uses a multi-architecture index with an immutable digest, and the runtime is an empty `scratch` image containing only the binary and CA bundle. Removing unused runtime OS packages resolved the final OpenSSL scan findings.
3. **The Makefile changed from shortcuts to a reproducible entry point.** The initial `make deploy` assumed the cluster, image and Prometheus CRDs already existed. It now creates/verifies the documented environment and builds the image inside Minikube.
4. **An unused Secret was removed.** The app does not consume a secret; pretending otherwise added configuration without reducing risk. The future secret-management approach is documented instead.
5. **Security settings were tightened.** The namespace now pins Restricted Pod Security Standards, the root filesystem is read-only, the API token is not mounted, and replicas have a topology-spread preference.
6. **Ingress was removed from the default workflow.** The clean-cluster rehearsal exposed slow registry downloads; source review also confirmed ingress-nginx had retired. A ClusterIP Service and local port-forward meet the lab's access needs without that dependency.
7. **Alert expressions were reviewed against their English meaning.** The restart alert now uses `increase(...[10m]) > 3`, and request alerts preserve namespace labels and avoid division by zero.

## Failures and how I investigated them

- Applying monitoring resources before installing the Prometheus Operator produced “no matches for kind ServiceMonitor/PrometheusRule.” I learned that custom resources require their CRDs first, then installed a pinned kube-prometheus-stack release.
- Searching for “taskguard” on Prometheus's query page returned nothing because the page expects PromQL, not a text search. I checked `/targets` first and then queried exact metric names.
- The default Minikube networking did not provide trustworthy NetworkPolicy enforcement evidence. I documented the limitation instead of claiming the YAML alone proved enforcement.
- Review found that normal graceful shutdown could block forever because a completion channel was not closed on `http.ErrServerClosed`. The goroutine now always closes it, and the API has automated tests.
- Review found a fake ConfigMap checksum annotation that Kustomize never substituted. It was removed; the deployment command now performs a rolling restart after configuration is applied.
- The original repository had deprecated Kustomize and Ingress fields and an alert formula that contradicted its comment. These were corrected and added to the AI error disclosure.
- A deliberately broken container-image rollout was used to practise reading Pod events and performing `kubectl rollout undo`; results are recorded in `TEST-REPORT.md`.

## What remains unsuitable for production

- Tasks are not durable and are not shared between replicas.
- There is no authentication, authorization or tenant separation.
- There is no production public edge, managed DNS or TLS.
- Minikube is a single-node development environment.
- NetworkPolicy enforcement was not proven with a production CNI.
- Images are built locally rather than signed and promoted through a registry.
- There is no SBOM, provenance, admission policy or runtime threat detection.
- Prometheus and alerts are local; there is no production retention or paging integration.
- There is no database backup/restore, disaster recovery or multi-zone test.

The project therefore demonstrates Kubernetes packaging and operations without claiming to be a complete production service.
