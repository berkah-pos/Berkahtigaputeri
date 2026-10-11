import { env, requireConfigured } from './env.ts';
import { HttpError } from './http.ts';

function baseUrl(): string {
  return env.midtransIsProduction
    ? 'https://app.midtrans.com'
    : 'https://app.sandbox.midtrans.com';
}

function apiUrl(): string {
  return env.midtransIsProduction
    ? 'https://api.midtrans.com'
    : 'https://api.sandbox.midtrans.com';
}

function serverKey(): string {
  return requireConfigured(env.midtransServerKey, 'MIDTRANS_SERVER_KEY');
}

function authorization(): string {
  return `Basic ${btoa(`${serverKey()}:`)}`;
}

export type SnapTransaction = {
  token: string;
  redirect_url: string;
};

export async function createSnapTransaction(input: {
  orderId: string;
  grossAmount: number;
  itemName: string;
  customerEmail?: string | null;
}): Promise<SnapTransaction> {
  const payload: Record<string, unknown> = {
    transaction_details: {
      order_id: input.orderId,
      gross_amount: input.grossAmount,
    },
    item_details: [
      {
        id: input.orderId,
        price: input.grossAmount,
        quantity: 1,
        name: input.itemName.slice(0, 50),
      },
    ],
    callbacks: {
      finish: env.midtransFinishUrl,
      unfinish: env.midtransUnfinishUrl,
      error: env.midtransErrorUrl,
    },
  };

  if (input.customerEmail) {
    payload.customer_details = { email: input.customerEmail };
  }

  const res = await fetch(`${baseUrl()}/snap/v1/transactions`, {
    method: 'POST',
    headers: {
      authorization: authorization(),
      accept: 'application/json',
      'content-type': 'application/json',
    },
    body: JSON.stringify(payload),
  });
  const data = await res.json();
  if (
    !res.ok ||
    typeof data.token !== 'string' ||
    typeof data.redirect_url !== 'string'
  ) {
    throw new HttpError(
      502,
      'midtrans_snap_create_failed',
      data,
    );
  }
  return data as SnapTransaction;
}

export async function getMidtransTransaction(
  orderId: string,
): Promise<Record<string, unknown>> {
  const res = await fetch(
    `${apiUrl()}/v2/${encodeURIComponent(orderId)}/status`,
    {
      headers: {
        authorization: authorization(),
        accept: 'application/json',
      },
    },
  );
  const data = await res.json();
  if (res.status === 404 || String(data.status_code) === '404') {
    throw new HttpError(404, 'midtrans_order_not_ready');
  }
  if (!res.ok) {
    throw new HttpError(502, 'midtrans_status_failed');
  }
  return data as Record<string, unknown>;
}

function hex(bytes: ArrayBuffer): string {
  return [...new Uint8Array(bytes)]
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

function constantTimeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}

export async function verifyMidtransSignature(
  payload: Record<string, unknown>,
): Promise<boolean> {
  const orderId = String(payload.order_id ?? '');
  const statusCode = String(payload.status_code ?? '');
  const grossAmount = String(payload.gross_amount ?? '');
  const signature = String(
    payload.signature_key ?? '',
  ).toLowerCase();

  if (!orderId || !statusCode || !grossAmount || !signature) {
    return false;
  }

  const input = new TextEncoder().encode(
    `${orderId}${statusCode}${grossAmount}${serverKey()}`,
  );
  const digest = await crypto.subtle.digest('SHA-512', input);
  return constantTimeEqual(hex(digest), signature);
}

export { normalizeMidtransStatus } from './provider_state.ts';
