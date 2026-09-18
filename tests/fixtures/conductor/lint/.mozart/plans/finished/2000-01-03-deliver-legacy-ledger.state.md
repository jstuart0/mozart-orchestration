# Pipeline state: 2000-01-03-deliver-legacy-ledger

**Last updated**: 2026-09-17T00:00Z
**Status**: CAMPAIGN COMPLETE — SHIPPED
**Flow**: FULL
**Tier**: STANDARD
**Context**: BROWNFIELD
**Mode**: AUTONOMOUS

## Change ledger (OPERATE + INCIDENT mitigations)
| id | target (context/ns/host) | change | snapshot path | rollback command | verify (observed) |
|----|--------------------------|--------|---------------|------------------|-------------------|
| C1 | prod / api | applied deployment.yaml | .mozart/snapshots/x.yaml | `kubectl apply -f x.yaml` | pods Ready |
| C2 | prod / api | scaled the deployment | .mozart/snapshots/y.yaml | `kubectl get deploy -o name | xargs -n1 kubectl scale --replicas=1` | pods Ready |
