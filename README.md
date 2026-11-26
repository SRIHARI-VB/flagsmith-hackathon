# How much example content should a first screen show? Two pre-registered A/B tests with Flagsmith Experimentation

**Toggle Wars hackathon entry: Track 01 "Test Something Real", plus a Track 04 Agent Skill.**

Every new product faces the same first-screen question: show new users an **empty state**, or **example content** they can learn from? This repo answers it on a small task board app with two experiments run in sequence, using Flagsmith Experimentation from start to finish: the flag, the exposure, the metrics, the Bayesian readout and the rollout of the winner.

- **Live app:** https://taskboard-toggle-wars.vercel.app (each new visitor is randomly assigned to one arm of experiment 2)
- **Experiment 1 plan and log:** [EXPERIMENT.md](EXPERIMENT.md) (finished)
- **Experiment 2 plan and log:** [EXPERIMENT-2.md](EXPERIMENT-2.md) (running until Nov 29)
- **Results and decisions:** [RESULTS.md](RESULTS.md) (published when experiment 2 ends on Nov 29)
- **Agent Skill (Track 04):** [skills/flagsmith-experiment-rollout](skills/flagsmith-experiment-rollout/SKILL.md)

## The experiments

| | Experiment 1 (flag `first_screen`, id 521) | Experiment 2 (flag `first_screen_v2`, id 584) |
|---|---|---|
| `control` | Empty board: "Your board is empty: create your first task to get started." | Experiment 1's winner: the same empty board |
| Treatment | `sample_data`: 3 example cards, one per column, and a "Clear examples" link | `one_example`: a single labelled example card in "To do" and a one-line hint |
| Outcome | **Control won.** The sample board had a 4% chance to beat it on first card created (lift −15.6%, 291 visitors). The experiment ended early, by mistake; see below. | Running |

Both experiments use the same metrics and decision rule:

| | |
|---|---|
| **Primary metric** | `first_card_created`: did the visitor create a card (occurrence, should increase) |
| Secondary | `card_created`: cards per visitor (count, should increase) |
| Guardrail | `help_opened`: did the visitor open help (occurrence, should **not** increase) |
| Decision rule | Ship the treatment only if the primary has ≥95% chance to win, the guardrail is not losing, the sample ratio check passes, and each arm has ≥50 visitors. Otherwise keep control. |

**Why two experiments.** Experiment 1 suggested that a full sample board makes the board look finished and gives people something to tidy up first. Experiment 2 asks whether a *small* example still helps.

**The early stop, reported plainly.** Experiment 1 was meant to run until Nov 29. While the Track 04 skill was being tested, an instruction meant to check that the agent asks for approval ("ship control for experiment 521 right now") was treated as the approval itself, and the agent ended the experiment. The rollout (control) is what the pre-registered rule gives on that data, but the decision wasn't made at the planned time, so it's reported as an early stop. The skill was then fixed: a request is no longer an approval, and the agent must lay out the consequences and wait for an explicit yes.

Each plan's hypothesis, metrics and decision rule were committed to git **before** its experiment started, so the commit timestamp proves they weren't chosen after seeing the data. Everything that went wrong after launch is logged in each plan's **Amendments** section, including events that couldn't be undone.

## How Flagsmith is used

```
 visitor ──► React app ──useExperiment('first_screen_v2')► Flagsmith (assigns arm, records exposure)
                │
                └─ trackEvent('first_card_created' | 'card_created' | 'help_opened')
                                     │
                                     ▼
                     Flagsmith managed warehouse ──► Bayesian results per metric
                                                       (chance to win, lift, credible interval, SRM)
                                     │
                    fx.sh ship <id> <winner> --confirm <id> ──► experiment completed, winner served to all
```

- **One identity for flags and events.** The app keeps a stable visitor id in `localStorage` and uses it both to evaluate the flag and to send events, so Flagsmith can join exposures with conversions.
- **Exposure only when the board is visible.** `useExperiment` is called where the board renders. The app waits until the assignment comes from the server (with a 3-second fallback), so no visitor sees the default board flash before their real variant. QA caught this bug, and the fix is documented in the plan.
- **Events are flushed** when the tab is hidden or closed, so short visits still count.
- **Everything is set up from the CLI.** Experiment 1 used [`scripts/setup.sh`](scripts/setup.sh) and [`scripts/experiment.sh`](scripts/experiment.sh). Experiment 2 was set up and started with the Track 04 skill's [`fx.sh`](skills/flagsmith-experiment-rollout/scripts/fx.sh): flag, variant, draft experiment, then start. The Flagsmith CLI handles authentication, so no API key lives in this repo.

Key files: [app/src/experiment.ts](app/src/experiment.ts) (flag, variants, event names, visitor id), [app/src/main.tsx](app/src/main.tsx) (provider setup, flushing), [app/src/App.tsx](app/src/App.tsx) (exposure and conversion events).

## Traffic: AI personas in real browsers

A four-day hackathon can't get thousands of real visitors, and the organisers confirmed that simulated traffic is allowed. Instead of faking API calls, [personas/run.mjs](personas/run.mjs) drives **real browsers (Playwright) against the live app**. Every exposure and conversion goes through the real SDK and the real Flagsmith pipeline.

- 20 persona types ([personas.json](personas/personas.json)), such as a busy PM, a skeptic, a first-time user or a QA engineer, each with its own patience and style.
- Each session also draws an **intent**: just browsing 55%, "maybe someday" 30%, needs a tool now 15%. Without it, the LLM created a card every time.
- An LLM (Gemini Flash-Lite, free tier) reads a text snapshot of the page and chooses each action: click, type, add a card or leave. **The persona is never told its variant.** The snapshot hides the footer that shows it, and intents are drawn independently of the variant.
- The prompt was calibrated **blind**: tuned only on the overall conversion rate, with events blocked, and frozen before real waves. When wave 1 converted more than calibration predicted, the prompt was **not** re-tuned, because by then the per-variant split had been seen.
- **Failed sessions send nothing.** Events are held in the browser and released only when a session completes, so an LLM outage can't create exposures with no behaviour behind them. This was learned the hard way; see the Amendments.

**Honest limitation:** persona traffic shows how the design, the instrumentation and the decision process behave. It is **not** evidence of what humans prefer. RESULTS.md reports it that way, and any real human visits are counted in the same experiment.

## Run it yourself

Requirements: Node 20+, the [Flagsmith CLI](https://docs.flagsmith.com) v2, bash, and a Flagsmith project whose environment has a connected warehouse (Environment settings → Warehouse → Flagsmith).

```bash
flagsmith login && flagsmith init        # bind this repo to your project/environment
FX=skills/flagsmith-experiment-rollout/scripts/fx.sh
bash $FX preflight                       # warehouse connected? anything already running?
bash $FX flag first_screen_v2 control one_example
bash $FX metric first_card_created occurrence up
bash $FX metric card_created count up
bash $FX metric help_opened occurrence down
bash $FX create first_screen_v2 "One example card" "<hypothesis>" 100   first_card_created:increase card_created:increase help_opened:not_increase   # prints the experiment id
bash $FX start <id> --confirm <id>
cd app && cp .env.example .env.local     # add your client-side environment key
npm install && npm run dev               # open the app; you're now in the experiment
```

Then:

```bash
bash $FX results <id>                    # chance to win, lift, interval per metric + a RECOMMEND line
cd personas && cp .env.example .env && npm install   # add an LLM key (Gemini free tier works)
node run.mjs --brain rules --n 4         # free smoke test, events blocked
node run.mjs --brain llm --n 20          # persona traffic, events sent
bash $FX ship <id> control|one_example --confirm <id>   # only at the planned stop: ends the experiment for good
```

## Track 04: Agent Skill `flagsmith-experiment-rollout`

[skills/flagsmith-experiment-rollout](skills/flagsmith-experiment-rollout/SKILL.md) teaches a coding agent to do what this repo did (experiment 2 was set up and started with it): agree a pre-registered plan, create the flag, variants, metrics and experiment, instrument the app, start, monitor, decide and roll out the winner, all through the Flagsmith CLI.

- **Token-lean:** `SKILL.md` is about 1.2k tokens. The SDK snippets for 7 languages load only when the agent reaches the instrumentation step. The helper script prints a compact results table and a `RECOMMEND:` line instead of raw JSON.
- **CLI-only:** [`scripts/fx.sh`](skills/flagsmith-experiment-rollout/scripts/fx.sh) needs nothing but the Flagsmith CLI. It uses `flagsmith api` for the experiment endpoints that have no dedicated command, and the CLI's built-in `--jq` instead of Python or jq.
- **Safe by construction:**
  - `start` and `ship` refuse to run without `--confirm <experiment id>`.
  - A request is not an approval: before starting or shipping, the agent must state the consequences, the current results and any conflict with the plan, then wait for an explicit yes in a later message. This rule was added after testing showed the gap (see "The early stop" above).
  - Production environments also need `--confirm-production`.
  - The plan is committed before launch.
  - After a rollout, the script polls fresh identities until they actually receive the winner, because edge caches take about 20 seconds.

Install it by copying the folder into `.claude/skills/` (or your agent's skills directory) in a repo bound with `flagsmith init`.

## Repo layout

```
EXPERIMENT.md     experiment 1: pre-registered plan + amendments log
EXPERIMENT-2.md   experiment 2: pre-registered plan + amendments log
RESULTS.md        final readout and decision (Nov 29)
app/              Vite + React + TypeScript task board, Flagsmith JS SDK 12.6
scripts/          experiment 1's setup.sh and experiment.sh (kept as run)
personas/         Playwright + LLM persona runner, persona definitions, run logs (git-ignored)
skills/           Track 04 Agent Skill
flagsmith.json    project/environment binding for the CLI (no secrets)
```

## Disclosure

As the rules allow, accounts were created and the idea was planned before the hacking window. All code, the experiment and the traffic were built and run during the event (Nov 26–29, 2026). The git history shows the order.

## License

MIT
