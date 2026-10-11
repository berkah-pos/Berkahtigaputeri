import { HttpError } from "./http.ts";
import { verifyPubSubPush } from "./pubsub.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

Deno.test("Google Play RTDN rejects requests without an OIDC bearer token", async () => {
  let caught: unknown;
  try {
    await verifyPubSubPush(new Request("https://localhost/billing/play/rtdn", { method: "POST" }));
  } catch (error) {
    caught = error;
  }
  assert(caught instanceof HttpError, "request should throw HttpError");
  assert(caught.status === 401, "missing Pub/Sub token should return unauthorized");
});
