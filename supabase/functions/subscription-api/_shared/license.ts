import { SignJWT, importPKCS8 } from 'npm:jose@5.10.0';
import { supabaseAdmin } from './auth.ts';
import {
  env,
  LICENSE_REFRESH_DAYS,
  LICENSE_TOKEN_DAYS,
} from './env.ts';

import { type DbSubscription, type EntitlementStatus } from './entitlement.ts';
export { deriveEntitlementStatus, type DbSubscription } from './entitlement.ts';

let privateKeyPromise: ReturnType<typeof importPKCS8> | null = null;

async function privateKeyPem(): Promise<string> {
  const environmentKey = env.licensePrivateKeyPem.trim();
  if (environmentKey) {
    return environmentKey;
  }

  const { data, error } = await supabaseAdmin.rpc('get_license_private_key');
  if (error || typeof data !== 'string' || data.trim().length === 0) {
    throw new Error('license_private_key_unavailable');
  }
  return data;
}

function privateKey() {
  privateKeyPromise ??= privateKeyPem().then((pem) => importPKCS8(pem, 'RS256'));
  return privateKeyPromise;
}

export async function signLicense(input: {
  userId: string;
  deviceId: string;
  sub: DbSubscription | null;
  features: string[];
  status: EntitlementStatus;
}): Promise<{
  token: string;
  serverTime: string;
  refreshBy: string;
}> {
  const now = new Date();
  const refreshBy = new Date(
    now.getTime() + LICENSE_REFRESH_DAYS * 86_400_000,
  );
  const tokenExp = new Date(
    now.getTime() + LICENSE_TOKEN_DAYS * 86_400_000,
  );

  const claims = {
    user_id: input.userId,
    device_id: input.deviceId,
    plan_id: input.sub?.plan_id ?? null,
    features: input.features,
    status: input.status,
    payment_provider: input.sub?.payment_provider ?? null,
    current_period_end: input.sub?.current_period_end ?? null,
    grace_period_end: input.sub?.payment_provider === 'play_billing'
      ? input.sub.current_period_end : input.sub?.grace_period_end ?? null,
    auto_renewing: input.sub?.auto_renewing ?? false,
    server_time: now.toISOString(),
    refresh_by: refreshBy.toISOString(),
  };

  const token = await new SignJWT(claims)
    .setProtectedHeader({ alg: 'RS256', typ: 'JWT' })
    .setIssuer(env.licenseIssuer)
    .setAudience(env.licenseAudience)
    .setSubject(input.userId)
    .setIssuedAt()
    .setJti(crypto.randomUUID())
    // JWT exp protects the cached token itself. Signed subscription expiry
    // remains current_period_end + grace_period_end.
    .setExpirationTime(Math.floor(tokenExp.getTime() / 1000))
    .sign(await privateKey());

  return {
    token,
    serverTime: now.toISOString(),
    refreshBy: refreshBy.toISOString(),
  };
}
