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

  const style = document.createElement("style");
  style.textContent = `
    #nexoraAccount { margin:18px 0; }
    #nexoraAccount .nx-grid { display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:12px; }
    #nexoraAccount .nx-message { padding:10px;border-radius:8px;background:#f3f6fa;margin-top:10px;white-space:pre-wrap; }
    #nexoraAccount button:disabled { opacity:.55;cursor:not-allowed; }
  `;
  document.head.appendChild(style);

  const nav = document.querySelector("header nav");
  const section = document.createElement("section");
  section.id = "accountSection";
  section.className = "section hidden";
  section.innerHTML = `
    <div class="section-head"><h2>Account & Login</h2><span class="tag">NEXORA Account</span></div>
    <div class="card" id="nexoraAccount">
      <p class="muted">Buyer, Seller, Porter ও Admin অ্যাকাউন্টের নিরাপদ প্রবেশ।</p>
      <div id="nxCurrent" class="offer">লোড হচ্ছে…</div>
      <div class="nx-grid">
        <form id="nxSignup">
          <h3>নতুন অ্যাকাউন্ট</h3>
          <label>পূর্ণ নাম</label><input name="full_name" required autocomplete="name">
          <label>অ্যাকাউন্টের ধরন</label>
          <select name="role" required>
            <option value="">ধরন নির্বাচন করুন</option>
            <option value="buyer">Buyer — ক্রেতা</option>
            <option value="seller">Seller — বিক্রেতা</option>
            <option value="porter">Porter — পরিবহনকারী</option>
          </select>
          <p class="muted">Buyer ও Seller নিবন্ধনের পর ব্যবহার করতে পারবেন; Seller-এর ব্যবসা/Listing প্রকাশের আগে Admin অনুমোদন লাগবে। Porter-এর কাজ শুরু করার আগে Admin অনুমোদন লাগবে।</p>
          <label>ইমেইল</label><input name="email" type="email" required autocomplete="email">
          <label>পাসওয়ার্ড (কমপক্ষে ৬ অক্ষর)</label><input name="password" type="password" minlength="6" required autocomplete="new-password">
          <div class="form-actions"><button class="primary" type="submit">Register</button></div>
        </form>
        <form id="nxLogin">
          <h3>লগইন</h3>
          <label>ইমেইল</label><input name="email" type="email" required autocomplete="email">
          <label>পাসওয়ার্ড</label><input name="password" type="password" required autocomplete="current-password">
          <div class="form-actions"><button class="secondary" type="submit">Login</button></div>
        </form>
      </div>
      <div id="nxLogged" class="hidden">
        <hr>
        <h3>অ্যাকাউন্টের অবস্থা</h3>
        <p id="nxProfile"></p>
        <form id="nxRoleRequest">
          <label>অ্যাকাউন্টের ধরন পরিবর্তনের আবেদন</label>
          <select name="requested_role" required>
            <option value="">Role নির্বাচন করুন</option><option value="seller">Seller</option><option value="porter">Porter</option>
          </select>
          <div class="form-actions"><button class="primary" type="submit">আবেদন পাঠান</button><button id="nxLogout" class="danger" type="button">Logout</button></div>
        </form>
      </div>
      <div id="nxAdmin" class="hidden">
        <hr><h3>Admin — Role আবেদন</h3><div id="nxRequests" class="muted">লোড হচ্ছে…</div>
      </div>
      <div id="nxMessage" class="nx-message" role="status" aria-live="polite"></div>
    </div>
  `;
  const main = document.querySelector("main");
  if (main) main.insertBefore(section, main.firstChild);

  if (nav) {
    const btn = document.createElement("button");
    btn.type = "button";
    btn.textContent = "Account / Login";
    btn.addEventListener("click", () => {
      // Show the dynamically added account section even if the site's
      // original showSection() only knows about the four marketplace sections.
      document.querySelectorAll("main .section").forEach(s => s.classList.add("hidden"));
      section.classList.remove("hidden");
      section.scrollIntoView({ behavior: "smooth", block: "start" });
    });
    nav.appendChild(btn);
  }

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
      document.getElementById("nxSignup").classList.remove("hidden");
      document.getElementById("nxLogin").classList.remove("hidden");
      return;
    }
    document.getElementById("nxSignup").classList.add("hidden");
    document.getElementById("nxLogin").classList.add("hidden");
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

  document.getElementById("nxRoleRequest").addEventListener("submit", async e => {
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
  document.getElementById("nxRequests").addEventListener("click", async e => {
    const b = e.target.closest("button[data-id]");
    if (!b || profile?.role !== "admin" || profile?.account_status !== "active") return;
    b.disabled = true;
    const { error } = await db.rpc("review_role_request", {
      request_id: b.dataset.id, decision: b.dataset.decision
    });
    if (error) say("সিদ্ধান্ত সংরক্ষণ হয়নি: " + error.message);
    else { say("আবেদনের সিদ্ধান্ত সংরক্ষিত হয়েছে।", true); await loadRequests(); }
  });

  db.auth.onAuthStateChange((_event, session) => { sync(session); });
  db.auth.getSession().then(({ data }) => sync(data.session));
  window.NEXORA_AUTH = { client: db, get user() { return currentUser; }, get profile() { return profile; } };
})();
