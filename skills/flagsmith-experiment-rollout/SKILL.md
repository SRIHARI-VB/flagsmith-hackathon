---
name: flagsmith-experiment-rollout
description: Run a complete A/B test with Flagsmith Experimentation and roll out the winner, using the Flagsmith CLI. Use when someone wants to test two or more versions of a feature, measure which one wins on a metric, and ship the winner safely. Covers preflight, flag and variant setup, metrics, experiment creation, SDK instrumentation, monitoring, the go/no-go decision and the rollout.
license: MIT
compatibility: Requires Flagsmith CLI v2 (logged in via `flagsmith login`, repo bound via `flagsmith init`), bash, and a Flagsmith environment with a connected warehouse.
metadata:
  author: "srihari-vb"
  version: "1.0"
allowed-tools: Bash(bash:*) Bash(flagsmith:*) Read Edit
---

# Experiment, then roll out the winner

All Flagsmith calls go through this skill's `scripts/fx.sh` (Flagsmith CLI only; terse output). Below, `$FX` means that file's path, e.g. `.claude/skills/flagsmith-experiment-rollout/scripts/fx.sh`. Run it from the repo root (where `flagsmith.json` is). Read its output instead of fetching raw JSON.

## Safety rules (always)
- **Never start or ship without explicit human approval in this conversation.** `start` and `ship` refuse unless you pass `--confirm <experiment_id>`. Only add that flag after the human says yes to that exact change.
- In an environment whose name contains "prod", `start`/`ship` also need `--confirm-production`. Say so to the human before asking.
- **Shipping is irreversible**: an ended experiment cannot be restarted.
- Never commit keys. Never edit `flagsmith.env` or `.env*` files.
- Don't change a running experiment's metrics or split to make results look better.

## 1. Preflight
`bash $FX preflight`. Stop on any `BLOCKER` and tell the human how to fix it. If `running:` lists the same flag, it can't take a second experiment.

## 2. Agree the plan (one message, wait for a yes)
Propose, then wait for approval:
- **Flag** (snake_case), **control value** (what users get today), **variant keys**.
- **Hypothesis**: "Changing X will increase Y because Z."
- **Primary metric**: one event that fires early in a visit. Aggregation: `occurrence` (did it happen), `count`, `sum` or `mean`. Direction `up`/`down`.
- **Guardrails** (optional): metrics that must not get worse, with `not_increase`/`not_decrease`.
- **Rollout %** (100 unless traffic is risky) and the **decision rule**. Default: ship the variant if the primary has ≥95% chance to win, no guardrail is losing, and the sample ratio check passes. Otherwise keep control.

Write the agreed plan to `EXPERIMENT.md` and commit it **before** starting, so the decision rule is fixed in advance.

## 3. Create (safe: nothing is live yet)
```
bash $FX flag <flag> <control_value> <variant_key>...
bash $FX metric <event> <aggregation> <up|down>        # once per metric
bash $FX create <flag> "<name>" "<hypothesis>" <rollout_pct> <primary_event>:increase [<guardrail_event>:not_increase]...
```
The primary metric must be listed **first**. The experiment is created as a draft. Note its id.

## 4. Instrument the app
Read `references/instrument.md` for the snippet in the app's language. Requirements:
- Events enabled at init. **The same identifier** for flag evaluation and events.
- Evaluate with `getExperimentFlag` (it records the exposure) where the user actually sees the variant.
- `trackEvent('<event>')` with names **exactly** matching the metrics (case-sensitive).
- Flush before the page or process ends.
Show the diff and get approval before applying it.

## 5. Start (needs approval)
Ask: "Start experiment <id> on <environment>?" On yes:
`bash $FX start <id> --confirm <id>`. Expect `running`. Edge caches can take ~20 s to serve the split.

## 6. Monitor
`bash $FX results <id>` (refreshes at most every 5 min). Results appear once every arm has ≥50 identities. Report the table and the `RECOMMEND:` line in plain words. Peeking is safe (Bayesian), but decide only when the agreed stop time or sample is reached. If `srm_p` < 0.001, stop: assignment is broken.

## 7. Decide and ship (needs approval)
Present the numbers, the `RECOMMEND:` line and the pre-registered rule. The human chooses. Then:
`bash $FX ship <id> <variant_key|control> --confirm <id>`
It ends the experiment, serves the choice to everyone, and polls until new identities get it (`verified:`).

## 8. Clean up (offer)
Replace the `getExperimentFlag` branch with the winning code and remove the losing variant. Once no code reads the flag, delete it with `flagsmith feature delete <flag> --yes`. Do this in a separate, reviewable change.

## Troubleshooting
- No exposures: the variant has no key, the user isn't identified, or the app exits before flushing.
- Conversions missing: event name mismatch or a different identifier for events.
- `refusing: pass --confirm`: by design. Get approval first.
