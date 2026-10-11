import { env, GRACE_DAYS } from './_shared/env.ts';
import { requireUser, supabaseAdmin } from './_shared/auth.ts';
import { corsHeaders, HttpError, json, pathEndsWith, readJson, requiredString } from './_shared/http.ts';
import {
  getGoogleSubscription,
  normalizeGoogleSubscription,
  rtdnTypeName,
} from './_shared/google_play.ts';
import {
  createSnapTransaction,
  getMidtransTransaction,
  normalizeMidtransStatus,
  verifyMidtransSignature,
} from './_shared/midtrans.ts';
import { deriveEntitlementStatus, signLicense, type DbSubscription } from './_shared/license.ts';
import { chooseSubscription } from './_shared/entitlement.ts';
import { verifyPubSubPush } from './_shared/pubsub.ts';
import { historyEntry, type HistoryRow } from './_shared/history.ts';

async function handleHistory(req: Request, url: URL): Promise<Response> {
  // Identity comes exclusively from the verified bearer token, never a query ID.
  const userId = await requireUser(req);
  const offsetText = url.searchParams.get('offset') ?? '0';
  if (!/^\d{1,7}$/.test(offsetText)) throw new HttpError(400, 'invalid_offset');
  const offset = Number(offsetText);
  const pageSize = 50;
  const { data, error } = await supabaseAdmin.from('subscriptions')
    .select('sub_id,plan_id,status,payment_provider,midtrans_order_id,play_order_id,current_period_start,current_period_end,paid_at,created_at')
    .eq('user_id', userId)
    .order('created_at', { ascending: false })
    .order('sub_id', { ascending: false })
    .range(offset, offset + pageSize);
  if (error) throw new HttpError(500, 'history_unavailable');
  const now = new Date();
  const rows = (data ?? []) as HistoryRow[];
  return json({
    entries: rows.slice(0, pageSize).map((row) => historyEntry(row, now.getTime())),
    next_offset: rows.length > pageSize ? offset + pageSize : null,
    server_time: now.toISOString(),
  });
}

type Plan = {
  plan_id: string;
  name: string;
  description: string | null;
  price_idr_direct: number;
  play_product_id: string | null;
  duration_days: number;
  max_devices: number;
  features: unknown;
  is_active: boolean;
};

function asFeatures(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value.filter((x): x is string => typeof x === 'string' && x.length > 0);
}

function addDays(date: Date, days: number): Date {
  return new Date(date.getTime() + days * 86_400_000);
}

function b64DecodeUtf8(input: string): string {
  const normalized = input.replace(/-/g, '+').replace(/_/g, '/');
  const binary = atob(normalized);
  const bytes = Uint8Array.from(binary, (c) => c.charCodeAt(0));
  return new TextDecoder().decode(bytes);
}

async function getPlanById(planId: string, activeOnly = false): Promise<Plan> {
  let query = supabaseAdmin.from('plans').select('*').eq('plan_id', planId);
  if (activeOnly) query = query.eq('is_active', true);
  const { data, error } = await query.maybeSingle();
  if (error) throw new HttpError(500, 'db_plan_query_failed', error);
  if (!data) throw new HttpError(404, activeOnly ? 'plan_not_active' : 'plan_not_found');
  return data as Plan;
}

async function getPlanByPlayProduct(productId: string, activeOnly = false): Promise<Plan> {
  let query = supabaseAdmin
    .from('plans')
    .select('*')
    .eq('play_product_id', productId);
  if (activeOnly) query = query.eq('is_active', true);
  const { data, error } = await query.maybeSingle();
  if (error) throw new HttpError(500, 'db_plan_query_failed', error);
  if (!data) throw new HttpError(404, 'unknown_play_product_id');
  return data as Plan;
}

async function recentSubscriptions(userId: string): Promise<DbSubscription[]> {
  const { data, error } = await supabaseAdmin
    .from('subscriptions')
    .select('sub_id,user_id,plan_id,status,payment_provider,current_period_start,current_period_end,grace_period_end,auto_renewing')
    .eq('user_id', userId)
    .in('status', ['active', 'past_due', 'cancelled'])
    .order('current_period_end', { ascending: false })
    ;
  if (error) throw new HttpError(500, 'db_subscription_query_failed', error);
  return (data ?? []) as DbSubscription[];
}

async function bindDevice(input: {
  userId: string;
  deviceId: string;
  platform: string;
  appVersion: string;
  planId: string;
}): Promise<void> {
  const { error } = await supabaseAdmin.rpc('bind_license_device', {
    p_user_id: input.userId,
    p_device_id: input.deviceId,
    p_platform: input.platform,
    p_app_version: input.appVersion,
    p_plan_id: input.planId,
  });
  if (!error) return;

  const message = String(error.message ?? '');
  if (message.includes('device_limit_exceeded')) throw new HttpError(409, 'device_limit_exceeded');
  if (message.includes('device_bound_to_other_user')) throw new HttpError(409, 'device_bound_to_other_user');
  if (message.includes('invalid_platform')) throw new HttpError(400, 'invalid_platform');
  throw new HttpError(500, 'device_binding_failed', error);
}

async function insertEvent(input: {
  subId?: string | null;
  provider: 'play_billing' | 'midtrans' | 'system';
  eventType: string;
  eventKey?: string | null;
  payload: unknown;
  occurredAt?: string | null;
}): Promise<void> {
  const { error } = await supabaseAdmin.from('subscription_events').insert({
    sub_id: input.subId ?? null,
    provider: input.provider,
    event_type: input.eventType,
    event_key: input.eventKey ?? null,
    payload: input.payload,
    occurred_at: input.occurredAt ?? null,
  });
  if (error && error.code !== '23505') {
    throw new HttpError(500, 'subscription_event_insert_failed', error);
  }
}

async function eventAlreadyHandled(eventKey: string): Promise<boolean> {
  const { data, error } = await supabaseAdmin
    .from('subscription_events')
    .select('event_id')
    .eq('event_key', eventKey)
    .maybeSingle();
  if (error) throw new HttpError(500, 'event_idempotency_query_failed', error);
  return Boolean(data);
}

async function handlePlans(req: Request, url: URL): Promise<Response> {
  await requireUser(req);
  const platform = url.searchParams.get('platform');
  if (platform !== 'android_play' && platform !== 'android_direct') {
    throw new HttpError(400, 'invalid_platform');
  }

  const { data, error } = await supabaseAdmin
    .from('plans')
    .select('plan_id,name,description,price_idr_direct,play_product_id,duration_days,max_devices,features')
    .eq('is_active', true)
    .order('price_idr_direct');
  if (error) throw new HttpError(500, 'db_plan_query_failed', error);

  // Do not cross-advertise the other payment rail from the Play build.
  const plans = (data ?? []).map((p) => platform === 'android_play'
    ? {
      plan_id: p.plan_id,
      name: p.name,
      description: p.description,
      play_product_id: p.play_product_id,
      duration_days: p.duration_days,
      max_devices: p.max_devices,
      features: p.features,
    }
    : {
      plan_id: p.plan_id,
      name: p.name,
      description: p.description,
      price_idr_direct: p.price_idr_direct,
      duration_days: p.duration_days,
      max_devices: p.max_devices,
      features: p.features,
    });
  return json({ plans, server_time: new Date().toISOString() });
}

async function handleLicenseCheck(req: Request, url: URL): Promise<Response> {
  const claimedUserId = requiredString(url.searchParams.get('user_id'), 'user_id');
  const userId = await requireUser(req, claimedUserId);
  const deviceId = requiredString(url.searchParams.get('device_id'), 'device_id');
  const platform = requiredString(url.searchParams.get('platform'), 'platform');
  const appVersion = requiredString(url.searchParams.get('app_version') ?? 'unknown', 'app_version');

  if (platform !== 'android_play' && platform !== 'android_direct') {
    throw new HttpError(400, 'invalid_platform');
  }

  const rows = await recentSubscriptions(userId);
  const nowMs = Date.now();
  const sub = chooseSubscription(rows, nowMs);
  const status = deriveEntitlementStatus(sub, nowMs);
  let features: string[] = [];

  if (sub) {
    const plan = await getPlanById(sub.plan_id, false);
    if (status === 'active' || status === 'past_due') {
      await bindDevice({ userId, deviceId, platform, appVersion, planId: plan.plan_id });
      features = asFeatures(plan.features);
    }
  }

  const signed = await signLicense({ userId, deviceId, sub, features, status });
  return json({
    license_token: signed.token,
    status,
    server_time: signed.serverTime,
    refresh_by: signed.refreshBy,
    current_period_end: sub?.current_period_end ?? null,
    grace_period_end: sub?.grace_period_end ?? null,
  });
}

async function applyPlayState(
  userId: string, token: string, planId: string,
  state: ReturnType<typeof normalizeGoogleSubscription>, checkedAt: string,
  linkedToken?: string,
): Promise<string> {
  const { data, error } = await supabaseAdmin.rpc('apply_play_subscription', {
    p_user_id: userId, p_token: token, p_plan_id: planId, p_state: state,
    p_checked_at: checkedAt, p_linked_token: linkedToken ?? null,
  });
  if (error) throw new HttpError(409, 'play_subscription_apply_failed');
  return data as string;
}

type PlayVerifyBody = {
  purchaseToken?: unknown;
  productId?: unknown;
  user_id?: unknown;
  device_id?: unknown;
};

async function handlePlayVerify(req: Request): Promise<Response> {
  const body = await readJson<PlayVerifyBody>(req);
  const purchaseToken = requiredString(body.purchaseToken, 'purchaseToken');
  const productId = requiredString(body.productId, 'productId');
  const claimedUserId = requiredString(body.user_id, 'user_id');
  const userId = await requireUser(req, claimedUserId);
  requiredString(body.device_id, 'device_id'); // kept for audit correlation; binding occurs in /license/check.

  const plan = await getPlanByPlayProduct(productId, true);
  const checkedAt = new Date().toISOString();
  const raw = await getGoogleSubscription(purchaseToken);
  const normalized = normalizeGoogleSubscription(raw, productId);

  const { data: ownerRow, error: ownerError } = await supabaseAdmin
    .from('subscriptions')
    .select('user_id')
    .eq('play_purchase_token', purchaseToken)
    .maybeSingle();
  if (ownerError) throw new HttpError(500, 'db_subscription_query_failed', ownerError);
  if (ownerRow && ownerRow.user_id !== userId) {
    throw new HttpError(409, 'purchase_token_already_bound');
  }

  const account = raw.externalAccountIdentifiers as { obfuscatedExternalAccountId?: string } | undefined;
  // A token is not proof of account ownership. New purchases must have been
  // launched with this authenticated account; only already-bound legacy tokens
  // can be restored without an account identifier.
  if (account?.obfuscatedExternalAccountId !== userId &&
      !(ownerRow?.user_id === userId && !account?.obfuscatedExternalAccountId)) {
    throw new HttpError(403, 'play_purchase_account_mismatch');
  }
  const subId = await applyPlayState(userId, purchaseToken, plan.plan_id, normalized, checkedAt, raw.linkedPurchaseToken);

  await insertEvent({
    subId,
    provider: 'play_billing',
    eventType: 'purchase_verified',
    eventKey: `verify:${purchaseToken}:${normalized.currentPeriodEnd}`,
    payload: { normalized, google: raw },
    occurredAt: new Date().toISOString(),
  });

  return json({
    ok: true,
    status: normalized.status,
    current_period_end: normalized.currentPeriodEnd,
    grace_period_end: normalized.gracePeriodEnd,
    acknowledgement_required_client_side: raw.acknowledgementState !== 'ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED',
  });
}

type PubSubEnvelope = {
  message?: {
    data?: string;
    messageId?: string;
    publishTime?: string;
  };
  subscription?: string;
};

type RtdnPayload = {
  packageName?: string;
  eventTimeMillis?: string;
  subscriptionNotification?: {
    notificationType?: number;
    purchaseToken?: string;
  };
};

async function handlePlayRtdn(req: Request): Promise<Response> {
  await verifyPubSubPush(req);
  const envelope = await readJson<PubSubEnvelope>(req);
  const messageId = requiredString(envelope.message?.messageId, 'pubsub_message_id');
  if (await eventAlreadyHandled(messageId)) return new Response(null, { status: 204 });

  const encoded = requiredString(envelope.message?.data, 'pubsub_message_data');
  let rtdn: RtdnPayload;
  try {
    rtdn = JSON.parse(b64DecodeUtf8(encoded)) as RtdnPayload;
  } catch {
    throw new HttpError(400, 'invalid_rtdn_payload');
  }

  if (rtdn.packageName !== env.googlePlayPackageName) {
    throw new HttpError(400, 'rtdn_package_name_mismatch');
  }
  const notification = rtdn.subscriptionNotification;
  if (!notification?.purchaseToken || typeof notification.notificationType !== 'number') {
    // Test notifications or unsupported developer notification types are still audited.
    await insertEvent({
      provider: 'play_billing',
      eventType: 'rtdn_non_subscription',
      eventKey: messageId,
      payload: { envelope, rtdn },
      occurredAt: envelope.message?.publishTime ?? null,
    });
    return new Response(null, { status: 204 });
  }

  const purchaseToken = notification.purchaseToken;
  const checkedAt = new Date().toISOString();
  const raw = await getGoogleSubscription(purchaseToken);
  const normalized = normalizeGoogleSubscription(raw);
  const eventType = rtdnTypeName[notification.notificationType] ?? `RTDN_${notification.notificationType}`;

  const { data: existing, error: lookupError } = await supabaseAdmin
    .from('subscriptions')
    .select('sub_id,user_id')
    .eq('play_purchase_token', purchaseToken)
    .maybeSingle();
  if (lookupError) throw new HttpError(500, 'rtdn_subscription_lookup_failed', lookupError);

  if (!existing) {
    // RTDN may arrive before the client /verify call. We cannot safely guess the
    // user. Audit the event; the authenticated /verify call will create the row.
    await insertEvent({
      provider: 'play_billing',
      eventType: `orphan_${eventType}`,
      eventKey: messageId,
      payload: { envelope, rtdn, google: raw, normalized },
      occurredAt: envelope.message?.publishTime ?? null,
    });
    return new Response(null, { status: 204 });
  }

  const plan = await getPlanByPlayProduct(normalized.productId, false);
  // RTDN is a wake-up signal. Apply the current provider response, not a
  // possibly delayed notification type. No grace timestamp before period end.
  await applyPlayState(existing.user_id, purchaseToken, plan.plan_id, normalized, checkedAt, raw.linkedPurchaseToken);

  await insertEvent({
    subId: existing.sub_id,
    provider: 'play_billing',
    eventType,
    eventKey: messageId,
    payload: { envelope, rtdn, google: raw, normalized },
    occurredAt: envelope.message?.publishTime ?? null,
  });

  return new Response(null, { status: 204 });
}

type MidtransCreateBody = {
  plan_id?: unknown;
  user_id?: unknown;
  device_id?: unknown;
  platform?: unknown;
};

async function handleMidtransCreate(req: Request): Promise<Response> {
  const body = await readJson<MidtransCreateBody>(req);
  const claimedUserId = requiredString(body.user_id, 'user_id');
  const userId = await requireUser(req, claimedUserId);
  const planId = requiredString(body.plan_id, 'plan_id');
  requiredString(body.device_id, 'device_id');
  const platform = requiredString(body.platform, 'platform');
  if (platform !== 'android_direct') throw new HttpError(403, 'midtrans_not_allowed_for_play_install');

  const plan = await getPlanById(planId, true);
  const now = new Date();
  const provisionalEnd = addDays(now, plan.duration_days);
  const orderId = `pos-${crypto.randomUUID()}`;

  const { data: pending, error: insertError } = await supabaseAdmin
    .from('subscriptions')
    .insert({
      user_id: userId,
      plan_id: plan.plan_id,
      status: 'pending',
      payment_provider: 'midtrans',
      midtrans_order_id: orderId,
      midtrans_amount_idr: plan.price_idr_direct,
      midtrans_duration_days: plan.duration_days,
      current_period_start: now.toISOString(),
      current_period_end: provisionalEnd.toISOString(),
      grace_period_end: addDays(provisionalEnd, GRACE_DAYS).toISOString(),
      auto_renewing: false,
    })
    .select('sub_id')
    .single();
  if (insertError) throw new HttpError(500, 'midtrans_pending_insert_failed', insertError);

  try {
    const { data: authData } = await supabaseAdmin.auth.admin.getUserById(userId);
    const snap = await createSnapTransaction({
      orderId,
      grossAmount: plan.price_idr_direct,
      itemName: `${plan.name} subscription`,
      customerEmail: authData.user?.email ?? null,
    });

    await insertEvent({
      subId: pending.sub_id,
      provider: 'midtrans',
      eventType: 'snap_created',
      eventKey: `snap_created:${orderId}`,
      payload: { order_id: orderId, plan_id: plan.plan_id, amount: plan.price_idr_direct },
      occurredAt: now.toISOString(),
    });

    return json({
      order_id: orderId,
      snap_token: snap.token,
      redirect_url: snap.redirect_url,
      status: 'pending',
    }, 201);
  } catch (error) {
    await supabaseAdmin.from('subscriptions').update({ status: 'expired' }).eq('sub_id', pending.sub_id).eq('status', 'pending');
    throw error;
  }
}

async function applyMidtransState(
  sub: { sub_id: string }, payload: Record<string, unknown>, checkedAt: string,
): Promise<string> {
  const { data, error } = await supabaseAdmin.rpc('apply_midtrans_payment', {
    p_sub_id: sub.sub_id,
    p_status: normalizeMidtransStatus(payload),
    p_transaction_id: requiredString(payload.transaction_id, 'transaction_id'),
    p_amount: payload.gross_amount,
    p_order_id: requiredString(payload.order_id, 'order_id'),
    p_checked_at: checkedAt,
  });
  if (error) throw new HttpError(409, 'midtrans_payment_apply_failed');
  return data as string;
}

async function lookupMidtransSub(orderId: string) {
  const { data, error } = await supabaseAdmin
    .from('subscriptions')
    .select('sub_id,user_id,plan_id,status,current_period_end')
    .eq('midtrans_order_id', orderId)
    .maybeSingle();
  if (error) throw new HttpError(500, 'midtrans_subscription_lookup_failed', error);
  return data as null | {
    sub_id: string;
    user_id: string;
    plan_id: string;
    status: string;
    current_period_end: string;
  };
}

async function handleMidtransWebhook(req: Request): Promise<Response> {
  const payload = await readJson<Record<string, unknown>>(req);
  if (!await verifyMidtransSignature(payload)) throw new HttpError(401, 'invalid_midtrans_signature');

  const orderId = requiredString(payload.order_id, 'order_id');
  const transactionStatus = String(payload.transaction_status ?? 'unknown');
  const transactionId = String(payload.transaction_id ?? 'none');
  const eventKey = `midtrans:${orderId}:${transactionStatus}:${transactionId}`;
  // Always reconcile the current provider status, even for repeated signals.

  const sub = await lookupMidtransSub(orderId);
  if (!sub) {
    await insertEvent({
      provider: 'midtrans',
      eventType: 'orphan_notification',
      eventKey,
      payload,
      occurredAt: typeof payload.transaction_time === 'string' ? payload.transaction_time : null,
    });
    return new Response(null, { status: 204 });
  }

  // signature_key does not sign transaction_status/fraud_status. Fetch the
  // authoritative state rather than trusting those notification fields.
  const checkedAt = new Date().toISOString();
  const remote = await getMidtransTransaction(orderId);
  const appliedStatus = await applyMidtransState(sub, remote, checkedAt);
  await insertEvent({
    subId: sub.sub_id,
    provider: 'midtrans',
    eventType: transactionStatus,
    eventKey,
    payload: { ...payload, applied_status: appliedStatus },
    occurredAt: typeof payload.transaction_time === 'string' ? payload.transaction_time : null,
  });
  return new Response(null, { status: 204 });
}

async function handleMidtransStatus(req: Request, url: URL): Promise<Response> {
  const claimedUserId = requiredString(url.searchParams.get('user_id'), 'user_id');
  const userId = await requireUser(req, claimedUserId);
  const orderId = requiredString(url.searchParams.get('order_id'), 'order_id');
  const sub = await lookupMidtransSub(orderId);
  if (!sub || sub.user_id !== userId) throw new HttpError(404, 'midtrans_order_not_found');

  // Reconcile with Midtrans directly so polling still works if the webhook is delayed.
  try {
    const checkedAt = new Date().toISOString();
    const remote = await getMidtransTransaction(orderId);
    await applyMidtransState(sub, remote, checkedAt);
  } catch (error) {
    // A newly-created Snap transaction can return not-found until a payment method
    // is selected. In that case return the DB status rather than failing polling.
    if (!(error instanceof HttpError) || error.message !== 'midtrans_order_not_ready') throw error;
  }

  const { data, error } = await supabaseAdmin
    .from('subscriptions')
    .select('status,current_period_end,grace_period_end,plan_id')
    .eq('sub_id', sub.sub_id)
    .single();
  if (error) throw new HttpError(500, 'midtrans_status_db_failed', error);
  return json({ ...data, order_id: orderId, server_time: new Date().toISOString() });
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: corsHeaders });

  try {
    const url = new URL(req.url);
    const path = url.pathname;

    if (req.method === 'GET' && pathEndsWith(path, '/billing/history')) {
      return await handleHistory(req, url);
    }

    if (req.method === 'GET' && pathEndsWith(path, '/billing/plans')) {
      return await handlePlans(req, url);
    }
    if (req.method === 'GET' && pathEndsWith(path, '/license/check')) {
      return await handleLicenseCheck(req, url);
    }
    if (req.method === 'POST' && pathEndsWith(path, '/billing/play/verify')) {
      return await handlePlayVerify(req);
    }
    if (req.method === 'POST' && pathEndsWith(path, '/billing/play/rtdn')) {
      return await handlePlayRtdn(req);
    }
    if (req.method === 'POST' && pathEndsWith(path, '/billing/midtrans/create')) {
      return await handleMidtransCreate(req);
    }
    if (req.method === 'POST' && pathEndsWith(path, '/billing/midtrans/webhook')) {
      return await handleMidtransWebhook(req);
    }
    if (req.method === 'GET' && pathEndsWith(path, '/billing/midtrans/status')) {
      return await handleMidtransStatus(req, url);
    }

    return json({ error: 'not_found' }, 404);
  } catch (error) {
    console.error(error);
    if (error instanceof HttpError) {
      return json({ error: error.message }, error.status);
    }
    return json({ error: 'internal_server_error' }, 500);
  }
});
