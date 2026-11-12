/* NEXORA Supabase Authentication — initial integration */
(() => {
  "use strict";

  const SUPABASE_URL = "https://qsjdeqljpnjumceewsjq.supabase.co";
  const SUPABASE_PUBLISHABLE_KEY = "sb_publishable_ZHxwvrwjAn2_UCCYsNLu8A_9twoGAKs";

  if (!window.supabase || !window.supabase.createClient) {
    console.error("NEXORA: Supabase JS library did not load.");
    return;
  }

  const db = window.supabase.createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY);
  let currentUser = null;
  let profile = null;
  let adminStaff = null;
  let pendingRoleRequest = null;
  let forgotMode = false;
  let recoveryMode = false;
  let mfaVerified = false;
  let mfaFactors = [];
  let mfaUnverifiedFactors = [];
  let mfaPendingFactor = null;
  let mfaChallengeId = null;
  let mfaChallengeFactorId = null;
  let mfaAssurance = null;

  const style = document.createElement("style");
  style.textContent = `
    #nexoraAccount { margin:18px 0; }
    #nexoraAccount .nx-grid { display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:12px; }
    #nexoraAccount .nx-message { padding:10px;border-radius:8px;background:#f3f6fa;margin-top:10px;white-space:pre-wrap; }
    #nexoraAccount button:disabled { opacity:.55;cursor:not-allowed; }
    #nexoraAccount .nx-social-divider{display:flex;align-items:center;gap:10px;color:#718096;font-size:12px;margin:15px 0}
    #nexoraAccount .nx-social-divider:before,#nexoraAccount .nx-social-divider:after{content:"";height:1px;background:#e3e9f0;flex:1}
    #nexoraAccount .nx-social-buttons{display:grid;grid-template-columns:1fr;gap:9px}
    #nexoraAccount .nx-social-buttons button{width:100%;border:1px solid #d6dee8;background:#fff;color:#243449}
    #nexoraAccount .nx-social-buttons .nx-yahoo{color:#6001d2}
    #nexoraAccount .nx-google-mark{font-weight:800;color:#4285f4;margin-right:8px;font-size:16px}
  `;
  document.head.appendChild(style);

  function say(message, ok = false) {
    const node = document.getElementById("nxMessage");
    if (node) {
      node.textContent = message;
      node.style.color = ok ? "#087b5f" : "#b42318";
    }
  }
  function setBusy(form, busy) {
    form.querySelectorAll("button").forEach(b => b.disabled = busy);
  }
  async function loadProfile() {
    if (!currentUser) { profile = null; adminStaff = null; pendingRoleRequest = null; return; }
    const { data, error } = await db.from("profiles")
      .select("id,full_name,role,account_status")
      .eq("id", currentUser.id).maybeSingle();
    if (error) throw error;
    profile = data;
    const pending = await db.from("role_requests")
      .select("requested_role,status,created_at")
      .eq("user_id", currentUser.id)
      .eq("status", "pending")
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();
    if (pending.error) throw pending.error;
    pendingRoleRequest = pending.data || null;
    adminStaff = null;
    if (profile?.role === "admin" && profile?.account_status === "active") {
      const staff = await db.from("admin_staff")
        .select("admin_code,admin_level,department_key,is_active")
        .eq("user_id", currentUser.id).maybeSingle();
      if (staff.error) throw staff.error;
      adminStaff = staff.data;
    }
  }
  function ensureMfaPanel() {
    let panel = document.getElementById("nxMfaPanel");
    if (!panel) {
      const logged = document.getElementById("nxLogged");
      if (!logged) return null;
      panel = document.createElement("section");
      panel.id = "nxMfaPanel";
      panel.className = "card hidden";
      logged.insertAdjacentElement("afterend", panel);
    }
    return panel;
  }
  async function refreshMfaState() {
    mfaVerified = false; mfaFactors = []; mfaAssurance = null;
    if (!currentUser) return;
    const [assurance, factors] = await Promise.all([
      db.auth.mfa.getAuthenticatorAssuranceLevel(),
      db.auth.mfa.listFactors()
    ]);
    if (assurance.error) throw assurance.error;
    if (factors.error) throw factors.error;
    mfaAssurance = assurance.data || null;
    mfaFactors = (factors.data?.totp || []).filter(x => x.status === "verified");
    mfaUnverifiedFactors = (factors.data?.totp || []).filter(x => x.status === "unverified");
    mfaVerified = mfaAssurance?.currentLevel === "aal2";
  }
  function renderMfaPanel() {
    const panel = ensureMfaPanel();
    if (!panel) return;
    if (!currentUser || !profile || recoveryMode) { panel.classList.add("hidden"); return; }
    const isAdminRole = profile.role === "admin" && profile.account_status === "active";
    const hasFactor = mfaFactors.length > 0;
    const mustBlock = isAdminRole && !mfaVerified;
    const shouldShow = mustBlock || !isAdminRole;
    panel.classList.toggle("hidden", !shouldShow);
    if (!shouldShow) return;
    panel.innerHTML = isAdminRole
      ? '<h3>Admin নিরাপত্তা যাচাই (MFA বাধ্যতামূলক)</h3><p class="muted">Admin Dashboard ব্যবহারের আগে Authenticator App দিয়ে MFA সক্রিয় ও যাচাই করুন।</p>'
      : '<h3>দুই-ধাপের নিরাপত্তা (ঐচ্ছিক MFA)</h3><p class="muted">Authenticator App যুক্ত করলে পাসওয়ার্ডের পাশাপাশি ৬ সংখ্যার কোড দিয়ে লগইন করতে পারবেন।</p>';
    if (mfaPendingFactor?.totp?.qr_code) {
      const qr = document.createElement("img");
      qr.alt = "Authenticator QR Code";
      qr.style.cssText = "max-width:220px;width:100%;display:block;margin:12px 0";
      qr.src = "data:image/svg+xml;charset=utf-8," + encodeURIComponent(mfaPendingFactor.totp.qr_code);
      panel.appendChild(qr);
      const secret = document.createElement("p");
      secret.className = "muted";
      secret.textContent = "QR স্ক্যান না হলে Secret: " + (mfaPendingFactor.totp.secret || "");
      panel.appendChild(secret);
      panel.insertAdjacentHTML("beforeend", '<label>Authenticator-এর ৬ সংখ্যার কোড</label><input id="nxMfaCode" inputmode="numeric" autocomplete="one-time-code" maxlength="6"><button class="primary" id="nxMfaVerifyEnroll" type="button">MFA সক্রিয় করুন</button>');
    } else if (mfaChallengeId) {
      panel.insertAdjacentHTML("beforeend", '<p>Authenticator App থেকে বর্তমান ৬ সংখ্যার কোড লিখুন।</p><label>৬ সংখ্যার কোড</label><input id="nxMfaCode" inputmode="numeric" autocomplete="one-time-code" maxlength="6"><button class="primary" id="nxMfaVerifyLogin" type="button">কোড যাচাই করুন</button>');
    } else if (!hasFactor && mfaUnverifiedFactors.length) {
      panel.insertAdjacentHTML("beforeend", '<p>আগের MFA setup অসম্পূর্ণ। Authenticator App-এ QR স্ক্যান করা থাকলে কোড যাচাই করে সেটআপ শেষ করুন।</p><button class="primary" id="nxMfaResumeEnroll" type="button">MFA Setup চালিয়ে যান</button><button class="light" id="nxMfaRestartEnroll" type="button">নতুন Secret দিয়ে আবার শুরু</button>');
    } else if (hasFactor && mfaVerified && !isAdminRole) {
      panel.insertAdjacentHTML("beforeend", '<p role="status">MFA সক্রিয় আছে। আপনার অ্যাকাউন্টে Authenticator App যুক্ত রয়েছে।</p><button class="light" id="nxMfaDisable" type="button">MFA বন্ধ করুন</button>');
    } else if (hasFactor) {
      panel.insertAdjacentHTML("beforeend", '<button class="primary" id="nxMfaStartChallenge" type="button">Authenticator Code দিন</button>');
    } else {
      panel.insertAdjacentHTML("beforeend", '<button class="primary" id="nxMfaEnroll" type="button">Authenticator App যুক্ত করুন</button>');
    }
    const error = document.createElement("p");
    error.id = "nxMfaError"; error.className = "muted"; error.setAttribute("aria-live","polite");
    panel.appendChild(error);
  }
  document.addEventListener("click", async e => {
    const button = e.target.closest("#nxMfaEnroll,#nxMfaVerifyEnroll,#nxMfaStartChallenge,#nxMfaVerifyLogin,#nxMfaDisable,#nxMfaResumeEnroll,#nxMfaRestartEnroll");
    if (!button) return;
    button.disabled = true;
    const showError = err => { const n=document.getElementById("nxMfaError"); if(n) n.textContent="MFA কাজ সম্পন্ন হয়নি: "+(err.message||String(err)); };
    try {
      if (button.id === "nxMfaDisable") {
        if (profile?.role === "admin") throw new Error("Admin MFA বন্ধ করা যাবে না।");
        if (!window.confirm("আপনি কি এই অ্যাকাউন্টের MFA বন্ধ করতে চান?")) { button.disabled=false; return; }
        const factorId=mfaFactors[0]?.id; if(!factorId) throw new Error("Verified Authenticator পাওয়া যায়নি।");
        const {error}=await db.auth.mfa.unenroll({factorId}); if(error) throw error;
        const {data,error:sessionError}=await db.auth.getSession(); if(sessionError) throw sessionError;
        await sync(data.session); say("MFA বন্ধ করা হয়েছে।",true);
      } else if (button.id === "nxMfaEnroll") {
        const {data,error}=await db.auth.mfa.enroll({factorType:"totp",friendlyName:"NEXORA Authenticator"});
        if(error) throw error;
        mfaPendingFactor=data; mfaChallengeId=null; renderMfaPanel();
      } else if (button.id === "nxMfaRestartEnroll") {
        const factorId=mfaUnverifiedFactors[0]?.id;
        if(!factorId) throw new Error("অসম্পূর্ণ Authenticator পাওয়া যায়নি।");
        if(!window.confirm("আগের অসম্পূর্ণ MFA Secret বাতিল করে নতুন Secret তৈরি করবেন? Authenticator App-এ পুরোনো NEXORA entry-টিও মুছে দিন।")) { button.disabled=false; return; }
        const removed=await db.auth.mfa.unenroll({factorId}); if(removed.error) throw removed.error;
        const enrolled=await db.auth.mfa.enroll({factorType:"totp",friendlyName:"NEXORA Authenticator"});
        if(enrolled.error) throw enrolled.error;
        mfaUnverifiedFactors=[]; mfaPendingFactor=enrolled.data; mfaChallengeId=null; mfaChallengeFactorId=null; renderMfaPanel();
      } else if (button.id === "nxMfaStartChallenge" || button.id === "nxMfaResumeEnroll") {
        const factorId=button.id === "nxMfaResumeEnroll" ? mfaUnverifiedFactors[0]?.id : mfaFactors[0]?.id;
        if(!factorId) throw new Error("Authenticator পাওয়া যায়নি।");
        const {data,error}=await db.auth.mfa.challenge({factorId}); if(error) throw error;
        mfaChallengeFactorId=factorId; mfaChallengeId=data.id; renderMfaPanel();
      } else {
        const rawCode=String(document.getElementById("nxMfaCode")?.value||"").trim();
        const code=rawCode.replace(/[০-৯]/g, d => String("০১২৩৪৫৬৭৮৯".indexOf(d))).replace(/[٠-٩]/g, d => String("٠١٢٣٤٥٦٧٨٩".indexOf(d)));
        if(!/^\d{6}$/.test(code)) throw new Error("৬ সংখ্যার কোড দিন (০-৯ বা 0-9)।");
        if(button.id==="nxMfaVerifyEnroll") {
          const factorId=mfaPendingFactor?.id; if(!factorId) throw new Error("MFA setup session পাওয়া যায়নি।");
          const challenge=await db.auth.mfa.challenge({factorId}); if(challenge.error) throw challenge.error;
          const {error}=await db.auth.mfa.verify({factorId,challengeId:challenge.data.id,code}); if(error) throw error;
          mfaPendingFactor=null;
        } else {
          const {error}=await db.auth.mfa.verify({factorId:mfaChallengeFactorId,challengeId:mfaChallengeId,code}); if(error) throw error;
          mfaChallengeId=null; mfaChallengeFactorId=null;
        }
        const {data,error}=await db.auth.getSession(); if(error) throw error;
        await sync(data.session);
        say("MFA যাচাই সফল হয়েছে।",true);
      }
    } catch(err) { showError(err); button.disabled=false; }
  });

  function render() {
    const current = document.getElementById("nxCurrent");
    const logged = document.getElementById("nxLogged");
    const admin = document.getElementById("nxAdmin");
    const loginView = document.getElementById("nxLoginView");
    const signupView = document.getElementById("nxSignupView");
    const forgotView = document.getElementById("nxForgotView");
    const recoveryView = document.getElementById("nxPasswordRecoveryView");
    if (!current) return;
    if (recoveryMode) {
      current.textContent = "নতুন পাসওয়ার্ড সেট করুন।";
      logged.classList.add("hidden");
      admin.classList.add("hidden");
      loginView?.classList.add("hidden");
      signupView?.classList.add("hidden");
      forgotView?.classList.add("hidden");
      recoveryView?.classList.remove("hidden");
      return;
    }
    recoveryView?.classList.add("hidden");
    if (!currentUser) {
      current.textContent = "আপনি লগইন করেননি।";
      logged.classList.add("hidden");
      admin.classList.add("hidden");
      document.getElementById("nxSignup").classList.remove("hidden");
      document.getElementById("nxLogin").classList.remove("hidden");
      document.getElementById("nxLoginView")?.classList.toggle("hidden", forgotMode);
      document.getElementById("nxSignupView")?.classList.add("hidden");
      document.getElementById("nxForgotView")?.classList.toggle("hidden", !forgotMode);
      return;
    }
    document.getElementById("nxSignup").classList.add("hidden");
    document.getElementById("nxLogin").classList.add("hidden");
    document.getElementById("nxLoginView")?.classList.add("hidden");
    document.getElementById("nxSignupView")?.classList.add("hidden");
    document.getElementById("nxForgotView")?.classList.add("hidden");
    logged.classList.remove("hidden");
    const roleForm = document.getElementById("nxRoleRequest");
    const roleStatus = document.getElementById("nxRoleRequestStatus");
    if (roleForm) roleForm.classList.toggle("hidden", !!pendingRoleRequest);
    if (roleStatus) {
      if (pendingRoleRequest) {
        const roleLabel = pendingRoleRequest.requested_role === "seller" ? "Seller" : "Porter";
        roleStatus.textContent = "আপনার " + roleLabel + " হওয়ার আবেদন পর্যালোচনাধীন। Admin-এর সিদ্ধান্ত না হওয়া পর্যন্ত নতুন আবেদন পাঠানোর প্রয়োজন নেই।";
        roleStatus.classList.remove("hidden");
      } else {
        roleStatus.textContent = "";
        roleStatus.classList.add("hidden");
      }
    }
    const p = profile || {};
    current.textContent = "লগইন: " + currentUser.email;
    document.getElementById("nxProfile").textContent =
      "নাম: " + (p.full_name || "—") + " | Role: " + (p.role || "অজানা") +
      " | Status: " + (p.account_status || "অজানা");
    const isActiveAdmin = p.role === "admin" && p.account_status === "active" && adminStaff?.is_active === true;
    renderMfaPanel();
    admin.classList.toggle("hidden", !isActiveAdmin || !mfaVerified);
    const adminIdentity = document.getElementById("nxAdminIdentity");
    if (adminIdentity) {
      const dept = adminStaff?.admin_level === "super_admin" ? "Super Admin" : (adminStaff?.department_key || "Assistant Admin");
      adminIdentity.textContent = "Admin ID: " + (adminStaff?.admin_code || "—") + " | দায়িত্ব: " + dept;
    }
    const adminManagePanel = document.getElementById("nxAdminManagement");
    if (adminManagePanel) adminManagePanel.classList.toggle("hidden", adminStaff?.admin_level !== "super_admin");
    if (isActiveAdmin && adminStaff?.admin_level === "super_admin") loadAdminManagement();
    if (isActiveAdmin) { loadAdminOperations(); loadAdminAuditLogs(); }
    const requestPanel = document.getElementById("nxRoleRequestsPanel");
    if (requestPanel) requestPanel.classList.toggle("hidden", adminStaff?.admin_level !== "super_admin");
    if (isActiveAdmin && adminStaff?.admin_level === "super_admin") loadRequests();
  }
  async function sync(session) {
    currentUser = session?.user || null;
    try {
      await loadProfile();
      if (currentUser && profile && profile.account_status === "active" && !recoveryMode) await refreshMfaState();
      else { mfaVerified=false; mfaFactors=[]; }
      if (currentUser && profile && profile.account_status !== "active" && !recoveryMode) {
        await db.auth.signOut({ scope: "global" });
        currentUser = null; profile = null; adminStaff = null;
        render();
        say("আপনার অ্যাকাউন্ট বর্তমানে সক্রিয় নয়। প্রবেশাধিকার বন্ধ করা হয়েছে।");
      } else render();
    }
    catch (e) { render(); say("প্রোফাইল লোড হয়নি: " + e.message); }
    window.dispatchEvent(new Event("nexora:auth-change"));
  }

  document.getElementById("nxSignup").addEventListener("submit", async e => {
    e.preventDefault();
    const form = e.currentTarget;
    setBusy(form, true); say("");
    const f = new FormData(form);
    try {
      const { data, error } = await db.auth.signUp({
        email: String(f.get("email")).trim(),
        password: String(f.get("password")),
        options: { data: {
          full_name: String(f.get("full_name")).trim(),
          role: String(f.get("role"))
        } }
      });
      if (error) throw error;
      if (data.session) await sync(data.session);
      say(data.session ? "অ্যাকাউন্ট তৈরি হয়েছে।" :
        "রেজিস্ট্রেশন হয়েছে। ইমেইলে confirmation link এলে সেটি খুলে নিশ্চিত করুন।", true);
      form.reset();
    } catch (err) { say("রেজিস্ট্রেশন ব্যর্থ: " + err.message); }
    finally { setBusy(form, false); }
  });

  document.getElementById("nxForgotOpen")?.addEventListener("click", () => {
    forgotMode = true;
    const loginEmail = document.querySelector('#nxLogin input[name="email"]')?.value || "";
    const emailInput = document.querySelector('#nxForgotForm input[name="email"]');
    if (emailInput) emailInput.value = loginEmail;
    render();
    document.querySelector('#accountSection .section-head h2').textContent = "Reset Password";
  });

  document.getElementById("nxForgotBack")?.addEventListener("click", () => {
    forgotMode = false;
    render();
    document.querySelector('#accountSection .section-head h2').textContent = "Login";
  });

  document.getElementById("nxForgotForm")?.addEventListener("submit", async e => {
    e.preventDefault();
    const form = e.currentTarget;
    setBusy(form, true); say("");
    const email = String(new FormData(form).get("email")).trim();
    try {
      const { error } = await db.auth.resetPasswordForEmail(email, {
        redirectTo: window.location.origin + window.location.pathname
      });
      if (error) throw error;
      say("যদি এই ইমেইলে NEXORA অ্যাকাউন্ট থাকে, পাসওয়ার্ড রিসেট লিংক পাঠানো হয়েছে। ইমেইলের লিংক খুলে নতুন পাসওয়ার্ড সেট করুন।", true);
    } catch (err) {
      say("রিসেট লিংক পাঠানো যায়নি: " + err.message);
    } finally { setBusy(form, false); }
  });

  document.getElementById("nxPasswordRecoveryForm")?.addEventListener("submit", async e => {
    e.preventDefault();
    const form = e.currentTarget;
    const f = new FormData(form);
    const password = String(f.get("password"));
    const confirm = String(f.get("confirm_password"));
    if (password.length < 8) return say("পাসওয়ার্ড কমপক্ষে ৮ অক্ষরের হতে হবে।");
    if (password !== confirm) return say("দুটি পাসওয়ার্ড মিলছে না।");
    setBusy(form, true); say("");
    try {
      const { error } = await db.auth.updateUser({ password });
      if (error) throw error;
      recoveryMode = false;
      forgotMode = false;
      await db.auth.signOut();
      await sync(null);
      document.querySelector('#accountSection .section-head h2').textContent = "Login";
      say("পাসওয়ার্ড সফলভাবে পরিবর্তন হয়েছে। নতুন পাসওয়ার্ড দিয়ে লগইন করুন।", true);
      form.reset();
    } catch (err) {
      say("পাসওয়ার্ড পরিবর্তন হয়নি: " + err.message);
    } finally { setBusy(form, false); }
  });

  document.getElementById("nxLogin").addEventListener("submit", async e => {
    e.preventDefault();
    const form = e.currentTarget;
    setBusy(form, true); say("");
    const f = new FormData(form);
    try {
      const { data, error } = await db.auth.signInWithPassword({
        email: String(f.get("email")).trim(), password: String(f.get("password"))
      });
      if (error) throw error;
      await sync(data.session); say("লগইন সফল হয়েছে।", true); form.reset();
    } catch (err) { say("লগইন ব্যর্থ: " + err.message); }
    finally { setBusy(form, false); }
  });

  // Social sign-in with Google or Facebook through Supabase Auth.
  document.querySelectorAll("[data-oauth-provider]").forEach(button => {
    button.addEventListener("click", async () => {
      const provider = button.dataset.oauthProvider;
      button.disabled = true;
      say("");
      try {
        const { error } = await db.auth.signInWithOAuth({
          provider,
          options: { redirectTo: window.location.origin + window.location.pathname }
        });
        if (error) throw error;
      } catch (err) {
        say((provider === "google" ? "Google" : "Facebook") + " Login চালু হয়নি: " + err.message);
        button.disabled = false;
      }
    });
  });

  document.getElementById("nxLogout").addEventListener("click", async () => {
    const { error } = await db.auth.signOut();
    if (error) say("Logout ব্যর্থ: " + error.message);
    else { await sync(null); say("লগআউট সম্পন্ন।", true); }
  });

  const testAccountForm = document.getElementById("nxTestAccountForm");
  testAccountForm?.addEventListener("submit", async e => {
    e.preventDefault();
    if (adminStaff?.admin_level !== "super_admin" || profile?.role !== "admin" || profile?.account_status !== "active") {
      return say("শুধু সক্রিয় Super Admin Test Account তৈরি করতে পারবেন।");
    }
    const form = e.currentTarget;
    const f = new FormData(form);
    const payload = {
      email: String(f.get("email") || "").trim(),
      password: String(f.get("password") || ""),
      role: String(f.get("role") || "buyer"),
      full_name: String(f.get("full_name") || "NEXORA Test User").trim()
    };
    if (!/^nexora-test\+[^@]+@example\.com$/i.test(payload.email)) {
      return say("শুধু nexora-test+label@example.com ঠিকানা ব্যবহার করুন।");
    }
    if (payload.password.length < 12) return say("অস্থায়ী পাসওয়ার্ড কমপক্ষে ১২ অক্ষরের হতে হবে।");
    setBusy(form, true); say("");
    try {
      const { data, error } = await db.functions.invoke("nexora-create-test-account", { body: payload });
      if (error) throw error;
      say("Test Account তৈরি হয়েছে: " + data.user.email + " | Role: " + data.user.role +
        " | Status: " + data.user.account_status + " | ID: " + data.user.id, true);
      form.reset();
    } catch (err) {
      say("Test Account তৈরি হয়নি: " + (err.message || "অজানা সমস্যা"));
    } finally { setBusy(form, false); }
  });

  const roleRequestForm = document.getElementById("nxRoleRequest");
  roleRequestForm?.addEventListener("submit", async e => {
    e.preventDefault();
    const form = e.currentTarget;
    if (!currentUser) return say("আগে লগইন করুন।");
    const role = new FormData(form).get("requested_role");
    if (!["seller", "porter"].includes(role)) return;
    setBusy(form, true);
    try {
      const { error } = await db.from("role_requests").insert({
        user_id: currentUser.id, requested_role: role, status: "pending"
      });
      if (error) {
        if (error.code === "23505" || String(error.message || "").includes("one_pending_role_request_per_user")) {
          const pending = await db.from("role_requests")
            .select("requested_role,status,created_at")
            .eq("user_id", currentUser.id)
            .eq("status", "pending")
            .order("created_at", { ascending: false })
            .limit(1)
            .maybeSingle();
          if (pending.error) throw pending.error;
          pendingRoleRequest = pending.data || null;
          render();
          say(pendingRoleRequest
            ? "আপনার " + (pendingRoleRequest.requested_role === "seller" ? "Seller" : "Porter") + " আবেদন আগে থেকেই পর্যালোচনাধীন আছে।"
            : "একটি আবেদন ইতিমধ্যে জমা হয়েছে। পৃষ্ঠাটি রিফ্রেশ করে দেখুন।", true);
          return;
        }
        throw error;
      }
      pendingRoleRequest = { requested_role: role, status: "pending" };
      form.reset();
      render();
      say("আপনার " + (role === "seller" ? "Seller" : "Porter") + " হওয়ার আবেদন Admin-এর কাছে পাঠানো হয়েছে।", true);
    } catch (err) { say("আবেদন জমা হয়নি: " + err.message); }
    finally { setBusy(form, false); }
  });


  const escapeHtml = value => String(value ?? "").replace(/[&<>"']/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
  async function loadAdminManagement() {
    const host = document.getElementById("nxAdminStaffList");
    const dept = document.getElementById("nxAssistantDepartment");
    const permissionHost = document.getElementById("nxAssistantPermissions");
    if (!host || !dept || !permissionHost || adminStaff?.admin_level !== "super_admin") return;
    const [departments, catalog, staff, grants] = await Promise.all([
      db.from("admin_departments").select("department_key,department_name").eq("is_assignable",true).order("department_name"),
      db.from("admin_permission_catalog").select("permission_key,permission_name,description,department_key,is_sensitive").order("permission_key"),
      db.from("admin_staff").select("user_id,admin_code,department_key,is_active,profiles(full_name)").eq("admin_level","assistant_admin").order("admin_code"),
      db.from("admin_permission_grants").select("admin_user_id,permission_key,is_allowed")
    ]);
    const failure = [departments,catalog,staff,grants].find(x=>x.error);
    if (failure) { host.textContent = "Admin তথ্য লোড হয়নি: " + failure.error.message; return; }
    dept.innerHTML = '<option value="">বিভাগ নির্বাচন করুন</option>' + (departments.data||[]).map(d=>'<option value="'+escapeHtml(d.department_key)+'">'+escapeHtml(d.department_name)+'</option>').join("");
    const drawPermissions = () => {
      const selected = dept.value;
      const rows = (catalog.data||[]).filter(c=>c.department_key===selected);
      permissionHost.innerHTML = rows.length ? rows.map(c=>'<label class="nx-permission-option"><input type="checkbox" name="assistant_permission" value="'+escapeHtml(c.permission_key)+'"> <span><b>'+escapeHtml(c.permission_name)+'</b><small>'+escapeHtml(c.description||"")+(c.is_sensitive?' • সংবেদনশীল অনুমতি':'')+'</small></span></label>').join("") : '<p class="muted">বিভাগ নির্বাচন করলে অনুমতিগুলো দেখা যাবে।</p>';
    };
    if (!dept.dataset.bound) { dept.addEventListener("change",drawPermissions); dept.dataset.bound="1"; }
    drawPermissions();
    host.innerHTML = (staff.data||[]).length ? staff.data.map(s=>{
      const count=(grants.data||[]).filter(g=>g.admin_user_id===s.user_id && g.is_allowed).length;
      return '<div class="offer"><b>'+escapeHtml(s.admin_code)+'</b> — '+escapeHtml(s.profiles?.full_name||"নাম নেই")+
        '<div class="muted">বিভাগ: '+escapeHtml(s.department_key)+' | অনুমতি: '+count+' | অবস্থা: '+(s.is_active?'সক্রিয়':'নিষ্ক্রিয়')+
        '<br>অ্যাকাউন্ট ইমেইল দিয়ে নিচের ফর্মে Update বা Deactivate করতে পারবেন।</div></div>';
    }).join("") : '<p class="muted">এখনো কোনো Assistant Admin নেই।</p>';
  }
  document.getElementById("nxAssistantAdminForm")?.addEventListener("submit", async e => {
    e.preventDefault();
    if (adminStaff?.admin_level !== "super_admin" || !currentUser) return say("শুধু Super Admin এই কাজ করতে পারবেন।");
    const form=e.currentTarget, f=new FormData(form);
    const action=String(f.get("action")), email=String(f.get("email")||"").trim();
    const department=String(f.get("department")||"");
    const permissions=[...form.querySelectorAll('input[name="assistant_permission"]:checked')].map(x=>x.value);
    if (!email) return say("Assistant Admin-এর নিবন্ধিত ইমেইল দিন।");
    if (action!=="deactivate" && !department) return say("বিভাগ নির্বাচন করুন।");
    setBusy(form,true); say("");
    try {
      const {data,error}=await db.rpc("manage_nexora_assistant_admin",{
        p_email:email,p_action:action,p_department_key:department||null,p_permissions:permissions
      });
      if(error) throw error;
      say("পরিবর্তন সংরক্ষিত হয়েছে। Admin ID: "+(data?.admin_code||"—"),true);
      form.reset(); drawAssistantPermissionReset();
      await loadAdminManagement();
    } catch(err) { say("Admin পরিবর্তন হয়নি: "+err.message); }
    finally { setBusy(form,false); }
  });
  function drawAssistantPermissionReset() {
    const host=document.getElementById("nxAssistantPermissions");
    if(host) host.innerHTML='<p class="muted">বিভাগ নির্বাচন করলে অনুমতিগুলো দেখা যাবে।</p>';
  }

  async function loadAdminOperations() {
    const root=document.getElementById("nxAdminOperations");
    if (!root || !currentUser || profile?.role!=="admin" || profile?.account_status!=="active" || adminStaff?.is_active!==true) return;
    root.classList.remove("hidden");
    const usersHost=document.getElementById("nxAdminUsers");
    const businessHost=document.getElementById("nxAdminBusinesses");
    const productsHost=document.getElementById("nxAdminProducts");
    const isSuper=adminStaff.admin_level==="super_admin";
    let permissions=new Set();
    if (!isSuper) {
      const {data,error}=await db.from("admin_permission_grants").select("permission_key").eq("admin_user_id",currentUser.id).eq("is_allowed",true);
      if(error){[usersHost,businessHost,productsHost].forEach(x=>x.textContent="অনুমতি যাচাই হয়নি: "+error.message);return;}
      permissions=new Set((data||[]).map(x=>x.permission_key));
    }
    const can=(key)=>isSuper||permissions.has(key);
    const safeDate=(v)=>v?escapeHtml(new Date(v).toLocaleString("bn-BD")):"—";
    if(can("users.view")||can("users.suspend")||can("users.restore")||can("users.cancel")) {
      const {data,error}=await db.from("profiles").select("id,full_name,role,account_status,created_at").in("role",["buyer","seller","porter"]).order("created_at",{ascending:false}).limit(20);
      if(error) usersHost.textContent="ব্যবহারকারী তালিকা লোড হয়নি: "+error.message;
      else if(!data?.length) usersHost.textContent="কোনো ব্যবহারকারী পাওয়া যায়নি।";
      else usersHost.innerHTML=data.map(u=>{
        let actions="";
        if(u.account_status==="active"&&can("users.suspend")) actions+='<button class="danger" data-admin-kind="user" data-admin-action="suspend" data-id="'+u.id+'">স্থগিত</button>';
        if(u.account_status==="suspended"&&can("users.restore")) actions+='<button class="primary" data-admin-kind="user" data-admin-action="restore" data-id="'+u.id+'">পুনরায় চালু</button>';
        if(u.account_status!=="cancelled"&&can("users.cancel")) actions+='<button class="light" data-admin-kind="user" data-admin-action="cancel" data-id="'+u.id+'">বাতিল</button>';
        return '<div class="offer"><b>'+escapeHtml(u.full_name||"নাম নেই")+'</b><div class="muted">Role: '+escapeHtml(u.role)+' | Status: '+escapeHtml(u.account_status)+'<br>নিবন্ধন: '+safeDate(u.created_at)+'</div><div class="form-actions">'+actions+'</div></div>';
      }).join("");
    } else usersHost.textContent="এই বিভাগের ব্যবহারকারী দেখার অনুমতি নেই।";

    if(can("businesses.view")||can("businesses.suspend")) {
      const {data,error}=await db.from("business_profiles").select("id,display_name,country,city,approval_status,created_at").order("created_at",{ascending:false}).limit(20);
      if(error) businessHost.textContent="ব্যবসার তালিকা লোড হয়নি: "+error.message;
      else if(!data?.length) businessHost.textContent="এখনো কোনো ব্যবসার আবেদন নেই।";
      else businessHost.innerHTML=data.map(b=>{
        let actions="";
        if(b.approval_status==="pending"&&isSuper) actions+='<button class="primary" data-admin-kind="business" data-admin-action="approve" data-id="'+b.id+'">Approve</button><button class="danger" data-admin-kind="business" data-admin-action="reject" data-id="'+b.id+'">Reject</button>';
        if(b.approval_status==="approved"&&can("businesses.suspend")) actions+='<button class="danger" data-admin-kind="business" data-admin-action="suspend" data-id="'+b.id+'">স্থগিত</button>';
        if(b.approval_status==="suspended"&&can("businesses.suspend")) actions+='<button class="primary" data-admin-kind="business" data-admin-action="restore" data-id="'+b.id+'">পুনরায় চালু</button>';
        return '<div class="offer"><b>'+escapeHtml(b.display_name)+'</b><div class="muted">'+escapeHtml([b.city,b.country].filter(Boolean).join(", "))+' | Status: '+escapeHtml(b.approval_status)+'<br>জমা: '+safeDate(b.created_at)+'</div><div class="form-actions">'+actions+'</div></div>';
      }).join("");
    } else businessHost.textContent="এই বিভাগের ব্যবসা দেখার অনুমতি নেই।";

    if(can("products.view")||can("products.suspend")||can("products.restore")) {
      const {data,error}=await db.from("products").select("id,product_code,product_name,category,listing_status,created_at").order("created_at",{ascending:false}).limit(20);
      if(error) productsHost.textContent="পণ্যের তালিকা লোড হয়নি: "+error.message;
      else if(!data?.length) productsHost.textContent="এখনো কোনো পণ্য জমা হয়নি।";
      else productsHost.innerHTML=data.map(p=>{
        let actions="";
        if(p.listing_status==="pending"&&isSuper) actions+='<button class="primary" data-admin-kind="product" data-admin-action="approve" data-id="'+p.id+'">Approve</button><button class="danger" data-admin-kind="product" data-admin-action="reject" data-id="'+p.id+'">Reject</button>';
        if(p.listing_status==="approved"&&can("products.suspend")) actions+='<button class="danger" data-admin-kind="product" data-admin-action="suspend" data-id="'+p.id+'">স্থগিত</button>';
        if(p.listing_status==="suspended"&&can("products.restore")) actions+='<button class="primary" data-admin-kind="product" data-admin-action="restore" data-id="'+p.id+'">পুনরায় চালু</button>';
        return '<div class="offer"><b>'+escapeHtml(p.product_name)+'</b><div class="muted">'+escapeHtml(p.product_code)+' | '+escapeHtml(p.category)+' | Status: '+escapeHtml(p.listing_status)+'<br>জমা: '+safeDate(p.created_at)+'</div><div class="form-actions">'+actions+'</div></div>';
      }).join("");
    } else productsHost.textContent="এই বিভাগের পণ্য দেখার অনুমতি নেই।";
  }

  async function loadAdminAuditLogs() {
    const host=document.getElementById("nxAdminAuditLogs");
    if(!host || !currentUser || profile?.role!=="admin" || profile?.account_status!=="active" || adminStaff?.is_active!==true) return;
    const isSuper=adminStaff.admin_level==="super_admin";
    if(!isSuper) {
      const {data,error}=await db.from("admin_permission_grants").select("permission_key").eq("admin_user_id",currentUser.id).eq("permission_key","security.audit_logs.view").eq("is_allowed",true).maybeSingle();
      if(error || !data) {host.textContent="Audit Log দেখার অনুমতি নেই।";return;}
    }
    const {data,error}=await db.from("admin_audit_logs")
      .select("id,actor_admin_code,action_key,target_type,target_id,reason,details,created_at")
      .order("created_at",{ascending:false}).limit(50);
    if(error) {host.textContent="Audit Log লোড হয়নি: "+error.message;return;}
    if(!data?.length) {host.textContent="এখনো কোনো Audit Log নেই।";return;}
    host.innerHTML=data.map(log=>{
      const details=log.details && typeof log.details==="object" ? JSON.stringify(log.details) : "";
      return '<div class="offer"><b>'+escapeHtml(log.action_key)+'</b>'+
        '<div class="muted">Admin: '+escapeHtml(log.actor_admin_code||"—")+
        ' | Target: '+escapeHtml(log.target_type||"—")+' / '+escapeHtml(log.target_id||"—")+
        '<br>সময়: '+escapeHtml(new Date(log.created_at).toLocaleString("bn-BD"))+
        (log.reason?'<br>কারণ: '+escapeHtml(log.reason):"")+
        (details?'<br>বিস্তারিত: '+escapeHtml(details.slice(0,700)):"")+
        '</div></div>';
    }).join("");
  }

  document.getElementById("nxAdminOperations")?.addEventListener("click", async e=>{
    const b=e.target.closest("button[data-admin-kind][data-admin-action][data-id]");
    if(!b) return;
    const kind=b.dataset.adminKind, action=b.dataset.adminAction, id=b.dataset.id;
    const labels={approve:"অনুমোদন",reject:"প্রত্যাখ্যান",suspend:"স্থগিত",restore:"পুনরায় চালু",cancel:"বাতিল"};
    if(!["user","business","product"].includes(kind)||!Object.hasOwn(labels,action)) return;
    const note=window.prompt("কারণ / Admin Note (ঐচ্ছিক):","") ;
    if(note===null) return;
    if(!window.confirm("আপনি কি নিশ্চিতভাবে "+labels[action]+" করতে চান?")) return;
    const buttons=b.closest(".offer")?.querySelectorAll("button")||[b];
    buttons.forEach(x=>x.disabled=true);
    const rpc=kind==="user"?"admin_manage_user":kind==="business"?"admin_moderate_business":"admin_moderate_product";
    const args=kind==="user"?{p_user_id:id,p_action:action,p_reason:note}:{[kind==="business"?"p_business_id":"p_product_id"]:id,p_action:action,p_note:note};
    try {
      const {error}=await db.rpc(rpc,args);
      if(error) throw error;
      say("পরিবর্তন সংরক্ষিত হয়েছে।",true);
      await loadAdminOperations();
    } catch(err) {
      say("পরিবর্তন হয়নি: "+(err.message||"অজানা সমস্যা"));
      buttons.forEach(x=>x.disabled=false);
    }
  });

  async function loadRequests() {
    const host = document.getElementById("nxRequests");
    if (!host) return;
    const { data, error } = await db.from("role_requests")
      .select("id,user_id,requested_role,created_at")
      .eq("status", "pending").order("created_at");
    if (error) { host.textContent = "আবেদন লোড হয়নি: " + error.message; return; }
    if (!data?.length) { host.textContent = "কোনো pending আবেদন নেই।"; return; }
    const userIds = [...new Set(data.map(r => r.user_id))];
    const { data: users, error: userError } = await db.from("profiles")
      .select("id,full_name,role,account_status")
      .in("id", userIds);
    if (userError) { host.textContent = "আবেদনকারীর তথ্য লোড হয়নি: " + userError.message; return; }
    const profileById = new Map((users || []).map(u => [u.id, u]));
    host.innerHTML = data.map(r => {
      const applicant = profileById.get(r.user_id);
      const roleLabel = r.requested_role === "seller" ? "Seller" : "Porter";
      const created = r.created_at ? new Date(r.created_at).toLocaleString("bn-BD") : "সময় পাওয়া যায়নি";
      return '<div class="offer"><b>' + escapeHtml(roleLabel) + ' আবেদন</b>' +
        '<div>আবেদনকারী: ' + escapeHtml(applicant?.full_name || "নাম পাওয়া যায়নি") + '</div>' +
        '<div class="muted">বর্তমান Role: ' + escapeHtml(applicant?.role || "অজানা") +
        ' | Account Status: ' + escapeHtml(applicant?.account_status || "অজানা") +
        '<br>আবেদনের সময়: ' + escapeHtml(created) + '</div>' +
        '<div class="form-actions"><button class="primary" data-id="' + r.id +
        '" data-decision="approved">Approve</button><button class="danger" data-id="' +
        r.id + '" data-decision="rejected">Reject</button></div></div>';
    }).join("");
  }
  document.getElementById("nxRequests")?.addEventListener("click", async e => {
    const b = e.target.closest("button[data-id]");
    if (!b || profile?.role !== "admin" || profile?.account_status !== "active" ||
        adminStaff?.admin_level !== "super_admin" || adminStaff?.is_active !== true) return;
    const decision = b.dataset.decision;
    if (!["approved", "rejected"].includes(decision)) return;
    const actionLabel = decision === "approved" ? "অনুমোদন" : "প্রত্যাখ্যান";
    if (!window.confirm("আপনি কি এই Role আবেদনটি " + actionLabel + " করতে নিশ্চিত? এই সিদ্ধান্ত আবেদনকারীর অ্যাকাউন্টে প্রভাব ফেলবে।")) return;
    const row = b.closest(".offer");
    const buttons = row?.querySelectorAll("button[data-id]") || [b];
    buttons.forEach(button => { button.disabled = true; });
    say("");
    try {
      const { error } = await db.rpc("review_role_request", {
        request_id: b.dataset.id, decision
      });
      if (error) throw error;
      say("আবেদনের সিদ্ধান্ত সংরক্ষিত হয়েছে।", true);
      await loadRequests();
    } catch (err) {
      say("সিদ্ধান্ত সংরক্ষণ হয়নি: " + (err.message || "অজানা সমস্যা"));
      buttons.forEach(button => { button.disabled = false; });
    }
  });

  // Keep database reads outside the Auth callback to avoid holding the Auth lock.
  db.auth.onAuthStateChange((event, session) => {
    if (event === "PASSWORD_RECOVERY") {
      recoveryMode = true;
      forgotMode = false;
      document.querySelector('#accountSection .section-head h2').textContent = "Set a New Password";
    }
    setTimeout(() => { sync(session); }, 0);
  });
  db.auth.getSession().then(({ data }) => sync(data.session));
  window.NEXORA_AUTH = { client: db, get user() { return currentUser; }, get profile() { return profile; }, get adminStaff() { return adminStaff; } };
})();
