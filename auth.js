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
  let showLogin = false;

  const style = document.createElement("style");
  style.textContent = `
    #nexoraAccount { margin:18px 0; }
    #nexoraAccount .nx-grid { display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:12px; }
    #nexoraAccount .nx-message { padding:10px;border-radius:8px;background:#f3f6fa;margin-top:10px;white-space:pre-wrap; }
    #nexoraAccount button:disabled { opacity:.55;cursor:not-allowed; }
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
    if (!currentUser) { profile = null; return; }
    const { data, error } = await db.from("profiles")
      .select("id,full_name,role,account_status")
      .eq("id", currentUser.id).maybeSingle();
    if (error) throw error;
    profile = data;
  }
  function render() {
    const current = document.getElementById("nxCurrent");
    const logged = document.getElementById("nxLogged");
    const admin = document.getElementById("nxAdmin");
    if (!current) return;
    if (!currentUser) {
      current.textContent = "আপনি লগইন করেননি।";
      logged.classList.add("hidden");
      admin.classList.add("hidden");
      document.getElementById("nxSignup").classList.toggle("hidden", showLogin);
      document.getElementById("nxLogin").classList.toggle("hidden", !showLogin);
      document.getElementById("nxAuthSwitch").classList.toggle("hidden", showLogin);
      return;
    }
    document.getElementById("nxSignup").classList.add("hidden");
    document.getElementById("nxLogin").classList.add("hidden");
    document.getElementById("nxAuthSwitch").classList.add("hidden");
    logged.classList.remove("hidden");
    const p = profile || {};
    current.textContent = "লগইন: " + currentUser.email;
    document.getElementById("nxProfile").textContent =
      "নাম: " + (p.full_name || "—") + " | Role: " + (p.role || "অজানা") +
      " | Status: " + (p.account_status || "অজানা");
    admin.classList.toggle("hidden", !(p.role === "admin" && p.account_status === "active"));
    if (!admin.classList.contains("hidden")) loadRequests();
  }
  async function sync(session) {
    currentUser = session?.user || null;
    try { await loadProfile(); render(); }
    catch (e) { render(); say("প্রোফাইল লোড হয়নি: " + e.message); }
    window.dispatchEvent(new Event("nexora:auth-change"));
  }

  document.getElementById("nxShowLogin")?.addEventListener("click", () => { showLogin = true; render(); });
  document.getElementById("nxShowRegister")?.addEventListener("click", () => { showLogin = false; render(); });

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

  document.getElementById("nxLogout").addEventListener("click", async () => {
    const { error } = await db.auth.signOut();
    if (error) say("Logout ব্যর্থ: " + error.message);
    else { await sync(null); say("লগআউট সম্পন্ন।", true); }
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
      if (error) throw error;
      say("আপনার আবেদন Admin-এর কাছে পাঠানো হয়েছে।", true);
      form.reset();
    } catch (err) { say("আবেদন জমা হয়নি: " + err.message); }
    finally { setBusy(form, false); }
  });

  async function loadRequests() {
    const host = document.getElementById("nxRequests");
    const { data, error } = await db.from("role_requests")
      .select("id,user_id,requested_role,created_at")
      .eq("status", "pending").order("created_at");
    if (error) { host.textContent = "আবেদন লোড হয়নি: " + error.message; return; }
    if (!data?.length) { host.textContent = "কোনো pending আবেদন নেই।"; return; }
    host.innerHTML = data.map(r =>
      '<div class="offer"><b>' + r.requested_role + '</b> — ' + r.user_id +
      '<div class="form-actions"><button class="primary" data-id="' + r.id +
      '" data-decision="approved">Approve</button><button class="danger" data-id="' +
      r.id + '" data-decision="rejected">Reject</button></div></div>'
    ).join("");
  }
  document.getElementById("nxRequests")?.addEventListener("click", async e => {
    const b = e.target.closest("button[data-id]");
    if (!b || profile?.role !== "admin" || profile?.account_status !== "active") return;
    b.disabled = true;
    const { error } = await db.rpc("review_role_request", {
      request_id: b.dataset.id, decision: b.dataset.decision
    });
    if (error) say("সিদ্ধান্ত সংরক্ষণ হয়নি: " + error.message);
    else { say("আবেদনের সিদ্ধান্ত সংরক্ষিত হয়েছে।", true); await loadRequests(); }
  });

  // Keep database reads outside the Auth callback to avoid holding the Auth lock.
  db.auth.onAuthStateChange((_event, session) => {
    setTimeout(() => { sync(session); }, 0);
  });
  db.auth.getSession().then(({ data }) => sync(data.session));
  window.NEXORA_AUTH = { client: db, get user() { return currentUser; }, get profile() { return profile; } };
})();
