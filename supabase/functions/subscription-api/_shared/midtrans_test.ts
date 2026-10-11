import { verifyMidtransSignature } from "./midtrans.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

function toHex(buffer: ArrayBuffer): string {
  return [...new Uint8Array(buffer)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function signature(orderId: string, statusCode: string, grossAmount: string, serverKey: string): Promise<string> {
  const input = new TextEncoder().encode(`${orderId}${statusCode}${grossAmount}${serverKey}`);
  return toHex(await crypto.subtle.digest("SHA-512", input));
}

Deno.test("Midtrans webhook signature accepts a matching server-key digest", async () => {
  const serverKey = Deno.env.get("MIDTRANS_SERVER_KEY");
  assert(serverKey, "CI test server key must be set");
  const orderId = "pos-test-order-001";
  const statusCode = "200";
  const grossAmount = "25000.00";
  const signatureKey = await signature(orderId, statusCode, grossAmount, serverKey);
  const accepted = await verifyMidtransSignature({
    order_id: orderId,
    status_code: statusCode,
    gross_amount: grossAmount,
    signature_key: signatureKey,
  });
  assert(accepted, "correct signature should pass");
});

Deno.test("Midtrans webhook signature rejects changed amount and missing signatures", async () => {
  const serverKey = Deno.env.get("MIDTRANS_SERVER_KEY");
  assert(serverKey, "CI test server key must be set");
  const signatureKey = await signature("pos-test-order-002", "200", "25000.00", serverKey);
  const changedAmount = await verifyMidtransSignature({
    order_id: "pos-test-order-002",
    status_code: "200",
    gross_amount: "1.00",
    signature_key: signatureKey,
  });
  const missing = await verifyMidtransSignature({
    order_id: "pos-test-order-002",
    status_code: "200",
    gross_amount: "25000.00",
  });
  assert(!changedAmount, "signature must not survive a changed amount");
  assert(!missing, "missing signature must be rejected");
});
