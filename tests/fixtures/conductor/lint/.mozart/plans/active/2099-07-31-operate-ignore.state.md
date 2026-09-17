# Pipeline state: 2099-07-31-operate-ignore

**Last updated**: 2026-09-17T00:00Z
**Status**: in-progress
**Flow**: OPERATE-FULL
**Tier**: STANDARD
**Context**: BROWNFIELD
**Mode**: AUTONOMOUS

## Stage progress
- [x] 1. Intake + context pin — 2026-10-01T00:00Z
- [x] 4. Pre-flight gate — 2026-10-01T00:10Z
- [x] 6. Verify — 2026-10-01T00:20Z

## Conductor record
| id | kind | claim | links | source | control (command -> observed) | written-to |
|----|------|-------|-------|--------|-------------------------------|------------|
| CR1 | fact | the cluster context is prod-cluster | 1 | `kubectl config current-context` 2026-10-01T00:00Z | `kubectl config current-context` -> prod-cluster | n/a |
| CR2 | check | the dry-run and snapshot are clean | 4 | `kubectl apply --dry-run=server -f deploy.yaml` 2026-10-01T00:10Z | `kubectl apply --dry-run=server -f deploy.yaml` -> no diff | n/a |
| CR3 | check | the deployment is healthy after apply | 6 | `kubectl -n api rollout status deploy/api` 2026-10-01T00:20Z | `kubectl -n api rollout status deploy/api` -> successfully rolled out | n/a |

## Change ledger (OPERATE + INCIDENT mitigations)
| id | target (context/ns/host) | change | manifest (field: old -> new; ignore: paths; coupling) | snapshot path | rollback command | verify (observed) |
|----|--------------------------|--------|-------------------------------------------------------|---------------|------------------|-------------------|
| C1 | prod / api | scaled replicas | spec.replicas: 2 -> 3; ignore: metadata.resourceVersion, server-defaults |  n/a  | `kubectl -n api scale deploy/api --replicas=2` | pods Ready |
| C2 | prod / api | bumped image | spec.template.spec.containers[0].image: a:1 -> a:2; ignore: metadata.resourceVersion, metadata.managedFields, metadata.annotations["a.b/c"], spec.containers[0].image, spec.template.metadata.annotations["x-injected"] |  n/a  | `kubectl -n api set image deploy/api api=a:1` | pods Ready |
| C3 | prod / api | scaled replicas | spec.replicas: 3 -> 4; ignore: spec.* |  n/a  | `kubectl -n api scale deploy/api --replicas=3` | pods Ready |
| C4 | prod / api | scaled replicas | spec.replicas: 4 -> 5; ignore: status.conditions[*] |  n/a  | `kubectl -n api scale deploy/api --replicas=4` | pods Ready |
| C5 | prod / api | scaled replicas | spec.replicas: 5 -> 6; ignore: spec. |  n/a  | `kubectl -n api scale deploy/api --replicas=5` | pods Ready |
| C6 | prod / api | scaled replicas | spec.replicas: 6 -> 7; ignore: status |  n/a  | `kubectl -n api scale deploy/api --replicas=6` | pods Ready |

