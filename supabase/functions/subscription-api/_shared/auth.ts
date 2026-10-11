import { createClient } from 'npm:@supabase/supabase-js@2.117.2';
import { env } from './env.ts';
import { HttpError } from './http.ts';

export const supabaseAdmin = createClient(
  env.supabaseUrl,
  env.supabaseServiceRoleKey,
  {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  },
);

function bearer(req: Request): string {
  const header = req.headers.get('authorization') ?? '';
  const match = /^Bearer\s+(.+)$/i.exec(header);
  if (!match) throw new HttpError(401, 'missing_bearer_token');
  return match[1];
}

export async function requireUser(
  req: Request,
  claimedUserId?: string,
): Promise<string> {
  const accessToken = bearer(req);
  const { data, error } = await supabaseAdmin.auth.getUser(accessToken);
  if (error || !data.user) throw new HttpError(401, 'invalid_access_token');

  const userId = data.user.id;
  if (claimedUserId && claimedUserId !== userId) {
    throw new HttpError(403, 'user_id_mismatch');
  }
  return userId;
}
