# Empty board or sample board? A pre-registered A/B test with Flagsmith Experimentation

**Toggle Wars hackathon entry: Track 01 "Test Something Real", plus a Track 04 Agent Skill.**

Every new product has the same question on its first screen: show new users an **empty state**, or a **pre-filled example** they can learn from? This repo runs that experiment for real on a small task board app, using Flagsmith Experimentation from start to finish: the flag, the exposure, the metrics, the Bayesian readout and the rollout of the winner.

- **Live app:** https://taskboard-toggle-wars.vercel.app (each visitor is randomly assigned to one arm)
- **Plan, written before any data was collected:** [EXPERIMENT.md](EXPERIMENT.md)
- **Results and the decision:** [RESULTS.md](RESULTS.md) (published when the experiment ends on Nov 29)
- **Agent Skill (Track 04):** [skills/flagsmith-experiment-rollout](skills/flagsmith-experiment-rollout/SKILL.md)

## The experiment

| | |
|---|---|
| Flag | `first_screen` (multivariate), 50/50 split, 100% rollout |
| `control` | Empty board: "Your board is empty: create your first task to get started." |
| `sample_data` | The same board with 3 example cards and a "make it yours" hint with a "Clear examples" link |
| **Primary metric** | `first_card_created`: did the visitor create a card (occurrence, should increase) |
| Secondary | `card_created`: cards per visitor (count, should increase) |
| Guardrail | `help_opened`: did the visitor open help (occurrence, should **not** increase) |
| Decision rule | Ship `sample_data` only if the primary has ≥95% chance to win, the guardrail is not losing, the sample ratio check passes, and each arm has ≥50 visitors. Otherwise keep control. |

The hypothesis, metrics and decision rule were committed to git **before** the experiment started, so the commit timestamp proves they weren't chosen after seeing the data. Everything that went wrong after launch is logged in the plan's **Amendments** section, including events that couldn't be undone.

## How Flagsmith is used

```
 visitor ──► React app ──useExperiment('first_screen')──► Flagsmith (assigns arm, records exposure)
                │
                └─ trackEvent('first_card_created' | 'card_created' | 'help_opened')
                                     │
                                     ▼
                     Flagsmith managed warehouse ──► Bayesian results per metric
                                                       (chance to win, lift, credible interval, SRM)
                                     │
                    scripts/experiment.sh ship <winner> ──► experiment completed, winner served to all
```

- **One identity for flags and events.** The app keeps a stable visitor id in `localStorage` and uses it both to evaluate the flag and to send events, so Flagsmith can join exposures with conversions.
- **Exposure only when the board is visible.** `useExperiment` is called where the board renders. The app waits until the assignment comes from the server (with a 3-second fallback), so no visitor sees the default board flash before their real variant. QA caught this bug, and the fix is documented in the plan.
- **Events are flushed** when the tab is hidden or closed, so short visits still count.
- **Everything is set up from the CLI.** `scripts/setup.sh` creates the flag, the keyed variant and the three metrics. `scripts/experiment.sh` creates, starts and monitors the experiment and ships the winner. The Flagsmith CLI handles authentication, so no API key lives in this repo.

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
flagsmith login && flagsmith init                    # bind this repo to your project/environment
bash scripts/setup.sh                                # flag + sample_data variant + 3 metrics (idempotent)
bash scripts/experiment.sh create && bash scripts/experiment.sh start
cd app && cp .env.example .env.local                 # add your client-side environment key
npm install && npm run dev                           # open the app; you're now in the experiment
```

Then:

```bash
bash scripts/experiment.sh results                   # chance to win, lift and interval per metric
cd personas && cp .env.example .env && npm install   # add an LLM key (Gemini free tier works)
node run.mjs --brain rules --n 4                     # free smoke test, events blocked
node run.mjs --brain llm --n 20                      # persona traffic, events sent
bash scripts/experiment.sh ship control|sample_data  # end the experiment and serve the winner (asks you to confirm)
```

## Track 04: Agent Skill `flagsmith-experiment-rollout`

[skills/flagsmith-experiment-rollout](skills/flagsmith-experiment-rollout/SKILL.md) teaches a coding agent to do what this repo did: agree a pre-registered plan, create the flag, variants, metrics and experiment, instrument the app, start, monitor, decide and roll out the winner, all through the Flagsmith CLI.

- **Token-lean:** `SKILL.md` is about 1.2k tokens. The SDK snippets for 7 languages load only when the agent reaches the instrumentation step. The helper script prints a compact results table and a `RECOMMEND:` line instead of raw JSON.
- **CLI-only:** [`scripts/fx.sh`](skills/flagsmith-experiment-rollout/scripts/fx.sh) needs nothing but the Flagsmith CLI. It uses `flagsmith api` for the experiment endpoints that have no dedicated command, and the CLI's built-in `--jq` instead of Python or jq.
- **Safe by construction:**
  - `start` and `ship` refuse to run without `--confirm <experiment id>`, which the agent may pass only after a human approves.
  - Production environments also need `--confirm-production`.
  - The plan is committed before launch.
  - After a rollout, the script polls fresh identities until they actually receive the winner, because edge caches take about 20 seconds.

Install it by copying the folder into `.claude/skills/` (or your agent's skills directory) in a repo bound with `flagsmith init`.

## Repo layout

```
EXPERIMENT.md     pre-registered plan + amendments log
RESULTS.md        final readout and decision (Nov 29)
app/              Vite + React + TypeScript task board, Flagsmith JS SDK 12.6
scripts/          setup.sh (flag, variant, metrics) and experiment.sh (create/start/status/results/ship)
personas/         Playwright + LLM persona runner, persona definitions, run logs (git-ignored)
skills/           Track 04 Agent Skill
flagsmith.json    project/environment binding for the CLI (no secrets)
```

## Disclosure

As the rules allow, accounts were created and the idea was planned before the hacking window. All code, the experiment and the traffic were built and run during the event (Nov 26–29, 2026). The git history shows the order.

## License

MIT
