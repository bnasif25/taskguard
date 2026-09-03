# Test and Verification Report

Verification date: 2–3 September 2026 (Mauritius time).

This report distinguishes observed results from configured capabilities. The
application is a Kubernetes operations demonstration, not a production service.
Saved terminal evidence has trailing whitespace normalized; result text is unchanged.

## Environment

- Apple Silicon M2 host, Docker Desktop engine 29.6.2.
- Minikube 1.38.1, Kubernetes 1.35.1, kubectl 1.36.3, Helm 4.2.4.
- Go 1.26.8 builder, digest-pinned multi-architecture input; static scratch runtime.
- kube-prometheus-stack 88.6.1; Trivy 0.74.0; Kubeconform 0.8.0.
- Local ARM64 checks and independent Ubuntu AMD64 GitHub Actions checks.

## Verification matrix

| Check | Observed result | Evidence |
|---|---|---|
| Go unit/API tests with race detection | PASS, 79.2% statement coverage | [Go test output](evidence/go-tests.txt) |
| Formatting and Go static analysis | PASS | `make lint`; CI code job |
| Shell scripts and workflow syntax | PASS | ShellCheck and actionlint 1.7.12 |
| Kustomize/schema validation | PASS: 10 resources, 8 valid, 2 custom schemas skipped, 0 errors | CI and server-side dry run |
| Kubernetes server-side dry run | PASS, including Prometheus CRDs | `kubectl --context=minikube apply --dry-run=server -k k8s/` |
| ARM64 image build | PASS | [Build and scan output](evidence/security-scan.txt) |
| Hardened container startup and SIGTERM | PASS, HTTP health response and exit code 0 | [Runtime output](evidence/container-runtime.txt) |
| Source/configuration security scan | PASS, no High/Critical findings | [Trivy output](evidence/security-scan.txt) |
| Container security scan | PASS, no fixable High/Critical findings | [Trivy output](evidence/security-scan.txt) |
| Existing-cluster deployment and full CRUD | PASS | [Deployment](evidence/deployment.txt), [smoke check](evidence/smoke-test.txt) |
| Final Service-only configuration | PASS, original cluster still healthy | [Final main-cluster smoke check](evidence/final-main-smoke.txt) |
| Fresh-cluster deployment and full CRUD | PASS, no preinstalled monitoring or application image | [Fresh deployment](evidence/clean-cluster-deployment-final.txt), [smoke check](evidence/clean-cluster-smoke.txt) |
| Bad-image rollout and rollback | PASS, real API checks passed during failure and after rollback | [Failure output](evidence/failure-rollback.txt) |
| Prometheus targets | PASS, two up targets, no scrape errors | [Monitoring evidence](evidence/monitoring-and-final-state.txt) |
| TaskGuard alert rules | PASS, all three loaded with health `ok` | [Monitoring evidence](evidence/monitoring-and-final-state.txt) |

The code checks include store operations, health/readiness state, complete CRUD,
invalid input, metrics, immediate active-task gauge updates and log-level parsing.
Coverage is a statement count, not a claim that every failure or concurrency case
has been tested.

## Controlled failure and recovery

1. Captured known-good Deployment revision 11, image `taskguard:1.0.0`.
2. Verified two ready endpoints: `10.244.0.43` and `10.244.0.44`.
3. Changed the new revision to the nonexistent image `taskguard:does-not-exist`.
4. The rollout timed out as expected after 45 seconds. Pod
   `taskguard-7b98498445-rwpbx` reported `ErrImagePull`/`ImagePullBackOff`.
5. Both original Pods remained ready. Health, readiness, create, list, toggle,
   delete and metrics checks succeeded while the rollout was stalled.
6. Restored the captured good revision, waited for rollout success and repeated
   the API checks.
7. A subsequent snapshot confirmed only two healthy running Pods, zero restarts,
   two ready endpoints and the restored `taskguard:1.0.0` image.

The immediate rollback log includes the failed Pod briefly terminating. That is
not a third ready endpoint; the later snapshot records its removal. The final
script now also explicitly waits for the failed Pod to be deleted.

There are no application logs from the bad-image Pod because its container never
started. Pod events, rather than `logs --previous`, are the correct evidence for
this failure. This is not a claimed CrashLoopBackOff test.

## Security remediation evidence

The first pinned Go/Alpine combination had fixable High/Critical vulnerabilities.
Updating Go removed the binary findings, but a further scan found OpenSSL issues
in the Alpine runtime. The final runtime uses `scratch`, containing only the
static binary and CA bundle. No ad hoc CVE ignore list was added; the fixable findings were remediated.

The scan gate selects High/Critical severity. CI and the image gate omit unfixed
vulnerabilities with `--ignore-unfixed`. A clean gate therefore does not mean
every severity, every unfixable issue or every future vulnerability is absent.
The final source and image scans found no findings under their stated policies.

The live Deployment also confirms non-root UID/GID 1000, default seccomp, all
capabilities dropped, no privilege escalation, a read-only root filesystem,
token automount disabled and a native ten-second pre-stop sleep. No application
Secret remains. The native sleep avoids depending on a shell in a scratch image.

## Clean-cluster rehearsal

The first isolated `taskguard-rehearsal` profile exposed an ingress add-on
download timeout. Node Docker logs reported repeated unexpected EOF errors.
Review of the official Kubernetes retirement notice also established that
ingress-nginx was no longer an appropriate new dependency.

The default deployment was simplified to the required ClusterIP Service and local
port-forward access; the retired controller and TaskGuard Ingress are no longer
installed by the workflow. The initial failed run is retained in
[evidence/clean-cluster-deployment.txt](evidence/clean-cluster-deployment.txt).
A retry also started before cleanup finished; that orchestration error is
retained in [evidence/rehearsal-retry.txt](evidence/rehearsal-retry.txt).
Subsequent cleanup and recreation are serialized.

The corrected single command, `make MINIKUBE_PROFILE=taskguard-rehearsal deploy`,
successfully created a new Kubernetes 1.35.1 cluster with 2 CPUs and 3 GiB memory,
installed monitoring and its CRDs, built the image from source and rolled out
TaskGuard. The follow-up smoke check passed health, readiness, full CRUD, metrics
and two ready endpoints. Both new Pods were Running with zero restarts.

This was a fresh cluster built from the working source tree, not a claim of an
independent third-party reproduction. Its successful output is retained in
[the final deployment log](evidence/clean-cluster-deployment-final.txt).
The documented teardown commands were then used only on that disposable profile;
the original `minikube` profile was preserved.

## CI evidence

The implementation commit `a0290b09e4f76c1c177528580e3ea1d9644f23a9` passed both
jobs in [GitHub Actions run 33667252964](https://github.com/bnasif25/taskguard/actions/runs/33667252964):
code/tests/manifest validation and container/runtime/security checks.
The final submitted commit must also have a green run after the packaging changes.

## What this report does not prove

- NetworkPolicy enforcement: the default bridge CNI is not treated as evidence of enforcement.
- Load-driven HPA scale-out: metrics and configuration are observed; no controlled load test is claimed.
- Node failure or multi-zone resilience: Minikube has one node.
- Persistent or shared task data: each Pod has an independent in-memory store.
- End-to-end paging delivery or a 30-day SLO history.
- The participant's personal understanding: that requires review, rehearsal and live defence.
