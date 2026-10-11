export type DbSubscription = {
  sub_id: string;
  user_id: string;
  plan_id: string;
  status:
    | 'pending'
    | 'active'
    | 'past_due'
    | 'expired'
    | 'cancelled';
  payment_provider: 'play_billing' | 'midtrans';
  current_period_start: string;
  current_period_end: string;
  grace_period_end: string | null;
  auto_renewing: boolean;
};

export type EntitlementStatus =
  | 'active'
  | 'past_due'
  | 'expired'
  | 'invalid';

export function deriveEntitlementStatus(
  sub: DbSubscription | null,
  nowMs = Date.now(),
): EntitlementStatus {
  if (!sub || !Number.isFinite(nowMs)) return 'invalid';
  if (sub.status === 'pending') return 'invalid';
  if (sub.status === 'expired') return 'expired';
  if (!['active', 'past_due', 'cancelled'].includes(sub.status)) return 'invalid';
  // A cancelled Midtrans order is not a paid, non-renewing Play subscription.
  if (sub.status === 'cancelled' && sub.payment_provider !== 'play_billing') return 'expired';
  const endMs = Date.parse(sub.current_period_end);
  const startMs = Date.parse(sub.current_period_start);
  const graceMs = sub.grace_period_end ? Date.parse(sub.grace_period_end) : endMs;
  if (![startMs, endMs, graceMs].every(Number.isFinite) || endMs < startMs || graceMs < endMs) return 'invalid';
  if (nowMs < startMs) return 'invalid';
  if (sub.payment_provider === 'play_billing') {
    if (nowMs >= endMs) return 'expired';
    return sub.status === 'past_due' ? 'past_due' : 'active';
  }
  if (sub.status === 'past_due') return nowMs < graceMs ? 'past_due' : 'expired';
  if (nowMs < endMs) return 'active';
  return nowMs < graceMs ? 'past_due' : 'expired';
}


// Capture one server instant for the entire selection and access decision.
export function chooseSubscription(
  rows: DbSubscription[],
  nowMs = Date.now(),
): DbSubscription | null {
  const priority = { active: 4, past_due: 3, expired: 2, invalid: 1 } as const;
  return [...rows].sort((a, b) => {
    const sa = deriveEntitlementStatus(a, nowMs);
    const sb = deriveEntitlementStatus(b, nowMs);
    const byStatus = priority[sb] - priority[sa];
    if (byStatus !== 0) return byStatus;
    return Date.parse(b.current_period_end) - Date.parse(a.current_period_end);
  })[0] ?? null;
}
