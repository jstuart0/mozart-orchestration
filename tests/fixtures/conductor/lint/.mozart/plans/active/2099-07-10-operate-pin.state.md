# Pipeline state: 2099-07-10-operate-pin

**Last updated**: 2026-09-17T00:00Z
**Status**: in-progress
**Flow**: OPERATE — plan → apply
**Tier**: STANDARD
**Context**: BROWNFIELD
**Mode**: AUTONOMOUS

## Stage progress
- [x] 1. Intake + context pin — 2026-09-10T00:00Z

## Conductor record
| id | kind | claim | links | source | control (command -> observed) | written-to |
|----|------|-------|-------|--------|-------------------------------|------------|
| CR1 | check | the cluster context is prod-cluster | 1 | `kubectl config current-context` 2026-09-10T00:00Z | `kubectl config current-context` -> prod-cluster | n/a |

## Change ledger (OPERATE + INCIDENT mitigations)
| id | target (context/ns/host) | change | manifest (field: old -> new; ignore: paths; coupling) | snapshot path | rollback command | verify (observed) |
|----|--------------------------|--------|-------------------------------------------------------|---------------|------------------|-------------------|
| C1 | prod / api | scaled replicas and bumped image | a: 1 -> 2; b: x → y |  n/a  | `kubectl -n api scale deploy/api --replicas=1` | pods Ready |
