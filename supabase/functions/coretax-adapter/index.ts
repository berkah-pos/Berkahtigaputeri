import { createClient } from 'npm:@supabase/supabase-js@2.117.2';

type JsonObject = Record<string, unknown>;
type RequestBody = {
  action?: unknown;
  tax_document_id?: unknown;
  template_code?: unknown;
  outbox_id?: unknown;
  coretax_reference?: unknown;
  result?: unknown;
  details?: unknown;
  tenant_id?: unknown;
  billing_code?: unknown;
  amount?: unknown;
  device_id?: unknown;
  app_version?: unknown;
  reason?: unknown;
};

const headers = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Content-Type': 'application/json; charset=utf-8',
  'Cache-Control': 'no-store',
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers });
}

function text(v: unknown, field: string): string {
  if (typeof v !== 'string' || v.trim().length === 0) throw new Error(`invalid_${field}`);
  return v.trim();
}

function optionalText(v: unknown): string | null {
  if (typeof v !== 'string') return null;
  const s = v.trim();
  return s.length ? s : null;
}

function object(v: unknown, field: string): JsonObject {
  if (!v || typeof v !== 'object' || Array.isArray(v)) throw new Error(`invalid_${field}`);
  return v as JsonObject;
}

function adminKey(): string {
  const keys = Deno.env.get('SUPABASE_SECRET_KEYS');
  if (keys) {
    const parsed = JSON.parse(keys) as Record<string, string>;
    if (parsed.default) return parsed.default;
  }
  const legacy = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!legacy) throw new Error('supabase_admin_key_missing');
  return legacy;
}

function publicKey(): string {
  const key = Deno.env.get('SUPABASE_PUBLISHABLE_KEY') ?? Deno.env.get('SUPABASE_ANON_KEY');
  if (!key) throw new Error('supabase_public_key_missing');
  return key;
}

function escapeXml(value: unknown): string {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');
}

function resolvePath(root: unknown, path: string): unknown {
  let current: unknown = root;
  for (const part of path.split('.')) {
    if (!current || typeof current !== 'object' || Array.isArray(current)) return undefined;
    current = (current as JsonObject)[part];
  }
  return current;
}

function renderVerifiedTemplate(xmlTemplate: string, spec: JsonObject, data: unknown): string {
  const status = optionalText(spec.status);
  if (status === 'SOURCE_REGISTERED_NOT_PARSED') throw new Error('official_coretax_template_not_verified');
  const declared = Array.isArray(spec.required_placeholders)
    ? new Set((spec.required_placeholders as unknown[]).map((v) => String(v)))
    : null;
  const paths = [...xmlTemplate.matchAll(/\{\{([A-Za-z0-9_.-]+)\}\}/g)].map((m) => m[1]);
  if (paths.length === 0) throw new Error('verified_template_has_no_placeholders');
  if (declared) {
    for (const path of paths) if (!declared.has(path)) throw new Error(`undeclared_xml_placeholder:${path}`);
    for (const path of declared) if (!paths.includes(path)) throw new Error(`declared_placeholder_missing_from_template:${path}`);
  }
  const rendered = xmlTemplate.replace(/\{\{([A-Za-z0-9_.-]+)\}\}/g, (_m, path: string) => {
    const value = resolvePath(data, path);
    if (value === undefined || value === null) throw new Error(`missing_xml_field:${path}`);
    return escapeXml(value);
  });
  if (rendered.includes('{{') || rendered.includes('}}')) throw new Error('unresolved_xml_placeholder');
  return rendered;
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers });
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);

  try {
    const authHeader = req.headers.get('authorization');
    if (!authHeader) return json({ error: 'authentication_required' }, 401);
    const url = Deno.env.get('SUPABASE_URL');
    if (!url) throw new Error('supabase_url_missing');

    const userClient = createClient(url, publicKey(), {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const admin = createClient(url, adminKey(), { auth: { persistSession: false, autoRefreshToken: false } });
    const { data: userData, error: userError } = await userClient.auth.getUser();
    if (userError || !userData.user) return json({ error: 'authentication_required' }, 401);

    const body = (await req.json()) as RequestBody;
    const action = text(body.action, 'action').toLowerCase();
    const deviceId = text(body.device_id, 'device_id');
    const appVersion = text(body.app_version, 'app_version');
    const reason = text(body.reason, 'reason');
    if (reason.length < 3) throw new Error('invalid_reason');

    if (action === 'prepare') {
      const taxDocumentId = text(body.tax_document_id, 'tax_document_id');
      const templateCode = text(body.template_code, 'template_code');
      const { data: pkgData, error: pkgError } = await userClient.rpc('prepare_coretax_export_package', {
        p_tax_document_id: taxDocumentId,
        p_template_code: templateCode,
        p_device_id: deviceId,
        p_app_version: appVersion,
        p_reason: reason,
      });
      if (pkgError) return json({ error: pkgError.message, code: pkgError.code }, pkgError.code === '23514' ? 409 : 400);
      const pkg = object(pkgData, 'export_package');
      const template = object(pkg.template, 'template');
      const data = object(pkg.data, 'data');
      const spec = object(template.generator_spec, 'generator_spec');
      const xmlTemplate = text(template.xml_template, 'xml_template');
      const xml = renderVerifiedTemplate(xmlTemplate, spec, data);

      const { data: outboxId, error: saveError } = await admin.rpc('save_coretax_export_internal', {
        p_tax_document_id: taxDocumentId,
        p_template_id: text(template.template_id, 'template_id'),
        p_xml_payload: xml,
        p_actor_user_id: userData.user.id,
        p_device_id: deviceId,
        p_reason: reason,
      });
      if (saveError) return json({ error: saveError.message, code: saveError.code }, 409);
      return json({ outbox_id: outboxId, template_code: templateCode, xml, delivery_mode: 'XML_MANUAL_OR_PJAP_PLUGIN' });
    }

    if (action === 'submit') {
      const { error } = await userClient.rpc('mark_coretax_submitted', {
        p_outbox_id: text(body.outbox_id, 'outbox_id'),
        p_coretax_reference: text(body.coretax_reference, 'coretax_reference'),
        p_device_id: deviceId,
        p_app_version: appVersion,
        p_reason: reason,
      });
      if (error) return json({ error: error.message, code: error.code }, 409);
      return json({ ok: true, status: 'SENT' });
    }

    if (action === 'result') {
      const { error } = await userClient.rpc('record_coretax_result', {
        p_outbox_id: text(body.outbox_id, 'outbox_id'),
        p_result: text(body.result, 'result'),
        p_reference: optionalText(body.coretax_reference),
        p_details: body.details && typeof body.details === 'object' && !Array.isArray(body.details) ? body.details : {},
        p_device_id: deviceId,
        p_app_version: appVersion,
        p_reason: reason,
      });
      if (error) return json({ error: error.message, code: error.code }, 409);
      return json({ ok: true });
    }

    if (action === 'status') {
      const { data, error } = await userClient.rpc('get_coretax_status', {
        p_tax_document_id: text(body.tax_document_id, 'tax_document_id'),
      });
      if (error) return json({ error: error.message, code: error.code }, 400);
      return json(data);
    }

    if (action === 'billing') {
      const amount = typeof body.amount === 'number' && Number.isSafeInteger(body.amount) ? body.amount : Number.NaN;
      if (!Number.isSafeInteger(amount) || amount <= 0) throw new Error('invalid_amount');
      const { data, error } = await userClient.rpc('register_tax_payment_reference', {
        p_tenant_id: text(body.tenant_id, 'tenant_id'),
        p_tax_document_id: optionalText(body.tax_document_id),
        p_billing_code: text(body.billing_code, 'billing_code'),
        p_amount: amount,
        p_device_id: deviceId,
        p_app_version: appVersion,
        p_reason: reason,
      });
      if (error) return json({ error: error.message, code: error.code }, 400);
      return json({ payment_ref_id: data });
    }

    if (action === 'pjap_submit') {
      const adapterUrl = Deno.env.get('PJAP_ADAPTER_URL');
      const adapterKey = Deno.env.get('PJAP_ADAPTER_KEY');
      if (!adapterUrl || !adapterKey) return json({ error: 'pjap_plugin_not_configured' }, 501);
      return json({ error: 'prepare_xml_first_then_submit_via_configured_pjap_plugin', adapter_configured: true }, 409);
    }

    return json({ error: 'unsupported_action' }, 400);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error('coretax-adapter failed', message);
    if (message.startsWith('invalid_') || message.startsWith('missing_xml_field:') || message.startsWith('undeclared_xml_placeholder:')) {
      return json({ error: message }, 400);
    }
    if (message.includes('not_verified') || message.includes('hard_gate')) return json({ error: message }, 409);
    return json({ error: 'coretax_adapter_failed' }, 500);
  }
});
