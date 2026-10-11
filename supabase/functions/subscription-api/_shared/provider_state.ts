import { HttpError } from './http.ts';

type GoogleSubscriptionLineItem = {
  productId?: string;
  expiryTime?: string;
  autoRenewingPlan?: {
    autoRenewEnabled?: boolean;
  };
};

export type GoogleSubscriptionPurchaseV2 = {
  startTime?: string;
  subscriptionState?: string;
  latestOrderId?: string;
  acknowledgementState?: string;
  linkedPurchaseToken?: string;
  lineItems?: GoogleSubscriptionLineItem[];
  [key: string]: unknown;
};

export type NormalizedPlaySubscription = {
  productId: string;
  currentPeriodStart: string;
  currentPeriodEnd: string;
  gracePeriodEnd: string;
  status:
    | 'pending'
    | 'active'
    | 'past_due'
    | 'expired'
    | 'cancelled';
  autoRenewing: boolean;
  playOrderId: string | null;
  rawState: string;
};

export function normalizeGoogleSubscription(
  raw: GoogleSubscriptionPurchaseV2,
  expectedProductId?: string,
): NormalizedPlaySubscription {
  const items = raw.lineItems ?? [];
  if (items.length === 0) {
    throw new HttpError(400, 'play_subscription_has_no_line_items');
  }

  const item = expectedProductId
    ? items.find((x) => x.productId === expectedProductId)
    : [...items].sort(
        (a, b) =>
          Date.parse(b.expiryTime ?? '1970-01-01') -
          Date.parse(a.expiryTime ?? '1970-01-01'),
      )[0];

  if (!item?.productId) {
    throw new HttpError(400, 'play_product_id_mismatch');
  }
  if (expectedProductId && item.productId !== expectedProductId) {
    throw new HttpError(400, 'play_product_id_mismatch');
  }
  if (!item.expiryTime || Number.isNaN(Date.parse(item.expiryTime))) {
    throw new HttpError(400, 'play_missing_expiry_time');
  }

  const now = Date.now();
  const periodEndMs = Date.parse(item.expiryTime);
  const graceEnd = new Date(item.expiryTime).toISOString();
  const graceEndMs = Date.parse(graceEnd);
  const state = String(
    raw.subscriptionState ?? 'SUBSCRIPTION_STATE_UNSPECIFIED',
  );

  // Google owns its grace window. Never manufacture access for hold, pause,
  // expired, unknown, or revoked purchases from a future timestamp alone.
  let status: NormalizedPlaySubscription['status'] = 'expired';
  if (state === 'SUBSCRIPTION_STATE_PENDING' ||
      state === 'SUBSCRIPTION_STATE_PENDING_PURCHASE_CANCELED') {
    status = 'pending';
  } else if (state === 'SUBSCRIPTION_STATE_ACTIVE' && now < periodEndMs) {
    status = 'active';
  } else if (state === 'SUBSCRIPTION_STATE_CANCELED' && now < periodEndMs) {
    status = 'cancelled';
  } else if (state === 'SUBSCRIPTION_STATE_IN_GRACE_PERIOD' && now < graceEndMs) {
    status = 'past_due';
  }

  return {
    productId: item.productId,
    currentPeriodStart:
      raw.startTime && !Number.isNaN(Date.parse(raw.startTime))
        ? new Date(raw.startTime).toISOString()
        : new Date(Math.min(now, periodEndMs)).toISOString(),
    currentPeriodEnd: new Date(item.expiryTime).toISOString(),
    gracePeriodEnd: graceEnd,
    status,
    autoRenewing: item.autoRenewingPlan?.autoRenewEnabled ?? false,
    playOrderId:
      typeof raw.latestOrderId === 'string'
        ? raw.latestOrderId
        : null,
    rawState: state,
  };
}


export function normalizeMidtransStatus(
  payload: Record<string, unknown>,
):
  | 'pending'
  | 'active'
  | 'cancelled'
  | 'expired' {
  const status = String(
    payload.transaction_status ?? '',
  ).toLowerCase();
  const statusCode = String(payload.status_code ?? '');
  const fraud = String(payload.fraud_status ?? '').toLowerCase();

  if (status === 'settlement' && statusCode === '200') {
    return 'active';
  }
  if (
    status === 'capture' &&
    statusCode === '200' &&
    fraud === 'accept'
  ) {
    return 'active';
  }
  if (status === 'pending' || status === 'authorize') {
    return 'pending';
  }
  if (['expire', 'refund', 'partial_refund', 'chargeback', 'partial_chargeback'].includes(status)) return 'expired';
  if (
    status === 'cancel' ||
    status === 'deny' ||
    status === 'failure'
  ) {
    return 'cancelled';
  }
  return 'pending';
}
