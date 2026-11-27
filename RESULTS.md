# Results

> All traffic is AI personas in real browsers, plus a handful of real visitors. These results show how the designs, the instrumentation and the decision process behave. They are **not** evidence of what humans prefer.
> Flagsmith numbers come from its experiment results. "Logs" numbers come from the persona runner's per-session records (`personas/runs/`, not committed), which include each persona's actions and its stated reason for each one. The log analysis covers the 264 sessions from waves 1–3. It leaves out failed sessions, the 7 quota-junk sessions and the 3 sessions from before calibration.

## Experiment 1: empty board vs. a board with 3 sample cards

**The sample board made new visitors less likely to create their first card: 50% vs 59%.** Flagsmith gives it a **4% chance** of being better (lift −15.6%, 95% interval −33% to +2%), which is in Flagsmith's "Losing" band. **Control (the empty board) was rolled out.** The experiment ended early, by mistake (see [EXPERIMENT.md](EXPERIMENT.md)), but the rollout is what the pre-registered rule gives on this data.

| Metric | Control | Sample board | Verdict |
|---|---|---|---|
| **First card created** (primary) | 80 / 135 (59%) | 78 / 156 (50%) | 4% chance to win: **Losing** |
| Help opened (guardrail) | 26% | 21% | 86% chance that sample is better: **guardrail OK** |
| Cards created (secondary) | 1.18 per visitor (logs) | 1.07 per visitor (logs) | **Not reported from Flagsmith: the data contains duplicates** (see finding 7) |

### What the data says: each claim checked

**1. The loss came from undecided visitors, not from people with a need.**
| Visitor intent | Control | Sample board |
|---|---|---|
| Just browsing | 44% | **32%** |
| "Maybe someday" | 80% | **67%** |
| Needs a tool now | 100% | 95% |

Visitors who needed a task board created a card either way. The sample board lost its ground among visitors who were still deciding.

**2. The sample board didn't make people leave at first sight.** Visitors who left without doing anything: 30% control vs 32% sample. The difference appears *after* the first look.

**3. My first explanation, "people leave because the sample board looks finished", is mostly not supported.** In their own words:
- **Got the idea without trying:** 12 of 64 sample-board leavers said, in effect, that the examples had already shown them what the product does. Examples: *"I've seen the example tasks, I think I get the idea now."* *"I've seen how cards move around. Looks clean enough, time to go."*
- **Too cluttered:** only 4 of 64 said this.
- **Control leavers** mostly blamed emptiness: 35 of 48 said "empty", "blank" or "boring".

The better explanation: **examples answer "what is this?" so well that trying it yourself becomes optional.**

**4. My second explanation, "tidying up the examples is a chore", is not supported.** 17% of sample-board visitors deleted or cleared examples before typing anything, and they created a card **more** often than the rest (70% vs 49%). Tidying up was a sign of engagement, not friction.

**5. The sample board slowed the start down.** Among visitors who created a card, sample-board visitors took more actions before typing: 0.78 vs 0.20 on average. 15 of 72 took two or more actions first, against 0 of 79 on the empty board.

**6. Once people started, both boards got the same depth of use:** 1.9 cards (control) vs 2.0 (sample) per visitor who created one. The whole difference is in *whether* people start.

**7. Measurement problem: duplicate events in wave 3.** The runner held event requests open past the SDK's 3-second timeout, so the SDK retried, and each retry reached Flagsmith.
- **Waves 1–2:** cards typed equal events sent (165 = 165).
- **Wave 3:** 132 cards typed, about 440 events sent.
- **Effect:** Flagsmith's `card_created` totals (299 / 259) are about 2× the real values. The occurrence metrics (first card, help) can't be affected by duplicates, and their counts match the logs.
- **Lesson:** a count metric needs an idempotent pipeline; a yes/no metric is robust to retries.
- **Status:** found in a post-hoc audit and fixed before experiment 2's traffic.

### Checked and ruled out
- **Step limit:** each session has at most 6 actions. Sessions that ran out of steps were 0 (control) vs 1 (sample), so the limit didn't penalise the slower-starting board.
- **Unreadable AI replies counted as "leave":** 1 (control) vs 2 (sample), all in wave 1. Too few to matter, and such replies now fail the session.
- **"A friend sent me this":** 38 persona thoughts mention a friend. That isn't invented; the "browsing" intent in our prompt says so. Personas echo their prompt, which is worth knowing when reading their reasons.
- **Hostile input:** QA personas typed `<script>alert(1)</script>` or `'; DROP TABLE tasks; --` 11 times. No session errored, and React renders card titles as plain text.

## Experiment 2: empty board vs. one example card

Running until Nov 29, about 10:00 IST. The plan is in [EXPERIMENT-2.md](EXPERIMENT-2.md). Results are added here after the decision.
