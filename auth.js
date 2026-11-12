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
    admin.classList.toggle("hidden", !isActiveAdmin);
    const adminIdentity = document.getElementById("nxAdminIdentity");
    if (adminIdentity) {
      const dept = adminStaff?.admin_level === "super_admin" ? "Super Admin" : (adminStaff?.department_key || "Assistant Admin");
      adminIdentity.textContent = "Admin ID: " + (adminStaff?.admin_code || "—") + " | দায়িত্ব: " + dept;
    }
    const adminManagePanel = document.getElementById("nxAdminManagement");
    if (adminManagePanel) adminManagePanel.classList.toggle("hidden", adminStaff?.admin_level !== "super_admin");
    if (isActiveAdmin && adminStaff?.admin_level === "super_admin") loadAdminManagement();
    const requestPanel = document.getElementById("nxRoleRequestsPanel");
    if (requestPanel) requestPanel.classList.toggle("hidden", adminStaff?.admin_level !== "super_admin");
    if (isActiveAdmin && adminStaff?.admin_level === "super_admin") loadRequests();
  }
  async function sync(session) {
    currentUser = session?.user || null;
    try {
      await loadProfile();
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
    if (!b || profile?.role !== "admin" || profile?.account_status !== "active" || adminStaff?.admin_level !== "super_admin" || adminStaff?.is_active !== true) return;
    b.disabled = true;
    const { error } = await db.rpc("review_role_request", {
      request_id: b.dataset.id, decision: b.dataset.decision
    });
    if (error) say("সিদ্ধান্ত সংরক্ষণ হয়নি: " + error.message);
    else { say("আবেদনের সিদ্ধান্ত সংরক্ষিত হয়েছে।", true); await loadRequests(); }
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
