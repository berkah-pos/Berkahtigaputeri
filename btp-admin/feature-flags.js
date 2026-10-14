(function(){
const $=id=>document.getElementById(id);
let tenant='',initial=null;
function current(){return {pos:$('featurePos').checked===true,akuntansi:$('featureAkuntansi').checked===true};}
function toggle(){
  const pos=$('featurePos')?.checked!==false;
  const acc=$('featureAkuntansi')?.checked===true;
  document.querySelectorAll('[data-scope="pos"] input,[data-scope="pos"] select,[data-scope="pos"] textarea').forEach(e=>e.disabled=!pos);
  document.querySelectorAll('[data-scope="akuntansi"] input,[data-scope="akuntansi"] select,[data-scope="akuntansi"] textarea').forEach(e=>e.disabled=!acc);
  const ppnAccount=$('ppnAccount');
  if(ppnAccount)ppnAccount.disabled=!acc;
  const note=$('featureNote');
  if(note)note.textContent=`POS ${pos?'ON':'OFF'} · AKUNTANSI ${acc?'ON':'OFF'}${acc?'':' — field akuntansi termasuk akun 2-2010 dinonaktifkan'}`;
}
function effectiveFeatures(){
  const config=BTP_EDITOR.getEffectiveConfig();
  const raw=config?.features;
  if(raw&&typeof raw==='object'&&!Array.isArray(raw))return {pos:raw.pos===true,akuntansi:raw.akuntansi===true};
  if('pos_enabled' in config||'akuntansi_enabled' in config)return {pos:config.pos_enabled===true,akuntansi:config.akuntansi_enabled===true};
  throw new Error('Konfigurasi efektif tidak memuat feature flags; periksa template dan canonical workbook.');
}
async function init(){
  tenant=BTP_EDITOR.getTenant();
  if(!tenant)return;
  const f=effectiveFeatures();
  initial={...f};
  $('featurePos').checked=f.pos;
  $('featureAkuntansi').checked=f.akuntansi;
  $('featurePos').onchange=toggle;
  $('featureAkuntansi').onchange=toggle;
  toggle();
}
function patch(){
  if(!initial)throw new Error('Feature flags belum dimuat');
  const next=current();
  return next.pos===initial.pos&&next.akuntansi===initial.akuntansi?{}:{features:next};
}
function markSaved(){initial=current();}
window.BTP_FEATURES={init,patch,markSaved,toggle};
})();