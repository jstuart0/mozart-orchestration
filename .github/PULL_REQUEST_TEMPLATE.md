## Summary

- 
- 
- 

## Type

- [ ] Docs / prose improvement
- [ ] Agent prompt change (existing agent)
- [ ] New agent
- [ ] Pipeline shape or flow change
- [ ] Packaging / plugin manifest
- [ ] OSS hygiene (CI, templates, CHANGELOG, etc.)

## Files changed

List each file and the nature of the change (one line each).

## Tested

How did you verify the change?

- [ ] Read the diff carefully and confirmed intent matches implementation
- [ ] Ran `/mozart <sample request>` and observed correct behavior
- [ ] Confirmed JSON files validate: `python3 -m json.tool .claude-plugin/plugin.json > /dev/null`
- [ ] Ran the CI validation logic locally (see CONTRIBUTING.md)
- [ ] Other: ___

## Related issues

Closes #

## Checklist

- [ ] No homelab fingerprints or personal infrastructure references introduced
- [ ] Voice is consistent with `agents/mozart.md` and `INTEGRATION.md` (professional, no emojis)
- [ ] If a new agent was added: PIPELINE.md, mozart.md, README.md, and agents/README.md are all updated
- [ ] If a pipeline shape or flow was changed: PIPELINE.md and agents/mozart.md agree
- [ ] CHANGELOG.md has an entry for this change (if user-visible)
- [ ] JSON files validate

## Co-author

- [ ] Claude collaborated on this change — `Co-Authored-By: Claude <noreply@anthropic.com>` is included in the commit message
