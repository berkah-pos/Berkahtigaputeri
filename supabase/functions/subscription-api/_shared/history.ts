// Read-only display projection. Never use this response to grant access.
export type HistoryRow = {
  sub_id: string;
  plan_id: string;
  status: string;
  payment_provider: string;
  midtrans_order_id: string | null;
  play_order_id: string | null;
  current_period_start: string;
  current_period_end: string;
  paid_at: string | null;
  created_at: string;
};

export function historyEntry(row: HistoryRow, now: number) {
  const start = Date.parse(row.current_period_start);
  const end = Date.parse(row.current_period_end);
  const confirmed = row.payment_provider === 'midtrans'
    ? row.paid_at !== null
    : ['active', 'past_due', 'cancelled'].includes(row.status);
  const usable = confirmed && ['active', 'past_due', 'cancelled'].includes(row.status)
    && (row.payment_provider !== 'midtrans' || row.status !== 'cancelled');
  let periodState = 'inactive';
  if (row.status === 'pending') periodState = 'pending';
  else if (usable && Number.isFinite(start) && Number.isFinite(end) && end > start) {
    periodState = now < start ? 'upcoming' : now < end ? 'current' : 'ended';
  }
  return {
    id: row.sub_id,
    plan_id: row.plan_id,
    status: row.status,
    provider: row.payment_provider,
    order_id: row.payment_provider === 'midtrans' ? row.midtrans_order_id : row.play_order_id,
    period_state: periodState,
    // Pending dates are provisional and must not look like purchased coverage.
    period_start: confirmed ? row.current_period_start : null,
    period_end: confirmed ? row.current_period_end : null,
    paid_at: row.paid_at,
    created_at: row.created_at,
  };
}
