# Experiment 2 plan (pre-registered): one example card vs. an empty board

> Written and committed **before** experiment 2 started. The git timestamp is the proof. Changes after launch go in "Amendments" at the bottom.
> Experiment 1 ([EXPERIMENT.md](EXPERIMENT.md)) is finished. Its result: the fully pre-filled sample board did **worse** than the empty board (4% chance to win on first card created). It also ended early, by mistake, as recorded there. Experiment 2 is the follow-up.

## Why this experiment
Experiment 1 suggests a full sample board makes the board look finished and gives people something to tidy up before starting. The empty board, by contrast, makes "create your first task" the only obvious action. The open question: **is any example at all helpful,** if it's small enough not to get in the way?

This hypothesis was formed **after** seeing experiment 1's data. That's legitimate for a new experiment, as long as the plan is fixed before experiment 2 collects anything. It is.

## Hypothesis
Adding **a single example card** (in "To do", clearly labelled, with a hint pointing to the add box) to the empty board will **increase the share of new visitors who create their first card**. It shows what a card looks like without making the board look finished.

## Setup
| | |
|---|---|
| Flag | `first_screen_v2` (multivariate), a new flag. `first_screen` is kept unchanged, because it holds experiment 1's record |
| Control (`control`) | Experiment 1's winner: the empty board, "Your board is empty: create your first task to get started." |
| Treatment (`one_example`) | The same page with one example card in "To do" ("Example: plan this week's priorities", tagged *example*, deletable with ✕) and a one-line hint: "Add your own task below. Delete the example whenever you like." |
| Unit | Visitor (a stable id; the same id for flag evaluation and events) |
| Rollout / split | 100% of visitors, 50% / 50% |
| Exposure | `useExperiment('first_screen_v2')` when the board renders, only after the server's assignment arrives (3-second fallback to control) |

Not tested: making the example card *editable*. Turning the example into the visitor's own card would make "create a card" ambiguous, so the primary metric would no longer mean the same thing in both arms.

## Metrics (the same definitions as experiment 1)
| Role | Metric | Event | Aggregation | Expected |
|---|---|---|---|---|
| **Primary** | First card created | `first_card_created` | Occurrence | Increase |
| Secondary | Cards created | `card_created` | Count | Increase |
| Guardrail | Help opened | `help_opened` | Occurrence | Should not increase |

## Decision rule (fixed now)
Ship `one_example` **only if all of these hold**:
1. The primary metric has **≥ 95% chance to beat control**.
2. The guardrail is **not Losing**.
3. The split is healthy: Flagsmith's SRM check, or a binomial test if Flagsmith shows none, gives p ≥ 0.001.
4. Each arm has **≥ 50 visitors**.

Otherwise, keep control. Inconclusive results are reported as inconclusive. **No moving the goalposts.**

**The experiment is ended (`ship`) only at the stop time below. Interim result checks are read-only.** Experiment 1's early stop is why this is spelled out.

## Traffic
- The same AI persona runner and the **same frozen prompt** as experiment 1, with no re-tuning, run in two waves: **wave 4** (Nov 27, after about 13:30 IST, about 130 sessions) and **wave 5** (Nov 28, about 130 sessions). The daily quota of the free LLM tier sets this size.
- Personas never see their variant. Events are held until a session completes, and failed sessions send nothing.
- Real visitors to the live app are included as they arrive.
- As in experiment 1, this tests the design and the decision process, not human preference.

## Stopping
Stop on **Nov 29, 2026, around 10:00 IST**. Stop earlier only if the split check fails; in that case, fix the problem and start over.

## Amendments
- **2026-11-26 14:41 IST: experiment 584 started.** It was set up and started with the Track 04 skill (`fx.sh flag`, `create`, `start --confirm 584`), after this plan was committed (3cb435a, 14:39 IST). Before the start, the app version reading `first_screen_v2` was deployed. Assignment check: 12 fresh identities queried through the flag API got 8 control and 4 one_example. This read-only query records no exposures; Flagsmith showed 0 exposures after the check. Nothing in the plan changed.
- **2026-11-27 08:30 IST: runner fix before any persona traffic (wave 4).** An audit of experiment 1 found that holding event requests open made the SDK time out and retry, so retries reached Flagsmith as duplicate events (see EXPERIMENT.md). The runner now answers the SDK's event requests immediately and keeps one copy of each. When the session ends, it sends them to Flagsmith once (session completed) or drops them (session failed). Tested before the wave:
  - a dry run logged each typed card exactly once;
  - a harmless non-metric test event sent this way was accepted by Flagsmith (HTTP 202).

  Unreadable LLM replies now fail the session instead of counting as a "leave". The persona prompt, the metrics and the decision rule are unchanged.
