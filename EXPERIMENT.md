# Experiment plan (pre-registered)

> Written and committed **before** the experiment started or any data was collected.
> The git timestamp of this file is the proof. Changes after launch go in the "Amendments" section at the bottom.

## Question
Do new visitors get started faster when their first screen is a board pre-filled with example cards, compared with an empty board?

## Hypothesis
Showing new visitors a **pre-filled sample board** will **increase the share who create their first card** in their first session, because they see what a finished board looks like instead of having to imagine it.

## Setup
| | |
|---|---|
| Flag | `first_screen` (multivariate) |
| Control (`control`) | Empty board, "Your board is empty: create your first task to get started." |
| Treatment (`sample_data`) | Board pre-filled with 3 example cards (one per column) and a "make it yours" hint with a "Clear examples" link |
| Unit | Visitor (a stable id kept in localStorage; the same id is used for flag evaluation and events) |
| Rollout | 100% of visitors |
| Split | 50% control / 50% sample_data |
| Exposure | Recorded by `useExperiment('first_screen')` when the board renders |
| Environment | Flagsmith Cloud, Development environment, managed warehouse |

## Metrics
| Role | Metric | Event | Aggregation | Expected |
|---|---|---|---|---|
| **Primary** | First card created | `first_card_created` | Occurrence (did it happen at least once) | Increase |
| Secondary | Cards created | `card_created` | Count per visitor | Increase |
| Guardrail | Help opened | `help_opened` | Occurrence | Should not increase (a rise would suggest the sample board confuses people) |

The primary metric fires within seconds of a visit, which suits a four-day test.

## Decision rule (set now, applied at the end)
Ship `sample_data` to everyone **only if all of these hold**:
1. The primary metric shows **≥ 95% chance to beat control** (Flagsmith's "Winning" threshold).
2. The guardrail `help_opened` is **not Losing** (chance to beat control ≥ 5% in the "lower is better" sense).
3. The **sample ratio mismatch (SRM) check is clean**, so the 50/50 split actually happened.
4. Each arm has **≥ 50 visitors and ≥ 5 conversions** (Flagsmith's minimum before it shows results).

If the primary metric is **Losing** (< 5%): keep control.
If it is **Inconclusive**: report it as inconclusive, keep control, and say what sample size would be needed. **No moving the goalposts.**

## Traffic
- **AI persona sessions:** headless browsers driven by LLM personas with different goals and patience levels. They use the real UI, so every exposure and conversion is a real SDK event.
- **Real people:** the live URL shared with the community. Real sessions are reported separately.
- Persona traffic tests how the design and instrumentation behave. It is not proof of human preference, and the results will say so.

## Stopping
Stop on **Nov 29, 2026, around 10:00 IST**, or earlier only if the SRM check fails (then fix and restart). Flagsmith's Bayesian engine makes peeking safe, but the decision is made once, at the end.

## Amendments
- **2026-11-26 08:20 IST: experiment 521 started.** The hypothesis, metrics and decision rule are unchanged from this plan.
- **2026-11-26 08:21 IST: QA visits and a render fix.** Two QA identities (`assign_check_1` → sample_data, `assign_check_2` → control) each created one card to verify exposures and conversions end to end. Flagsmith recorded 1 exposure per arm and 0 excluded. One visit per arm keeps the test symmetric, and it is negligible against the planned traffic. The first QA visit exposed a bug: the page rendered the default (control) board for a moment before the server's assignment arrived. The app now waits for the server's assignment, with a 3-second fallback to control. Only that QA identity saw the bug, before any real traffic.
- **2026-11-26 08:53 IST: persona runner incidents.** (a) Three LLM persona sessions (`persona_llm_4e5e1ee0`, `persona_llm_51499236`, `persona_llm_df6186e6`) failed because the configured Gemini model had been retired. The app had already recorded an exposure for each (all `sample_data`), with no behaviour behind them. Flagsmith events can't be deleted, so they stay in the data: 3 extra non-converting `sample_data` identities, which biases slightly *against* the treatment. The runner now checks the LLM before opening any page and drops all events from a session that errors. (b) Three sessions (`persona_llm_2326afc3`, `persona_llm_e39072a0`, `persona_llm_4fefef86`) ran with the first persona prompt, under which every persona created a card. They are valid sessions but come from the uncalibrated prompt.
- **2026-11-26 08:57 IST: persona calibration (blind).** The prompt gained a per-session *intent* (browsing 55%, someday 30%, needs it now 15%), drawn independently of the variant, plus a reminder that leaving early is normal. It was tuned only on the **overall** first-card rate (target 25–45%, a realistic first-visit activation level), in a dry run with events blocked, without looking at the per-variant split. Result: 25% overall (3/12). The prompt is now frozen for the rest of the experiment.
