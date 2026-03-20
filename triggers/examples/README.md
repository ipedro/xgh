# Trigger Examples

Copy any of these to `~/.xgh/triggers/` to activate them. Edit to your needs.

**DO NOT** edit files here directly — they're reset on plugin updates.

## Getting started

```bash
cp triggers/examples/p0-alert.yaml ~/.xgh/triggers/p0-alert.yaml
# edit ~/.xgh/triggers/p0-alert.yaml with your Slack channel
```

Then run `/xgh-trigger list` to see it. Run `/xgh-trigger test p0-alert` to dry-run it.

## Examples

| File | Event | Action | Level |
|------|-------|--------|-------|
| p0-alert.yaml | P0 issue in Jira | Slack #incidents + investigate | autonomous |
| pr-stale-reminder.yaml | PR awaiting review >24h | DM you | notify |
| npm-post-publish.yaml | `npm publish` succeeds | Tag release + Slack | create |
| weekly-standup.yaml | Monday 9am | Run /xgh-brief, post to Slack | autonomous |

## Global config

Before triggers fire, set your global cap in `~/.xgh/triggers.yaml`:

```yaml
enabled: true
action_level: notify   # start here; elevate to create/autonomous when ready
fast_path: true
cooldown: 5m
```
