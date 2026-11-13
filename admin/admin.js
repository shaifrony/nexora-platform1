(() => {
  "use strict";
  const SUPABASE_URL = "https://qsjdeqljpnjumceewsjq.supabase.co";
  const SUPABASE_PUBLISHABLE_KEY = "sb_publishable_ZHxwvrwjAn2_UCCYsNLu8A_9twoGAKs";
  const $ = (id) => document.getElementById(id);
  const client = window.supabase?.createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY);
  if (!client) { document.body.textContent = "NEXORA: authentication library unavailable."; return; }
  let currentFactor = null;
  let currentChallenge = null;
  const escapeHtml = (value) => String(value ?? "").replace(/[&<>"']/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
  const panels = ["loginPanel","mfaPanel","deniedPanel","dashboard"];
  function show(id) { panels.forEach(x => $(x).hidden = x !== id); }
  function message(id, value) { $(id).textContent = value || ""; }
  async function sync() {
    const {data:{session}} = await client.auth.getSession();
    if (!session) { $("sessionLabel").textContent = "লগইন প্রয়োজন"; $("signOutBtn").hidden = true; show("loginPanel"); return; }
    $("signOutBtn").hidden = false;
    $("sessionLabel").textContent = session.user.email || "Signed in";
    const {data:aal,error:aalError} = await client.auth.mfa.getAuthenticatorAssuranceLevel();
    if (aalError) { show("deniedPanel"); message("deniedMessage","MFA status যাচাই করা যায়নি: "+aalError.message); return; }
    if (aal.currentLevel !== "aal2") {
      const {data:factorData,error:factorError} = await client.auth.mfa.listFactors();
      const factor = factorData?.totp?.find(x => x.status === "verified");
      if (factorError || !factor) { show("deniedPanel"); message("deniedMessage","প্রশাসনিক অ্যাকাউন্টে প্রবেশের আগে Authenticator MFA সেটআপ সম্পন্ন করতে হবে।"); return; }
      currentFactor = factor.id;
      const {data:challenge,error:challengeError} = await client.auth.mfa.challenge({factorId:currentFactor});
      if (challengeError) { show("deniedPanel"); message("deniedMessage",challengeError.message); return; }
      currentChallenge = challenge.id; show("mfaPanel"); return;
    }
    const {data:staff,error:staffError} = await client.from("admin_staff").select("user_id,admin_code,admin_level,department_key,position_key,staff_email,is_active").eq("user_id",session.user.id).maybeSingle();
    if (staffError || !staff || !staff.is_active) { show("deniedPanel"); message("deniedMessage",staffError?.message || "এই অ্যাকাউন্টে সক্রিয় কর্মকর্তা অনুমতি নেই।"); return; }
    const {data:grants,error:grantError} = await client.from("admin_permission_grants").select("permission_key,is_allowed").eq("admin_user_id",session.user.id).eq("is_allowed",true);
    if (grantError) { show("deniedPanel"); message("deniedMessage","Permission যাচাই করা যায়নি: "+grantError.message); return; }
    renderDashboard(staff,grants||[]);
  }
  function renderDashboard(staff,grants) {
    const names = {super_admin:"Director",managing_director:"Managing Director",department_head:"বিভাগীয় প্রধান",department_officer:"বিভাগীয় কর্মকর্তা"};
    const dept = {marketing:"Marketing Department",transport:"Transport & Logistics",accounts:"Accounts & Finance",managing_director:"MD Office"};
    const title = staff.admin_level==="super_admin" ? "Director" : (names[staff.position_key]||"NEXORA Officer");
    $("welcomeTitle").textContent = title+" Dashboard";
    $("welcomeSubtitle").textContent = (dept[staff.department_key]||staff.department_key||"NEXORA Administration")+" · "+(staff.staff_email||"");
    $("adminCode").textContent = staff.admin_code||"NEX-ADM";
    $("adminPosition").textContent = title;
    const modules = [
      ["Marketing","Buyer/Seller onboarding ও campaign","marketing",["marketing.leads.view","marketing.leads.manage","marketing.campaigns.manage"]],
      ["Transport & Logistics","Delivery, Partner ও Assignment","transport",["transport.partners.view","transport.partners.manage","transport.staff.manage","logistics.view","logistics.assign"]],
      ["Accounts & Finance","আর্থিক রেকর্ড ও হিসাব","accounts",["finance.view","finance.transactions.view","finance.transactions.manage","finance.refunds.request","finance.refunds.approve","finance.payouts.manage"]]
    ];
    const keys = new Set(grants.map(x=>x.permission_key));
    const allowed = modules.filter(m=>staff.admin_level==="super_admin"||m[3].some(k=>keys.has(k)));
    $("moduleNav").innerHTML = allowed.map(m=>'<div class="module-card"><strong>'+escapeHtml(m[0])+'</strong><p>'+escapeHtml(m[1])+'</p></div>').join("") || '<p class="muted">আপনার জন্য এখনো কোনো বিভাগীয় Permission বরাদ্দ নেই।</p>';
    $("permissionList").innerHTML = grants.length ? grants.map(g=>'<div class="permission"><strong>'+escapeHtml(g.permission_key)+'</strong><small>অনুমোদিত Permission</small></div>').join("") : '<p class="muted">কোনো অতিরিক্ত Permission বরাদ্দ নেই।</p>';
    $("directorNotice").hidden = staff.admin_level!=="super_admin";
    show("dashboard");
  }
  $("loginForm").addEventListener("submit",async e=>{
    e.preventDefault(); const f=new FormData(e.currentTarget); const btn=e.currentTarget.querySelector("button"); btn.disabled=true;
    const {error}=await client.auth.signInWithPassword({email:String(f.get("email")),password:String(f.get("password"))});
    btn.disabled=false; if(error) message("loginMessage",error.message); else {message("loginMessage",""); await sync();}
  });
  $("mfaForm").addEventListener("submit",async e=>{
    e.preventDefault(); const code=String(new FormData(e.currentTarget).get("code")||""); const btn=e.currentTarget.querySelector("button"); btn.disabled=true;
    const {error}=await client.auth.mfa.verify({factorId:currentFactor,challengeId:currentChallenge,code});
    btn.disabled=false; if(error) message("mfaMessage",error.message); else {message("mfaMessage",""); await sync();}
  });
  async function signOut(){await client.auth.signOut();currentFactor=null;currentChallenge=null;await sync();}
  $("signOutBtn").addEventListener("click",signOut); $("deniedSignOut").addEventListener("click",signOut);
  client.auth.onAuthStateChange(()=>{setTimeout(sync,0);});
  sync();
})();