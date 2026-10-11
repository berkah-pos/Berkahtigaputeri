import { normalizeGoogleSubscription, normalizeMidtransStatus } from "./provider_state.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

Deno.test("Google Play active and cancelled purchases are normalized from provider state", () => {
  const active = normalizeGoogleSubscription({
    startTime: "2026-10-01T00:00:00Z",
    subscriptionState: "SUBSCRIPTION_STATE_ACTIVE",
    lineItems: [{
      productId: "pos_pro_monthly",
      expiryTime: "2026-11-01T00:00:00Z",
      autoRenewingPlan: { autoRenewEnabled: true },
    }],
  }, "pos_pro_monthly");
  assert(active.status === "active", "active provider state should activate current paid period");
  assert(active.autoRenewing, "auto-renewing flag should be preserved");

  const cancelled = normalizeGoogleSubscription({
    startTime: "2026-10-01T00:00:00Z",
    subscriptionState: "SUBSCRIPTION_STATE_CANCELED",
    lineItems: [{ productId: "pos_pro_monthly", expiryTime: "2026-11-01T00:00:00Z" }],
  }, "pos_pro_monthly");
  assert(cancelled.status === "cancelled", "canceled provider state should be retained until expiry");
});

Deno.test("Google Play hold and expired periods do not grant active access", () => {
  const hold = normalizeGoogleSubscription({
    subscriptionState: "SUBSCRIPTION_STATE_ON_HOLD",
    lineItems: [{ productId: "pos_basic", expiryTime: "2026-11-01T00:00:00Z" }],
  }, "pos_basic");
  assert(hold.status === "expired", "on-hold must fail closed");

  const expired = normalizeGoogleSubscription({
    subscriptionState: "SUBSCRIPTION_STATE_ACTIVE",
    lineItems: [{ productId: "pos_basic", expiryTime: "2026-10-01T00:00:00Z" }],
  }, "pos_basic");
  assert(expired.status === "expired", "provider active state with expired period must not grant access");
});

Deno.test("Google Play product mismatch is rejected", () => {
  let rejected = false;
  try {
    normalizeGoogleSubscription({
      subscriptionState: "SUBSCRIPTION_STATE_ACTIVE",
      lineItems: [{ productId: "other-product", expiryTime: "2026-11-01T00:00:00Z" }],
    }, "expected-product");
  } catch {
    rejected = true;
  }
  assert(rejected, "product ID mismatch must be rejected");
});

Deno.test("Midtrans server states are mapped conservatively", () => {
  assert(normalizeMidtransStatus({ transaction_status: "settlement", status_code: "200" }) === "active", "settlement should activate");
  assert(normalizeMidtransStatus({ transaction_status: "capture", status_code: "200", fraud_status: "accept" }) === "active", "accepted capture should activate");
  assert(normalizeMidtransStatus({ transaction_status: "pending" }) === "pending", "pending should remain pending");
  assert(normalizeMidtransStatus({ transaction_status: "refund" }) === "expired", "refund must remove entitlement");
  assert(normalizeMidtransStatus({ transaction_status: "chargeback" }) === "expired", "chargeback must remove entitlement");
});
