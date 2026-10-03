# Conductor record: 2099-09-18-deliver-split-crlf

## Conductor record
| id | kind | claim | links | source | control (command -> observed) | written-to |
|----|------|-------|-------|--------|-------------------------------|------------|
| CR1 | check | codex on diff raised nothing open | 9 | `bash t.sh` 2026-09-01T00:00Z | `bash t.sh` -> exit 0 | n/a |
| CR2 | check | raw pipe | - | `ls | wc -l` 2026-09-01T00:00Z | `bash t.sh` -> exit 0 | n/a |
| CR3 | check | escaped pipe, empty control | - | `ls \| wc -l` 2026-09-01T00:00Z |  | n/a |
