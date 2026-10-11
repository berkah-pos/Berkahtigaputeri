import { chooseSubscription, deriveEntitlementStatus, type DbSubscription } from "./entitlement.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

const start = "2026-10-01T00:00:00.000Z";
const end = "2026-11-01T00:00:00.000Z";
const grace = "2026-11-04T00:00:00.000Z";
const now = Date.parse("2026-10-11T00:00:00.000Z");

function sub(overrides: Partial<DbSubscription> = {}): DbSubscription {
  return {
    sub_id: "sub-test",
    user_id: "user-test",
    plan_id: "plan-test",
    status: "active",
    payment_provider: "midtrans",
    current_period_start: start,
    current_period_end: end,
    grace_period_end: grace,
    auto_renewing: false,
    ...overrides,
  };
}

Deno.test("active paid subscription grants active entitlement", () => {
  assert(deriveEntitlementStatus(sub(), now) === "active", "active subscription must be active");
});

Deno.test("Midtrans subscription enters bounded grace after paid period", () => {
  const afterPeriod = Date.parse("2026-11-02T00:00:00.000Z");
  assert(deriveEntitlementStatus(sub(), afterPeriod) === "past_due", "within grace should be past_due");
  assert(
    deriveEntitlementStatus(sub(), Date.parse("2026-11-05T00:00:00.000Z")) === "expired",
    "after grace must be expired",
  );
});

Deno.test("cancelled Play subscription keeps access only until paid period end", () => {
  const cancelled = sub({ status: "cancelled", payment_provider: "play_billing" });
  assert(deriveEntitlementStatus(cancelled, now) === "active", "cancelled-but-paid Play period should remain active");
  assert(
    deriveEntitlementStatus(cancelled, Date.parse("2026-11-01T00:00:00.000Z")) === "expired",
    "Play cancellation must not extend past paid period",
  );
});

Deno.test("pending, invalid dates and missing subscriptions fail closed", () => {
  assert(deriveEntitlementStatus(null, now) === "invalid", "missing sub must be invalid");
  assert(deriveEntitlementStatus(sub({ status: "pending" }), now) === "invalid", "pending must not grant access");
  assert(
    deriveEntitlementStatus(sub({ current_period_end: "not-a-date" }), now) === "invalid",
    "invalid period must fail closed",
  );
});

Deno.test("subscription choice prefers active entitlement using a single evaluation instant", () => {
  const chosen = chooseSubscription([
    sub({ sub_id: "old", status: "active", current_period_end: "2026-10-05T00:00:00.000Z" }),
    sub({ sub_id: "current", current_period_end: end }),
  ], now);
  assert(chosen?.sub_id === "current", "active subscription should be selected over expired period");
});
