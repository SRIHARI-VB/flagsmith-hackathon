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
- **2026-11-27 14:30–15:14 IST: wave 4 (130 sessions) plus 35 make-up sessions.** The PC lost its internet connection partway through wave 4, and 35 sessions failed before loading the page or reaching the LLM. Of those, 33 recorded nothing and 2 had their events dropped as designed, so none reached Flagsmith. The 35 make-up sessions replaced them, with the same prompt and model. In total, 130 sessions completed and were sent (59 control, 71 one_example). Flagsmith's exposures went from 4 / 5 (real visitors since the start) to **63 / 76**, exactly the logged numbers, with 0 excluded. **No duplicates:** the cards personas typed (135) plus 3 from real visitors equal Flagsmith's `card_created` total (138). The split is 63 vs 76 (binomial p ≈ 0.31). Flagsmith hasn't computed its SRM value yet. Also found: `fx.sh results` printed Flagsmith's empty statistics (shown below 50 identities per arm) as "chance=0% WINNING". Its recommendation line was correct ("keep running"). Fixed in 1802791. Interim results, not a decision: `first_card_created` control 37/63 (59%) vs one_example 30/76 (39%), with a 0.3% chance that one_example is better.
- **2026-11-27 (written before wave 5 sent anything): wave 5 runs on a different LLM.** At the owner's request, wave 5 runs now instead of tomorrow. Gemini's free daily quota is used up, and OpenRouter's free pool was rate-limited. Wave 5 therefore uses **`nvidia/nemotron-3.5-bolt-e4b`** through NVIDIA's API. It was chosen as the only fast model that returned valid JSON in the runner's request format; others were unavailable, too slow or returned nothing. **The persona prompt, intents, metrics and decision rule are unchanged.** Assignment is random per visitor and independent of the model, so the control vs one_example comparison stays fair *within* each model. Pooling the two models changes the visitor mix, though, so this is fixed now, before any wave 5 data:
  1. The decision uses Flagsmith's pooled result, as pre-registered.
  2. RESULTS.md also reports the first-card rate **per model** (Gemini waves vs. the Nemotron wave) from the run logs. Each session's log records its model.
  3. If the two models point in opposite directions, the result is reported as model-dependent and treated as inconclusive, so control is kept.
- **2026-11-27 15:30–15:43 IST: wave 5 (130 sessions, `nvidia/nemotron-3.5-bolt-e4b`).** All 130 sessions completed and were sent (65 control, 65 one_example), with 0 errors. Flagsmith's exposures went from 63 / 76 to **128 / 141**, exactly the logged numbers, with 0 excluded. Flagsmith's `first_card_created` sums (61 / 55) equal the logged converters, and typed cards equal `card_created` events (111 = 111), so there are no duplicates. Split: binomial p ≈ 0.46. **This completes the planned persona traffic. No further waves will be added, because adding traffic after seeing results would bias the stop.** The experiment stays running for real visitors until the planned stop.

  Interim results, not a decision:
  - **Pooled (Flagsmith):** `first_card_created` has a 6% chance that one_example is better (lift −18.1%, CI [−40.7%, +4.4%]): inconclusive. Guardrail `help_opened` has a 100% chance that one_example is better (lift −31%).
  - **Per model (logs, the pre-declared check):** Gemini 59% vs 41% (P(one_example better) ≈ 0.02); Nemotron 37% vs 38% (≈ 0.57). The models don't point in opposite directions; Nemotron shows no effect.
