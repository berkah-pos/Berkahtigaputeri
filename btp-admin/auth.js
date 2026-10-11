(function(){
  const ALLOWED_EMAIL='berkahtigaputeri@gmail.com';
  const DEFAULT_URL='https://cztlmwzfrhyafgawphgw.supabase.co';
  const DEFAULT_KEY='sb_publishable_LlsIisir66_TWiRRQ43l6A_yqoUDH13'; // gitleaks:allow -- public Supabase publishable key, not a secret
  const URL_KEY='btp:connUrl', ANON_KEY='btp:connKey';
  let cached=null, cachedUrl='', cachedKey='';
  function cfg(){return {url:localStorage.getItem(URL_KEY)||DEFAULT_URL,key:localStorage.getItem(ANON_KEY)||DEFAULT_KEY};}
  function saveConfig(url,key){localStorage.setItem(URL_KEY,(url||DEFAULT_URL).trim());localStorage.setItem(ANON_KEY,(key||DEFAULT_KEY).trim());cached=null;}
  function client(){
    const {url,key}=cfg(); if(!url||!key) throw new Error('Supabase URL + Anon/Publishable Key belum tersedia.');
    if(!cached||cachedUrl!==url||cachedKey!==key){cached=window.supabase.createClient(url,key,{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:true}});cachedUrl=url;cachedKey=key;}
    return cached;
  }
  async function getAdmin(){
    let c; try{c=client();}catch(_){return null;}
    const {data,error}=await c.auth.getSession(); if(error||!data.session)return null;
    const email=(data.session.user?.email||'').toLowerCase(); return email===ALLOWED_EMAIL?data.session.user:null;
  }
  async function requireAdmin(opts={}){
    const redirect=opts.redirect!==false; const user=await getAdmin();
    if(!user&&redirect){const next=encodeURIComponent(location.pathname.split('/').pop()+location.search);location.replace(`login.html?next=${next}`);} return user;
  }
  async function login(url,key,email,password){
    saveConfig(url,key); const c=client();
    const {data,error}=await c.auth.signInWithPassword({email:email.trim(),password}); if(error)throw error;
    if((data.user?.email||'').toLowerCase()!==ALLOWED_EMAIL){await c.auth.signOut();throw new Error('Akun ini bukan super admin yang diizinkan.');}
    return data.user;
  }
  async function requestPasswordReset(email,redirectTo){
    const normalized=(email||'').trim().toLowerCase();
    if(normalized!==ALLOWED_EMAIL)throw new Error('Email bukan akun Super Admin yang diizinkan.');
    const {error}=await client().auth.resetPasswordForEmail(ALLOWED_EMAIL,{redirectTo});
    if(error)throw error;
    return true;
  }
  async function updatePassword(password){
    const {data,error}=await client().auth.updateUser({password});
    if(error)throw error;
    return data.user;
  }
  async function logout(){try{await client().auth.signOut();}finally{location.replace('login.html');}}
  window.BTP_AUTH={ALLOWED_EMAIL,DEFAULT_URL,DEFAULT_KEY,cfg,saveConfig,client,getAdmin,requireAdmin,login,requestPasswordReset,updatePassword,logout};
})();
