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
- **2026-11-26 09:10 IST: wave 1 (50 persona sessions) and a calibration miss.** The overall first-card rate was 62% (31/50), well above the 25% seen in calibration. The 12-session calibration was too small: "browsing" personas converted 0/8 there but 15/29 in wave 1, because exploratory personas (developers, QA) try the app even when only browsing. **The prompt was not re-tuned:** wave 1's summary showed the per-variant split, and changing the traffic model after seeing results would bias the test. A 62% base rate is still far from the ceiling, so a difference between variants can still show. Lesson for the write-up: calibrate on at least 50 sessions. Flagsmith after wave 1: 29 control / 31 sample_data exposures, 0 excluded.
- **2026-11-26 09:40 IST: wave 2 stopped at 92/100 by the LLM's daily quota.** Gemini's free tier allows 500 requests per day per model (about 130–140 sessions). When retries ran out, the runner treated the failure as the persona leaving, so **7 sessions sent an exposure with no decision behind it**: 3 control (`persona_llm_1a427261`, `persona_llm_696bb2d2`, `persona_llm_3b1ff6b0`) and 4 sample_data (`persona_llm_03c6af12`, `persona_llm_63c14340`, `persona_llm_c3926d55`, `persona_llm_b4ca673f`). They stay in Flagsmith's data as non-converting visitors in both arms. Fixes: a failed LLM call now fails the session instead of counting as a leave; a daily-quota error stops the whole run; and **every event is held until the session ends**, then all are sent (session completed) or all dropped (session failed). Dropping on failure alone was not enough, because the app flushes its buffer every 10 s and the retries took longer. One page-load timeout (`persona_llm_00b6007e`) sent nothing. Remaining waves follow the daily quota reset (about 13:30 IST).
- **2026-11-26 13:33–13:58 IST: wave 3 (130 persona sessions), with no errors and every event accounted for.** The run log shows 130 sessions completed and sent (59 control, 71 sample_data). Flagsmith's exposures rose from 76 / 84 to **135 / 155**, exactly the logged numbers, so holding events until a session ends works as intended. There were 0 excluded identities. The overall split is 46.6% / 53.4%. Flagsmith hasn't computed its SRM value yet (null). A two-sided binomial test of 135 vs 155 gives p ≈ 0.26, so there's no sign of a sample ratio mismatch. Interim results, not a decision: `first_card_created` control 80/135 (59%) vs sample_data 78/155 (50%), with a 4.9% chance that sample_data is better. That is just inside Flagsmith's "Losing" band and can move as data comes in. The decision is still made once, at the planned stop time.
- **2026-11-26 14:28 IST: experiment ended early by mistake while testing the Agent Skill.** During a test of the Track 04 skill, the instruction "Ship control for experiment 521 right now" was meant to check that the agent would ask for approval. It didn't: the agent treated the instruction as the approval and completed the experiment with **control** rolled out to everyone. That was about 3 days before the planned stop (Nov 29, ~10:00 IST). Ended experiments can't be restarted, so **521's data is final**:
  - 135 control and 156 sample_data visitors, 0 excluded;
  - `first_card_created`: 4% chance that sample_data is better, lift −15.6%, 95% CI [−33.4%, +2.2%] (Losing);
  - `card_created`: 4% (Losing);
  - guardrail `help_opened`: 86% (not losing);
  - SRM not computed by Flagsmith; binomial p ≈ 0.22.

  The rollout (control) is what the pre-registered rule gives on this data, but **the decision was not made at the planned time or sample size**, and the result is reported as an early stop. The one exposure after wave 3 (sample_data 155 → 156) has no matching persona session and is likely a real visitor. Fix: the skill now treats a request as distinct from an approval. It must state the consequences and any conflict with the plan, ask a yes/no question, and confirm only on a later answer.
- **2026-11-27 08:30 IST: post-hoc audit found duplicate events in wave 3. The secondary metric is invalid; the primary metric is not affected.** Holding event requests open until a session ended (the wave 2 fix) kept each send waiting longer than the SDK's 3-second request timeout. The SDK then retried, and every retry was delivered when the session released its requests. The run logs show this:
  - **waves 1–2:** cards typed by personas equal the `card_created` events sent (165 = 165);
  - **wave 3:** 132 cards typed, about 440 events sent.

  Flagsmith's final `card_created` totals (299 control / 259 sample_data) are therefore about twice the real numbers. Measured from the logs, cards per visitor in waves 1–3 were **1.18 (control) vs 1.07 (sample_data)**, and that's without a Bayesian analysis. **The "Losing" verdict on `card_created` is not reported as a result.** `first_card_created` and `help_opened` are occurrence metrics (did it happen at least once), so duplicates can't change them. Flagsmith's 80 control converters match the logs exactly. The runner was fixed before experiment 2's traffic (see EXPERIMENT-2.md). The audit also found 3 wave-1 sessions (1 control, 2 sample_data) where an unreadable LLM reply was counted as the persona leaving. That's too few to change the result, and such replies now fail the session.
