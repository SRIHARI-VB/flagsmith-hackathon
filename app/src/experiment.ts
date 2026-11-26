// Single source of truth for the experiment's names. The setup scripts and the
// persona runner use the same strings: event names are case-sensitive, and an
// event that doesn't match a metric is silently dropped by Flagsmith.

export const FLAG = 'first_screen' as const;

export const VARIANTS = {
  control: 'control', // empty board + "Create your first task" call to action
  sampleData: 'sample_data', // board pre-filled with example cards
} as const;

export type Variant = (typeof VARIANTS)[keyof typeof VARIANTS];

export const EVENTS = {
  firstCardCreated: 'first_card_created', // primary: Occurrence, up
  cardCreated: 'card_created', // secondary: Count, up
  helpOpened: 'help_opened', // guardrail: Occurrence, should not increase
} as const;

const VISITOR_KEY = 'ft_visitor_id';

/**
 * A stable id per browser, so the same visitor always lands in the same bucket.
 * The persona runner passes `?uid=persona_<uuid>` to start a fresh identity.
 */
export function getVisitorId(): string {
  const fromUrl = new URLSearchParams(location.search).get('uid');
  if (fromUrl) {
    localStorage.setItem(VISITOR_KEY, fromUrl);
    return fromUrl;
  }
  let id = localStorage.getItem(VISITOR_KEY);
  if (!id) {
    id = `visitor_${crypto.randomUUID()}`;
    localStorage.setItem(VISITOR_KEY, id);
  }
  return id;
}

export function toVariant(value: unknown): Variant {
  return value === VARIANTS.sampleData ? VARIANTS.sampleData : VARIANTS.control;
}
