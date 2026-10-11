import { SignJWT, importPKCS8 } from 'npm:jose@5.10.0';
import { env, requireConfigured } from './env.ts';
import { HttpError } from './http.ts';

const ANDROID_PUBLISHER_SCOPE =
  'https://www.googleapis.com/auth/androidpublisher';
const GOOGLE_TOKEN_URI = 'https://oauth2.googleapis.com/token';

type ServiceAccount = {
  client_email: string;
  private_key: string;
  token_uri?: string;
};

import { type GoogleSubscriptionPurchaseV2 } from './provider_state.ts';
export { normalizeGoogleSubscription } from './provider_state.ts';

let oauthCache: { token: string; expiresAtMs: number } | null = null;

function serviceAccount(): ServiceAccount {
  try {
    return JSON.parse(
      requireConfigured(
        env.googlePlayServiceAccountJson,
        'GOOGLE_PLAY_SERVICE_ACCOUNT_JSON',
      ),
    ) as ServiceAccount;
  } catch {
    throw new Error(
      'GOOGLE_PLAY_SERVICE_ACCOUNT_JSON is not valid JSON',
    );
  }
}

async function googleAccessToken(): Promise<string> {
  const now = Date.now();
  if (oauthCache && oauthCache.expiresAtMs - 60_000 > now) {
    return oauthCache.token;
  }

  const sa = serviceAccount();
  if (!sa.client_email || !sa.private_key) {
    throw new Error(
      'Google service account JSON is missing client_email/private_key',
    );
  }

  const tokenUri = sa.token_uri || GOOGLE_TOKEN_URI;
  const key = await importPKCS8(sa.private_key, 'RS256');
  const nowSec = Math.floor(now / 1000);
  const assertion = await new SignJWT({
    scope: ANDROID_PUBLISHER_SCOPE,
  })
    .setProtectedHeader({ alg: 'RS256', typ: 'JWT' })
    .setIssuer(sa.client_email)
    .setSubject(sa.client_email)
    .setAudience(tokenUri)
    .setIssuedAt(nowSec)
    .setExpirationTime(nowSec + 3600)
    .sign(key);

  const body = new URLSearchParams({
    grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
    assertion,
  });
  const res = await fetch(tokenUri, {
    method: 'POST',
    headers: {
      'content-type': 'application/x-www-form-urlencoded',
    },
    body,
  });
  const payload = await res.json();
  if (!res.ok || typeof payload.access_token !== 'string') {
    throw new HttpError(502, 'google_oauth_failed', payload);
  }

  oauthCache = {
    token: payload.access_token,
    expiresAtMs: now + Number(payload.expires_in ?? 3600) * 1000,
  };
  return oauthCache.token;
}

export async function getGoogleSubscription(
  purchaseToken: string,
): Promise<GoogleSubscriptionPurchaseV2> {
  const accessToken = await googleAccessToken();
  const packageName = encodeURIComponent(env.googlePlayPackageName);
  const token = encodeURIComponent(purchaseToken);
  const url =
    'https://androidpublisher.googleapis.com/androidpublisher/v3/' +
    `applications/${packageName}/purchases/subscriptionsv2/tokens/${token}`;
  const res = await fetch(url, {
    headers: { authorization: `Bearer ${accessToken}` },
  });
  const payload = await res.json();
  if (!res.ok) {
    throw new HttpError(
      res.status === 404 ? 400 : 502,
      'play_subscription_verify_failed',
      payload,
    );
  }
  return payload as GoogleSubscriptionPurchaseV2;
}

export const rtdnTypeName: Record<number, string> = {
  1: 'SUBSCRIPTION_RECOVERED',
  2: 'SUBSCRIPTION_RENEWED',
  3: 'SUBSCRIPTION_CANCELED',
  4: 'SUBSCRIPTION_PURCHASED',
  5: 'SUBSCRIPTION_ON_HOLD',
  6: 'SUBSCRIPTION_IN_GRACE_PERIOD',
  7: 'SUBSCRIPTION_RESTARTED',
  9: 'SUBSCRIPTION_DEFERRED',
  10: 'SUBSCRIPTION_PAUSED',
  11: 'SUBSCRIPTION_PAUSE_SCHEDULE_CHANGED',
  12: 'SUBSCRIPTION_REVOKED',
  13: 'SUBSCRIPTION_EXPIRED',
  19: 'SUBSCRIPTION_PRICE_STEP_UP_CONSENT_UPDATED',
};
