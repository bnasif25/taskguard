# Competition Submission Checklist

Source of truth: the organiser's [official rules](https://www.linkedin.com/pulse/kubernetes-community-build-challenge-2026-rules-vincent-chu-wai-chow-47byf), reviewed on 2 September 2026. The Notion learning plan is not the requirements specification.

Deadline: 10 September 2026 at 23:59 UTC (11 September at 03:59 in Mauritius).

## Repository and technical evidence

- [x] Public source repository
- [x] Small application productionised on Kubernetes
- [x] Single documented `make deploy` entry point
- [x] Setup, verification and teardown instructions
- [x] Deployment, Service, resources, probes, labels and ConfigMap
- [x] Non-root restricted security context
- [x] Dedicated zero-permission ServiceAccount with no token mount
- [x] NetworkPolicy plus environment-enforcement limitation
- [x] Replicas, PDB, rolling update, rollback and topology decision
- [x] HPA metrics, thresholds, behavior and limitations explained
- [x] Automated tests
- [x] CI linting, tests, manifest validation and container build
- [x] CI vulnerability, secret and misconfiguration scanning
- [x] Logs, metrics and alert rules
- [x] Basic SLI/SLO
- [x] Troubleshooting and operational runbook

## Mandatory deliverables

- [x] `README.md`
- [x] Architecture diagram
- [x] `THREAT-MODEL.md`
- [x] `RUNBOOK.md`
- [x] `TEST-REPORT.md`
- [x] `AI-USAGE.md`
- [x] `RETROSPECTIVE.md`
- [ ] Personal demonstration video, no more than eight minutes
- [ ] Confirm final repository commit identifier after all changes
- [ ] Confirm selected track: Mauritius Community or International Community
- [ ] Confirm intended eligible CNCF certification
- [ ] Review the final AI-assisted changes and retrospective; practise explaining and modifying them

The remaining items require the participant's recording, review or personal
decision. The repository is not a submitted entry merely because its CI passes.
