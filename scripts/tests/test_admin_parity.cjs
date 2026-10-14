'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const root = path.resolve(__dirname, '..', '..');
const editorSource = fs.readFileSync(path.join(root, 'btp-admin/editor-core.js'), 'utf8');
const fieldSource = fs.readFileSync(path.join(root, 'btp-admin/admin-fields.js'), 'utf8');
const start = fieldSource.indexOf('window.BTP_FIELDS=');
const open = fieldSource.indexOf('[', start);
const close = fieldSource.lastIndexOf(']');
assert.ok(start >= 0 && open >= 0 && close > open, 'BTP_FIELDS contract must be a JSON array');
const fields = JSON.parse(fieldSource.slice(open, close + 1));
assert.equal(fields.length, 43, 'Admin field manifest must remain at 43 entries');

const tenantId = 'tenantA';
const deviceId = 'deviceA';
const appConfig = {
  global: {version: 1, common: 'global', winner: 'global', globalOnly: true},
  'template:PRO': {
    version: 2, common: 'template', winner: 'template',
    templateOnly: true, features: {pos: true, akuntansi: false},
  },
  'tenant:tenantA': {
    version: 8, tenant_id: tenantId, template_id: 'PRO',
    toko_name: 'Tenant A', expiry: '2027-01-01', max_user: 3, blocked: false,
    common: 'tenant', winner: 'tenant', tenantOnly: true, unrenderedTenantMarker: 'preserve-me',
  },
  'tenant:tenantA:service:pos': {
    version: 5, common: 'pos-service', winner: 'pos-service',
    posOnly: true, inherited_from_template: 'template:PRO', mdr: 0.5, mdr_pos: 0.4,
    qris_mdr: 0.7, 'mdr_%': 1.2,
  },
  'tenant:tenantA:service:akuntansi': {
    version: 7, common: 'akuntansi-service', winner: 'akuntansi-service',
    akuntansiOnly: true, ppn_rate: 11,
  },
  'device:deviceA': {
    version: 6, device_id: deviceId, tenant_id: tenantId,
    common: 'device', winner: 'device', deviceOnly: true, printer_type: 'PDF Preview',
  },
};
const reads = [];
const rpcCalls = [];
const elements = new Map();
function element(id) {
  if (!elements.has(id)) {
    elements.set(id, {
      id, value: '', checked: false, disabled: false, textContent: '',
      className: '', innerHTML: '', href: '',
      addEventListener() {},
    });
  }
  return elements.get(id);
}
const document = {getElementById: element};
const location = {search: '?tenant=tenantA'};
const supabase = {
  auth: {currentSession: {user: {id: 'admin-user'}}},
  from(table) {
    const query = {table, selected: '*', filter: null};
    const builder = {
      select(columns) {query.selected = columns; return this;},
      eq(column, value) {query.filter = {column, value}; return this;},
      order() {
        assert.equal(table, 'devices');
        return Promise.resolve({
          data: [{device_id: deviceId, tenant_id: tenantId, package_id: 'com.btp.test',
            hardware_mode: 'SIMULATED', printer_type: 'PDF Preview', created_at: '2026-01-01'}],
          error: null,
        });
      },
      maybeSingle() {
        assert.equal(table, 'tenants');
        assert.equal(query.filter.value, tenantId);
        return Promise.resolve({
          data: {tenant_id: tenantId, toko_name: 'Tenant A', template_id: 'PRO',
            package_id: 'com.btp.test', max_user: 3, expiry: '2027-01-01', is_blocked: false},
          error: null,
        });
      },
      in(column, keys) {
        assert.equal(table, 'app_config');
        assert.equal(column, 'key');
        reads.push([...keys]);
        return Promise.resolve({
          data: keys.filter(key => appConfig[key]).map(key => ({
            key, value: structuredClone(appConfig[key]), updated_at: '2026-10-14T00:00:00Z',
          })),
          error: null,
        });
      },
    };
    return builder;
  },
  async rpc(name, params) {
    rpcCalls.push({name, params: structuredClone(params)});
    assert.equal(name, 'update_app_config_atomic');
    const current = appConfig[params.p_key];
    assert.ok(current, 'atomic update must target an existing canonical key');
    assert.equal(current.version, params.p_expected_version, 'RPC must use the loaded version');
    const next = {...params.p_new_value, version: current.version + 1};
    appConfig[params.p_key] = next;
    return {data: structuredClone(next), error: null};
  },
};
const window = {
  BTP_FIELDS: fields,
  BTP_AUTH: {async requireAdmin() {return {id: 'admin-user'};}, client() {return supabase;}},
};
const context = {window, document, location, URLSearchParams, Date, structuredClone, console};
vm.runInNewContext(editorSource, context, {filename: 'btp-admin/editor-core.js'});
const editor = window.BTP_EDITOR;
assert.ok(editor, 'Admin editor must expose its API');

function expectedEffective(service) {
  const serviceKey = 'tenant:' + tenantId + ':service:' + service;
  const serviceRow = {...appConfig[serviceKey]};
  if (serviceRow.inherited_from_template != null && String(serviceRow.inherited_from_template).trim() !== '') {
    delete serviceRow.mdr;
    delete serviceRow.mdr_pos;
    delete serviceRow.qris_mdr;
    delete serviceRow['mdr_%'];
  }
  return {
    ...appConfig.global,
    ...appConfig['template:PRO'],
    ...appConfig['tenant:' + tenantId],
    ...serviceRow,
    ...appConfig['device:' + deviceId],
  };
}

(async () => {
  assert.equal(await editor.init(), true, 'Admin editor should load canonical layers');
  assert.deepEqual(reads[0], [
    'global', 'template:PRO', 'tenant:tenantA',
    'tenant:tenantA:service:pos', 'device:deviceA',
  ], 'POS must request exactly the canonical five rows and include TEMPLATE');
  let effective = JSON.parse(JSON.stringify(editor.getEffectiveConfig()));
  assert.deepEqual(effective, expectedEffective('pos'), 'Admin POS result must match the canonical five-layer merge');
  assert.equal(effective.winner, 'device', 'DEVICE must have the highest precedence');
  assert.equal(effective.features.akuntansi, false, 'template feature defaults must be inherited');
  assert.equal(Object.hasOwn(effective, 'mdr'), false, 'inherited service MDR must be stripped consistently with RPC');

  assert.equal(await editor.setService('akuntansi'), true, 'Admin should load the requested accounting service');
  assert.deepEqual(reads[1], [
    'global', 'template:PRO', 'tenant:tenantA',
    'tenant:tenantA:service:akuntansi', 'device:deviceA',
  ], 'Akuntansi must request only its own service row');
  effective = JSON.parse(JSON.stringify(editor.getEffectiveConfig()));
  assert.deepEqual(effective, expectedEffective('akuntansi'), 'Admin Akuntansi result must match the canonical five-layer merge');
  assert.equal(effective.akuntansiOnly, true);
  assert.equal(Object.hasOwn(effective, 'posOnly'), false, 'POS-only settings must not leak into Akuntansi');

  assert.equal(await editor.saveTenant({features: {pos: false, akuntansi: true}}), true,
    'Tenant and feature changes must save through the atomic config RPC');
  assert.equal(rpcCalls.length, 1, 'Tenant and feature override must use exactly one atomic RPC');
  assert.equal(rpcCalls[0].params.p_key, 'tenant:tenantA');
  assert.equal(rpcCalls[0].params.p_expected_version, 8);
  assert.equal(rpcCalls[0].params.p_new_value.template_id, 'PRO',
    'Save must preserve the template assignment not directly editable in the form');
  assert.equal(rpcCalls[0].params.p_new_value.unrenderedTenantMarker, 'preserve-me',
    'Save must preserve canonical properties not rendered by the Admin form');
  assert.deepEqual(JSON.parse(JSON.stringify(rpcCalls[0].params.p_new_value.features)),
    {pos: false, akuntansi: true});
  assert.equal(appConfig['tenant:tenantA'].version, 9);
  console.log('PASS: Admin and expected RPC resolver agree for POS and Akuntansi; versioned tenant save preserves canonical fields.');
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
