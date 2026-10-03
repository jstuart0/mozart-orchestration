# Conductor record: 2099-05-08-deliver-split-main

## Conductor record
| id | kind | claim | links | source | control (command -> observed) | written-to |
|----|------|-------|-------|--------|-------------------------------|------------|
| CR1 | check | the widget renders | - | `bash t.sh` 2026-09-01T00:00Z | `bash t.sh` -> exit 0 | n/a |
| CR2 | adjudication | otto's F1 claim does not reproduce | F1 | `bash t.sh` 2026-09-01T00:00Z | `bash repro.sh` -> no repro | n/a |
| CR3 | fact | the upstream API is unversioned | - | doc unverified |  | n/a |
