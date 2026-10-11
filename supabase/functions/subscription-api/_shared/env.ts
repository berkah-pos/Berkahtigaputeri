function required(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error(`Missing required environment variable: ${name}`);
  return value;
}

function optional(name: string, fallback = ''): string {
  return Deno.env.get(name)?.trim() || fallback;
}

export function requireConfigured(value: string, name: string): string {
  if (!value.trim()) throw new Error(`Missing required environment variable: ${name}`);
  return value;
}

export const env = {
  supabaseUrl: required('SUPABASE_URL'),
  supabaseServiceRoleKey: required('SUPABASE_SERVICE_ROLE_KEY'),

  // Provider configuration is intentionally lazy. Direct staging must be able
  // to boot before Play Console credentials exist, and vice versa.
  googlePlayPackageName: optional(
    'GOOGLE_PLAY_PACKAGE_NAME',
    'com.berkahtigaputeri.pos',
  ),
  googlePlayServiceAccountJson: optional('GOOGLE_PLAY_SERVICE_ACCOUNT_JSON'),
  pubsubAudience: optional('PUBSUB_AUDIENCE'),
  pubsubPushServiceAccountEmail: optional('PUBSUB_PUSH_SERVICE_ACCOUNT_EMAIL'),

  licensePrivateKeyPem:
    optional('LICENSE_PRIVATE_KEY_PEM').replaceAll('\\n', '\n'),
  licenseIssuer: optional('LICENSE_ISSUER', 'pos-license-server'),
  licenseAudience: optional('LICENSE_AUDIENCE', 'pos-flutter-client'),

  midtransServerKey: optional('MIDTRANS_SERVER_KEY'),
  midtransIsProduction:
    optional('MIDTRANS_IS_PRODUCTION', 'false').toLowerCase() === 'true',
  midtransFinishUrl:
    optional('MIDTRANS_FINISH_URL', 'https://example.com/payment/finish'),
  midtransUnfinishUrl:
    optional('MIDTRANS_UNFINISH_URL', 'https://example.com/payment/unfinish'),
  midtransErrorUrl:
    optional('MIDTRANS_ERROR_URL', 'https://example.com/payment/error'),
};

export const GRACE_DAYS = 3;
export const LICENSE_REFRESH_DAYS = 7;
export const LICENSE_TOKEN_DAYS = 8;
