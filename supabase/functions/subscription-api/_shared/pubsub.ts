import { createRemoteJWKSet, jwtVerify } from 'npm:jose@5.10.0';
import { env, requireConfigured } from './env.ts';
import { HttpError } from './http.ts';

const googleJwks = createRemoteJWKSet(
  new URL('https://www.googleapis.com/oauth2/v3/certs'),
);

export async function verifyPubSubPush(req: Request): Promise<void> {
  const auth = req.headers.get('authorization') ?? '';
  const match = /^Bearer\s+(.+)$/i.exec(auth);
  if (!match) throw new HttpError(401, 'missing_pubsub_oidc_token');

  try {
    const audience = requireConfigured(env.pubsubAudience, 'PUBSUB_AUDIENCE');
    const pushEmail = requireConfigured(
      env.pubsubPushServiceAccountEmail,
      'PUBSUB_PUSH_SERVICE_ACCOUNT_EMAIL',
    );
    const { payload } = await jwtVerify(match[1], googleJwks, {
      audience,
      issuer: ['https://accounts.google.com', 'accounts.google.com'],
    });

    if (
      payload.email !== pushEmail ||
      payload.email_verified !== true
    ) {
      throw new Error('unexpected_pubsub_identity');
    }
  } catch (error) {
    throw new HttpError(
      401,
      'invalid_pubsub_oidc_token',
      String(error),
    );
  }
}
