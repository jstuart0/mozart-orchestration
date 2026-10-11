# Pipeline state: 2099-12-27-operate-critdrill

**Last updated**: 2026-09-17T00:00Z
**Status**: in-progress
**Flow**: OPERATE-FULL
**Tier**: CRITICAL (surface: schema)
**Context**: BROWNFIELD
**Mode**: AUTONOMOUS

## Stage progress
- [x] 1. Intake + context pin — 2026-09-17T00:00Z
- [x] 4. Pre-flight gate — 2026-09-18T00:00Z

## Conductor record
| id | kind | claim | links | source | control (command -> observed) | written-to |
|----|------|-------|-------|--------|-------------------------------|------------|
| CR1 | fact | the cluster context is prod-cluster | 1 | `kubectl config current-context` 2026-09-10T00:00Z | `kubectl config current-context` -> prod-cluster | n/a |
| CR2 | check | rehearsal: run; rollback drill: run | 4 | `bash test.sh` 2026-09-16T00:00Z | `bash test.sh` -> exit 0 | n/a |
