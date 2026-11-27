// Persona traffic runner.
//
// Each session is a fresh browser with a new identity (persona_<brain>_<id>).
// A "brain" looks at a text snapshot of the page and picks the next action.
// The app itself fires the real Flagsmith SDK events (exposure + conversions).
//
//   node run.mjs --brain rules --n 4            # free smoke test, events BLOCKED
//   node run.mjs --brain llm --n 20             # LLM personas, events SENT
//
// Options: --url <app url>  --concurrency <k>  --max-steps <m>  --send-events (rules only)  --print-snapshots
//          --dry  (llm: block events, for calibration runs that must not touch the experiment)
// LLM config (personas/.env): LLM_API_KEY, LLM_BASE_URL, LLM_MODEL. Any
// OpenAI-compatible chat completions endpoint works (Gemini, Groq, OpenRouter...).
//
// The brain never sees which variant it is in: the snapshot excludes the
// footer (visitor id / variant) and anything outside the app's main UI.

import { chromium } from 'playwright';
import { readFileSync, mkdirSync, appendFileSync, existsSync } from 'node:fs';
import { randomUUID } from 'node:crypto';

// ---------- config ----------
const args = Object.fromEntries(
  process.argv.slice(2).reduce((acc, a, i, all) => {
    if (a.startsWith('--')) acc.push([a.slice(2), all[i + 1]?.startsWith('--') || all[i + 1] === undefined ? 'true' : all[i + 1]]);
    return acc;
  }, []),
);
loadEnv(new URL('./.env', import.meta.url));

const BRAIN = args.brain ?? 'rules';
const N = Number(args.n ?? 4);
const URL_ = args.url ?? 'https://taskboard-toggle-wars.vercel.app';
const CONCURRENCY = Number(args.concurrency ?? 2);
const MAX_STEPS = Number(args['max-steps'] ?? 6);
// Smoke runs must never pollute the experiment; LLM runs are the real traffic,
// unless --dry (used for calibration).
const DRY = args.dry === 'true';
const SEND_EVENTS = !DRY && (BRAIN === 'llm' || args['send-events'] === 'true');

// How much the visitor cares today. Drawn per session, independent of the
// variant, so it sets the overall conversion level without favouring a version.
const INTENTS = [
  { id: 'browsing', weight: 55, text: "You have no real task in mind. You're only glancing because a friend asked. Leave once you've formed an impression, unless something genuinely makes you want to try it." },
  { id: 'someday', weight: 30, text: 'You might use a tool like this someday, but nothing is urgent. You will try it only if it is quick and clear.' },
  { id: 'needs_it', weight: 15, text: 'You have something to organise right now and are looking for a simple tool.' },
];
function pickIntent() {
  let r = Math.random() * INTENTS.reduce((s, i) => s + i.weight, 0);
  return INTENTS.find((i) => (r -= i.weight) < 0) ?? INTENTS[0];
}

const LLM = {
  key: process.env.LLM_API_KEY,
  base: (process.env.LLM_BASE_URL ?? 'https://generativelanguage.googleapis.com/v1beta/openai').replace(/\/$/, ''),
  model: process.env.LLM_MODEL ?? 'gemini-3.5-flash-lite',
};
if (BRAIN === 'llm' && !LLM.key) {
  console.error('LLM_API_KEY missing: add it to personas/.env (see .env.example)');
  process.exit(1);
}

const PERSONAS = JSON.parse(readFileSync(new URL('./personas.json', import.meta.url), 'utf8'));
const RUN_ID = new Date().toISOString().replace(/[:.]/g, '-');
mkdirSync(new URL('./runs/', import.meta.url), { recursive: true });
const LOG = new URL(`./runs/${RUN_ID}-${BRAIN}.jsonl`, import.meta.url);

// ---------- page snapshot (what the persona "sees") ----------
// Numbered list of visible, meaningful elements inside the app, excluding the
// footer and banner so the variant name and visitor id never leak.
async function snapshot(page) {
  return page.evaluate(() => {
    const root = document.querySelector('.page');
    const skip = (el) => el.closest('footer, .banner');
    const visible = (el) => {
      const r = el.getBoundingClientRect();
      return r.width > 0 && r.height > 0 && getComputedStyle(el).visibility !== 'hidden';
    };
    let ref = 0;
    const lines = [];
    root.querySelectorAll('[data-ref]').forEach((el) => el.removeAttribute('data-ref'));
    for (const el of root.querySelectorAll('h1, h2, p, section.hint, article, input, button')) {
      if (skip(el) || !visible(el)) continue;
      if (el.matches('section.hint')) { lines.push(`[note] ${el.childNodes[0]?.textContent?.trim() ?? ''} ${el.querySelector('b')?.nextSibling?.textContent?.trim() ?? ''}`.trim()); continue; }
      if (el.matches('article')) { lines.push(`  [card] "${el.querySelector('span')?.textContent}"${el.querySelector('.tag') ? ' (example)' : ''}`); continue; }
      if (!el.matches('button, input') && el.closest('article, section.hint')) continue; // already described
      if (el.matches('input')) {
        el.setAttribute('data-ref', String(++ref));
        lines.push(`#${ref} [text box] placeholder="${el.placeholder}" value="${el.value}"`);
      } else if (el.matches('button')) {
        el.setAttribute('data-ref', String(++ref));
        const text = el.textContent.trim();
        const label = text.length <= 2 && el.title ? `${text} (${el.title})` : text || el.title; // e.g. "✕ (Delete)"
        lines.push(`${el.closest('article') ? '    ' : ''}#${ref} [button] ${label}${el.disabled ? ' (disabled)' : ''}`);
      } else {
        lines.push(`[${el.tagName.toLowerCase()}] ${el.textContent.trim()}`);
      }
    }
    return lines.join('\n');
  });
}

// ---------- brains ----------
// rules: variant-blind random behaviour. Only for testing the pipeline.
function rulesBrain(_persona, snap, step) {
  const refs = [...snap.matchAll(/^#(\d+) \[(text box|button)\] (.*)$/gm)];
  const box = refs.find((r) => r[2] === 'text box');
  const roll = Math.random();
  if (roll < 0.25 || step >= 4) return { action: 'leave', thought: 'random leave' };
  if (roll < 0.6 && box) return { action: 'type', ref: Number(box[1]), text: 'Smoke test task', thought: 'random type' };
  const buttons = refs.filter((r) => r[2] === 'button' && !r[3].includes('(disabled)'));
  const b = buttons[Math.floor(Math.random() * buttons.length)];
  return b ? { action: 'click', ref: Number(b[1]), thought: 'random click' } : { action: 'leave' };
}

const SYSTEM = `You role-play a real person visiting a web app for the first time. A friend sent you a link saying "try this task board". Stay in character: your intent, patience and habits decide what you do. Be realistic: most first-time visitors leave within seconds without doing anything, and leaving is always a fine choice. Never do something just because it is possible.
Reply with ONLY a JSON object: {"thought": "<max 15 words>", "action": "click"|"type"|"leave", "ref": <number for click/type>, "text": "<what you type, for type>"}
"type" enters text into a text box and presses Enter.`;

async function llmBrain(persona, snap, step, history, intent = INTENTS[0]) {
  const user = `You are ${persona.who}. Patience: ${persona.patience}. Habits: ${persona.style}.
Today: ${intent.text}
Step ${step + 1} of at most ${MAX_STEPS}.${history.length ? `\nSo far you: ${history.join('; ')}.` : ''}
The page shows:
${snap}`;
  const body = {
    model: LLM.model,
    temperature: 1,
    max_tokens: 120,
    response_format: { type: 'json_object' },
    messages: [{ role: 'system', content: SYSTEM }, { role: 'user', content: user }],
  };
  for (let attempt = 0; attempt < 6; attempt++) {
    const res = await fetch(`${LLM.base}/chat/completions`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', authorization: `Bearer ${LLM.key}` },
      body: JSON.stringify(body),
    });
    if (res.status === 429 || res.status >= 500) {
      const detail = await res.text();
      if (/per[ -]?day|PerDay|daily/i.test(detail)) {
        // Daily quota: retrying won't help. Fail this session and stop the run.
        throw Object.assign(new Error('LLM daily quota exhausted'), { quota: true });
      }
      const wait = Number(res.headers.get('retry-after')) * 1000 || 2000 * 2 ** attempt;
      await sleep(Math.min(wait, 60000));
      continue;
    }
    if (!res.ok) throw new Error(`LLM ${res.status}: ${(await res.text()).slice(0, 200)}`);
    const data = await res.json();
    const text = data.choices?.[0]?.message?.content ?? '';
    const usage = data.usage ?? {};
    try {
      return { ...JSON.parse(text.slice(text.indexOf('{'), text.lastIndexOf('}') + 1)), usage };
    } catch {
      // Not a decision: fail the session (events dropped) rather than log a "leave".
      throw new Error(`unparseable LLM reply: ${text.slice(0, 60)}`);
    }
  }
  // Never turn a failed call into a "leave": that would record a visitor who
  // made no decision. Fail the session instead (its events are dropped).
  throw new Error('LLM rate limited, gave up after retries');
}

// ---------- one session ----------
async function session(browser, n) {
  const persona = PERSONAS[Math.floor(Math.random() * PERSONAS.length)];
  const intent = pickIntent();
  const uid = `persona_${BRAIN}_${randomUUID().slice(0, 8)}`;
  const ctx = await browser.newContext({ viewport: { width: 1200, height: 800 } });
  const page = await ctx.newPage();
  const events = [];
  // Event requests are answered at once with a fake "accepted" and KEPT. When
  // the session ends they are sent to Flagsmith once each (session completed)
  // or dropped (session failed). Sending as they come would leak the exposure
  // of a session that later fails. Holding the real request open instead (the
  // wave 3 approach) made the SDK time out after 3 s and retry, and every
  // retry was delivered: count metrics got duplicates.
  let failed = false;
  const held = []; // { url, headers, body }
  const CORS = { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': 'POST, OPTIONS' };
  await page.route('**/events.api.flagsmith.com/**', async (route) => {
    const req = route.request();
    if (req.method() === 'OPTIONS') return route.fulfill({ status: 204, headers: CORS });
    const body = req.postData() ?? '{}';
    for (const e of JSON.parse(body).events ?? [])
      events.push(e.event === '$flag_exposure' ? `exposure:${e.value}` : e.event);
    held.push({ url: req.url(), headers: await req.allHeaders(), body });
    return route.fulfill({ status: 202, headers: { ...CORS, 'content-type': 'application/json' }, body: '{}' });
  });

  const log = { run: RUN_ID, n, uid, persona: persona.id, intent: intent.id, brain: BRAIN, model: BRAIN === 'llm' ? LLM.model : null, sent: SEND_EVENTS, steps: [], tokens: 0 };
  const history = [];
  try {
    await page.goto(`${URL_}/?uid=${uid}`, { waitUntil: 'domcontentloaded' });
    await page.waitForFunction(() => document.querySelector('.page')?.dataset.variant !== 'loading', null, { timeout: 15000 });
    log.variant = await page.getAttribute('.page', 'data-variant'); // for our logs only, never shown to the brain
    await sleep(800 + Math.random() * 1500); // a moment to "look"

    for (let step = 0; step < MAX_STEPS; step++) {
      const snap = await snapshot(page);
      if (args['print-snapshots']) console.log(`--- ${uid} step ${step + 1} sees:\n${snap}\n`);
      const d = BRAIN === 'llm' ? await llmBrain(persona, snap, step, history, intent) : rulesBrain(persona, snap, step);
      log.tokens += (d.usage?.prompt_tokens ?? 0) + (d.usage?.completion_tokens ?? 0);
      log.steps.push({ action: d.action, ref: d.ref, text: d.text, thought: d.thought });
      if (d.action === 'leave' || !d.action) break;
      const el = page.locator(`[data-ref="${d.ref}"]`);
      if (!(await el.count())) { history.push(`tried something that wasn't there`); continue; }
      if (d.action === 'type') {
        await el.fill(String(d.text ?? '').slice(0, 80));
        await el.press('Enter');
        history.push(`typed "${d.text}"`);
      } else {
        const label = (await el.textContent())?.trim() || (await el.getAttribute('title')) || 'a button';
        await el.click({ timeout: 3000 }).catch(() => {});
        history.push(`clicked "${label}"`);
      }
      await sleep(600 + Math.random() * 1200);
    }
  } catch (err) {
    log.error = String(err.message ?? err).slice(0, 200);
    failed = true;
    if (err.quota) STOP = true;
  } finally {
    // Leaving the page: the app flushes its event buffer on pagehide.
    await page.evaluate(() => dispatchEvent(new Event('pagehide'))).catch(() => {});
    await sleep(2500);
    const send = SEND_EVENTS && !failed;
    let delivered = 0;
    if (send) {
      for (const h of held) {
        const headers = Object.fromEntries(Object.entries(h.headers).filter(([k]) => !k.startsWith(':') && !['host', 'content-length', 'connection'].includes(k)));
        const res = await fetch(h.url, { method: 'POST', headers, body: h.body }).catch((e) => ({ ok: false, status: String(e) }));
        if (res.ok) delivered++;
        else log.deliveryError = `events API ${res.status}`;
      }
    }
    log.sent = send && held.length > 0 && delivered === held.length;
    log.requests = { kept: held.length, delivered };
    log.events = events;
    appendFileSync(LOG, JSON.stringify(log) + '\n');
    await ctx.close();
    const converted = events.includes('first_card_created') ? '✓ card' : '· no card';
    console.log(`${String(n).padStart(3)} ${uid} ${persona.id.padEnd(16)} ${intent.id.padEnd(8)} ${String(log.variant).padEnd(11)} ${converted.padEnd(9)} steps=${log.steps.length} tokens=${log.tokens}${log.error ? ' ERROR ' + log.error : ''}`);
  }
  return log;
}

// ---------- main ----------
// Preflight: make sure the brain answers before any page (and exposure) exists.
if (BRAIN === 'llm') {
  try {
    await llmBrain({ who: 'a tester', patience: 'high', style: 'n/a' }, '#1 [button] OK', 0, []);
  } catch (err) {
    console.error(`LLM preflight failed, nothing was run: ${err.message}`);
    process.exit(1);
  }
}
const browser = await chromium.launch({ channel: 'msedge' });
console.log(`run ${RUN_ID}: ${N} sessions, brain=${BRAIN}${BRAIN === 'llm' ? ` (${LLM.model})` : ''}, events ${SEND_EVENTS ? 'SENT to Flagsmith' : DRY ? 'BLOCKED (dry run)' : 'BLOCKED'}, url=${URL_}`);
let next = 0;
let STOP = false; // set when the LLM's daily quota runs out
const results = [];
await Promise.all(
  Array.from({ length: CONCURRENCY }, async () => {
    while (next < N && !STOP) results.push(await session(browser, ++next));
  }),
);
if (STOP) console.log('Stopped early: LLM daily quota exhausted. Failed sessions sent nothing.');
await browser.close();

const by = (v) => results.filter((r) => r.variant === v);
for (const v of [...new Set(results.map((r) => r.variant).filter(Boolean))].sort()) {
  const rs = by(v);
  const conv = rs.filter((r) => r.events?.includes('first_card_created')).length;
  console.log(`${v.padEnd(11)} sessions=${rs.length} first_card=${conv} (${rs.length ? Math.round((100 * conv) / rs.length) : 0}%)`);
}
const tokens = results.reduce((s, r) => s + r.tokens, 0);
console.log(`errors=${results.filter((r) => r.error).length} tokens=${tokens} (avg ${Math.round(tokens / Math.max(1, results.length))}/session) log=${LOG.pathname}`);

// ---------- helpers ----------
function sleep(ms) { return new Promise((r) => setTimeout(r, ms)); }
function loadEnv(url) {
  if (!existsSync(url)) return;
  for (const line of readFileSync(url, 'utf8').split(/\r?\n/)) {
    const m = line.match(/^\s*([A-Z_]+)\s*=\s*(.*)\s*$/);
    if (m && !process.env[m[1]]) process.env[m[1]] = m[2].replace(/^["']|["']$/g, '');
  }
}
