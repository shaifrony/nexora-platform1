/* NEXORA Marketplace — Supabase-backed MVP */
(() => {
  "use strict";
  const state = { products: [], demands: [], buyerDemands: [], business: null, businessMap: new Map(), offers: {} };
  const $ = (id) => document.getElementById(id);
  const client = () => window.NEXORA_AUTH?.client;
  const user = () => window.NEXORA_AUTH?.user;
  const profile = () => window.NEXORA_AUTH?.profile;
  const esc = (v) => String(v ?? "").replace(/[&<>"']/g, c => ({
    "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"
  })[c]);
  const say = (message, ok = false) => {
    const node = $("nxMessage");
    if (node) {
      node.textContent = message;
      node.style.color = ok ? "#087b5f" : "#b42318";
    } else if (message) alert(message);
  };
  const signedIn = () => Boolean(user()?.id);
  const activeBuyer = () => profile()?.role === "buyer" && profile()?.account_status === "active";
  const activeSeller = () => profile()?.role === "seller" && profile()?.account_status === "active";
  const currencyOK = (v) => /^[A-Z]{3}$/.test(String(v || "").toUpperCase());
  const setBusy = (form, busy) => form.querySelectorAll("button").forEach(b => b.disabled = busy);

  window.toggleProductForm = function() { $("productForm")?.classList.toggle("hidden"); };

  function ensureAdminApprovalPanel() {
    const host = $("nxAdmin");
    if (!host || $("nxMarketplaceAdmin")) return;
    const panel = document.createElement("div");
    panel.id = "nxMarketplaceAdmin";
    panel.innerHTML = `
      <hr><h3>Marketplace Approvals</h3>
      <h4>Pending Business Profiles</h4><div id="nxPendingBusinesses" class="muted">Loading…</div>
      <h4>Pending Product Listings</h4><div id="nxPendingProducts" class="muted">Loading…</div>`;
    host.appendChild(panel);
    panel.addEventListener("click", handleAdminDecision);
  }

  async function loadAdminActions() {
    const staff = window.NEXORA_AUTH?.adminStaff;
    const signedUser = user();
    const host = $("nxAdminPermissionActions");
    if (!host) return;
    if (!signedUser || profile()?.role !== "admin" || profile()?.account_status !== "active" ||
        !staff?.is_active || staff.admin_level !== "assistant_admin") {
      host.classList.add("hidden");
      return;
    }
    const { data: grants, error: grantError } = await client().from("admin_permission_grants")
      .select("permission_key").eq("admin_user_id", signedUser.id).eq("is_allowed", true);
    if (grantError) { host.textContent = "অনুমতি যাচাই করা যায়নি: " + grantError.message; host.classList.remove("hidden"); return; }
    const allowed = new Set((grants || []).map(g => g.permission_key));
    const productActions = ["products.suspend","products.restore","products.cancel"].some(k => allowed.has(k));
    const businessActions = allowed.has("businesses.suspend");
    const userActions = ["users.view","users.suspend","users.restore","users.cancel"].some(k => allowed.has(k));
    if (!productActions && !businessActions && !userActions) { host.classList.add("hidden"); return; }
    host.classList.remove("hidden");
    host.innerHTML = '<hr><h3>Assigned Tasks</h3><div id="nxAssistantUserActions"></div><div id="nxAssistantProductActions"></div><div id="nxAssistantBusinessActions"></div>';
    const userHost = $("nxAssistantUserActions");
    const productHost = $("nxAssistantProductActions");
    const businessHost = $("nxAssistantBusinessActions");
    if (userActions) {
      userHost.textContent = "ব্যবহারকারী লোড হচ্ছে…";
      const { data, error } = await client().from("profiles")
        .select("id,full_name,role,account_status,created_at")
        .in("role",["buyer","seller","porter"]).order("created_at",{ascending:false}).limit(100);
      if (error) userHost.textContent = "ব্যবহারকারী লোড হয়নি: " + error.message;
      else userHost.innerHTML = '<h4>User Management</h4>' + ((data||[]).map(u => {
        const buttons=[];
        if (allowed.has("users.suspend") && u.account_status==="active") buttons.push('<button class="danger" data-user-id="'+esc(u.id)+'" data-user-action="suspend">Suspend</button>');
        if (allowed.has("users.restore") && u.account_status==="suspended") buttons.push('<button class="primary" data-user-id="'+esc(u.id)+'" data-user-action="restore">Restore</button>');
        if (allowed.has("users.cancel") && u.account_status==="active") buttons.push('<button class="danger" data-user-id="'+esc(u.id)+'" data-user-action="cancel">Cancel</button>');
        return '<div class="offer"><b>'+esc(u.full_name||"নাম দেওয়া হয়নি")+'</b><p class="muted">Role: '+esc(u.role)+' | Status: '+esc(u.account_status)+'</p><div class="form-actions">'+buttons.join("")+'</div></div>';
      }).join("") || "কোনো Buyer, Seller বা Porter অ্যাকাউন্ট পাওয়া যায়নি।");
    }
    if (productActions) {
      const { data, error } = await client().from("products")
        .select("id,product_code,product_name,listing_status")
        .in("listing_status", ["approved","pending","suspended"]).order("created_at",{ascending:false}).limit(50);
      if (error) productHost.textContent = "পণ্য লোড হয়নি: " + error.message;
      else productHost.innerHTML = '<h4>পণ্য Listing</h4>' + ((data||[]).map(p => {
        const buttons = [];
        if (allowed.has("products.suspend") && ["approved","pending"].includes(p.listing_status)) buttons.push('<button class="danger" data-mod-type="product" data-mod-id="'+esc(p.id)+'" data-mod-action="suspend">Suspend</button>');
        if (allowed.has("products.restore") && p.listing_status==="suspended") buttons.push('<button class="primary" data-mod-type="product" data-mod-id="'+esc(p.id)+'" data-mod-action="restore">Restore</button>');
        if (allowed.has("products.cancel") && !["cancelled","rejected"].includes(p.listing_status)) buttons.push('<button class="danger" data-mod-type="product" data-mod-id="'+esc(p.id)+'" data-mod-action="cancel">Cancel</button>');
        return '<div class="offer"><b>'+esc(p.product_name)+'</b><p class="muted">'+esc(p.product_code)+' | '+esc(p.listing_status)+'</p><div class="form-actions">'+buttons.join("")+'</div></div>';
      }).join("") || "কোনো পরিচালনাযোগ্য পণ্য নেই।");
    } else productHost.textContent = "";
    if (businessActions) {
      const { data, error } = await client().from("business_profiles")
        .select("id,display_name,approval_status").in("approval_status",["approved","pending"]).order("created_at",{ascending:false}).limit(50);
      if (error) businessHost.textContent = "Business লোড হয়নি: " + error.message;
      else businessHost.innerHTML = '<h4>Business Listing</h4>' + ((data||[]).map(b =>
        '<div class="offer"><b>'+esc(b.display_name)+'</b><p class="muted">'+esc(b.approval_status)+'</p><div class="form-actions"><button class="danger" data-mod-type="business" data-mod-id="'+esc(b.id)+'" data-mod-action="suspend">Suspend</button></div></div>'
      ).join("") || "কোনো স্থগিতযোগ্য Business নেই।");
    } else businessHost.textContent = "";
  }

  async function handleAssistantModeration(e) {
    const userButton = e.target.closest("button[data-user-action]");
    if (userButton) {
      const staff = window.NEXORA_AUTH?.adminStaff;
      if (profile()?.role !== "admin" || profile()?.account_status !== "active" || staff?.admin_level !== "assistant_admin" || staff?.is_active !== true) return;
      const reason = prompt("এই User Management পদক্ষেপের কারণ লিখুন (কমপক্ষে ৫ অক্ষর):", "");
      if (!reason || reason.trim().length < 5) return say("কারণ না দিলে কাজটি করা যাবে না।");
      userButton.disabled = true;
      try {
        const { error } = await client().rpc("manage_nexora_user", {
          p_user_id: userButton.dataset.userId,
          p_action: userButton.dataset.userAction,
          p_reason: reason.trim()
        });
        if (error) throw error;
        say("ব্যবহারকারীর অ্যাকাউন্টের অবস্থা আপডেট হয়েছে।", true);
        await loadAdminActions();
      } catch (err) {
        userButton.disabled = false;
        say("User Management কাজটি করা যায়নি: " + err.message);
      }
      return;
    }
    const button = e.target.closest("button[data-mod-type]");
    if (!button) return;
    const staff = window.NEXORA_AUTH?.adminStaff;
    if (profile()?.role !== "admin" || profile()?.account_status !== "active" ||
        staff?.admin_level !== "assistant_admin" || staff?.is_active !== true) return;
    const reason = prompt("এই পদক্ষেপের কারণ লিখুন (কমপক্ষে ৫ অক্ষর):", "");
    if (!reason || reason.trim().length < 5) return say("কারণ না দিলে কাজটি করা যাবে না।");
    button.disabled = true;
    try {
      const { error } = await client().rpc("manage_marketplace_listing", {
        p_target_type: button.dataset.modType,
        p_target_id: button.dataset.modId,
        p_action: button.dataset.modAction,
        p_reason: reason.trim()
      });
      if (error) throw error;
      say("পরিবর্তন সফলভাবে সংরক্ষিত হয়েছে।", true);
      await loadAdminActions();
    } catch (err) {
      button.disabled = false;
      say("পরিবর্তন করা যায়নি: " + err.message);
    }
  }

  async function loadAdminQueue() {
    if (profile()?.role !== "admin" || profile()?.account_status !== "active" ||
        window.NEXORA_AUTH?.adminStaff?.admin_level !== "super_admin" ||
        window.NEXORA_AUTH?.adminStaff?.is_active !== true) return;
    ensureAdminApprovalPanel();
    const businessHost = $("nxPendingBusinesses");
    const productHost = $("nxPendingProducts");
    if (!businessHost || !productHost) return;
    const [businesses, products] = await Promise.all([
      client().from("business_profiles")
        .select("id,display_name,country,city,seller_id,created_at")
        .eq("approval_status", "pending").order("created_at"),
      client().from("products")
        .select("id,product_code,product_name,category,price,currency,seller_id,created_at")
        .eq("listing_status", "pending").order("created_at")
    ]);
    if (businesses.error) businessHost.textContent = "Business queue error: " + businesses.error.message;
    else businessHost.innerHTML = (businesses.data || []).map(b => `
      <div class="offer"><strong>${esc(b.display_name)}</strong>
      <p class="muted">${esc(b.country)}, ${esc(b.city)} | Seller ID: ${esc(b.seller_id)}</p>
      <div class="form-actions">
        <button class="primary" data-review-type="business" data-review-id="${esc(b.id)}" data-decision="approved">Approve</button>
        <button class="danger" data-review-type="business" data-review-id="${esc(b.id)}" data-decision="rejected">Reject</button>
      </div></div>`).join("") || "কোনো Pending Business Profile নেই।";
    if (products.error) productHost.textContent = "Product queue error: " + products.error.message;
    else productHost.innerHTML = (products.data || []).map(p => `
      <div class="offer"><strong>${esc(p.product_name)}</strong>
      <div class="form-actions">
        <button class="primary" data-review-type="product" data-review-id="${esc(p.id)}" data-decision="approved">Approve</button>
        <button class="danger" data-review-type="product" data-review-id="${esc(p.id)}" data-decision="rejected">Reject</button>
      </div></div>`).join("") || "কোনো Pending Product নেই।";
  }

  async function handleAdminDecision(e) {
    const button = e.target.closest("button[data-review-type]");
    if (!button || profile()?.role !== "admin" || profile()?.account_status !== "active" ||
        window.NEXORA_AUTH?.adminStaff?.admin_level !== "super_admin" ||
        window.NEXORA_AUTH?.adminStaff?.is_active !== true) return;
    const note = prompt("Admin note (ঐচ্ছিক):", "") || null;
    button.disabled = true;
    const type = button.dataset.reviewType;
    const approved = button.dataset.decision === "approved";
    const table = type === "business" ? "business_profiles" : "products";
    const statusColumn = type === "business" ? "approval_status" : "listing_status";
    const { error } = await client().from(table).update({
      [statusColumn]: approved ? "approved" : "rejected",
      admin_note: note,
      reviewed_by: user().id,
      reviewed_at: new Date().toISOString()
    }).eq("id", button.dataset.reviewId);
    if (error) { button.disabled = false; return say("Approval update failed: " + error.message); }
    say((type === "business" ? "Business Profile" : "Product") + (approved ? " approved." : " rejected."), true);
    await loadAdminQueue();
  }

  let currentSection = "market";
  let restoringSectionHistory = false;

  function ensurePageBackButtons() {
    document.querySelectorAll("main > section.section:not(#market)").forEach(section => {
      if (section.querySelector(":scope > .nx-page-back-row")) return;
      const row = document.createElement("div");
      row.className = "nx-page-back-row";
      row.innerHTML = '<button type="button" class="nx-page-back-button" data-nx-page-back><span aria-hidden="true">←</span> Back</button>';
      section.insertBefore(row, section.firstChild);
    });
  }

  function applySection(id) {
    document.body.classList.toggle("nx-buyer-dashboard-active", id === "buyerDashboard");
    document.body.classList.toggle("nx-demand-only-active", id === "postDemand");
    document.querySelectorAll("main section.section").forEach(s => s.classList.toggle("hidden", s.id !== id));
    currentSection = id;
    if (id === "market") loadProducts();
    if (id === "accountSection") loadAdminActions();
    if (id === "buyerDashboard") loadBuyerDashboard();
    if (id === "sellerDashboard") loadSellerDashboard();
    if (id === "porterDashboard") loadPorterDashboard();
    if (id === "accountSection") { loadAdminPorterOptions(); loadAdminLogisticsMonitor(); }
    window.scrollTo({ top: 0, behavior: "smooth" });
  }

  window.nexoraGoBack = function() {
    if (window.history.state?.nxPage && window.history.state.nxPage !== "market") {
      window.history.back();
      return;
    }
    if (currentSection !== "market") {
      applySection("market");
      window.history.replaceState({ nxPage: "market" }, "", window.location.href);
    } else {
      window.history.back();
    }
  };

  window.showSection = function(id, options = {}) {
    const role = profile()?.role;
    const activePorter = role === "porter" && profile()?.account_status === "active";
    const access = {
      buyer: signedIn() && activeBuyer(),
      seller: signedIn() && activeSeller(),
      porter: signedIn() && activePorter
    };
    const requiredRole = {
      postDemand: "buyer", buyerDashboard: "buyer",
      sellerDashboard: "seller", porterDashboard: "porter"
    }[id];
    if (requiredRole && !access[requiredRole]) {
      const hint = $("nxCurrent");
      const roleLabel = requiredRole === "buyer" ? "Buyer" : requiredRole === "seller" ? "Seller" : "Porter";
      if (hint) hint.textContent = signedIn()
        ? roleLabel + " Center ব্যবহার করতে অনুমোদিত Active " + roleLabel + " অ্যাকাউন্ট প্রয়োজন।"
        : roleLabel + " Center ব্যবহার করতে আগে লগইন করুন।";
      id = "accountSection";
    }
    if (!document.querySelector('main > section.section#' + CSS.escape(id))) return;
    if (!restoringSectionHistory && options.history !== false && id !== currentSection) {
      window.history.pushState({ nxPage: id }, "", window.location.href);
    }
    applySection(id);
  };

  document.addEventListener("click", event => {
    if (event.target.closest("[data-nx-page-back]")) window.nexoraGoBack();
  });

  if (!window.history.state?.nxPage) {
    window.history.replaceState({ nxPage: "market" }, "", window.location.href);
  }
  window.addEventListener("popstate", event => {
    const next = event.state?.nxPage || "market";
    restoringSectionHistory = true;
    window.showSection(next, { history: false });
    restoringSectionHistory = false;
  });
  ensurePageBackButtons();

  function ensureBusinessForm() {
    const host = $("sellerDashboard");
    if (!host || $("businessProfileCard")) return;
    const card = document.createElement("div");
    card.className = "card";
    card.id = "businessProfileCard";
    card.innerHTML = `
      <h3>Business Profile & Approval</h3>
      <p class="muted">একটি ব্যবসার একটি Business Profile এবং একটি Sales Center Address থাকবে। Marketplace-এ প্রকাশের আগে Admin অনুমোদন প্রয়োজন।</p>
      <div id="businessProfileStatus" class="offer">Business Profile লোড হচ্ছে…</div>
      <form id="businessProfileForm">
        <label>Business Display Name *</label><input name="display_name" required maxlength="160">
        <label>Business Description</label><textarea name="description"></textarea>
        <div class="grid">
          <div><label>Country *</label><input name="country" required></div>
          <div><label>City *</label><input name="city" required></div>
        </div>
        <label>Sales Center Address *</label><textarea name="sales_center_address" required></textarea>
        <div class="form-actions"><button class="primary" type="submit">Save Business Profile</button></div>
      </form>`;
    host.insertBefore(card, host.firstChild);
    $("businessProfileForm").addEventListener("submit", saveBusinessProfile);
  }

  async function loadBusinessProfile() {
    if (!signedIn() || !activeSeller()) return;
    const { data, error } = await client().from("business_profiles")
      .select("id,display_name,description,country,city,sales_center_address,approval_status,admin_note")
      .eq("seller_id", user().id).maybeSingle();
    if (error) throw error;
    state.business = data;
    const status = $("businessProfileStatus");
    const form = $("businessProfileForm");
    if (!status || !form) return;
    if (!data) {
      status.textContent = "এখনো Business Profile তৈরি হয়নি।";
      form.classList.remove("hidden");
      form.reset();
      return;
    }
    status.innerHTML = `Status: <strong>${esc(data.approval_status)}</strong>${data.admin_note ? " — " + esc(data.admin_note) : ""}`;
    for (const key of ["display_name","description","country","city","sales_center_address"]) {
      form.elements[key].value = data[key] || "";
    }
    form.classList.toggle("hidden", data.approval_status !== "pending");
  }

  async function saveBusinessProfile(e) {
    e.preventDefault();
    const form = e.currentTarget;
    if (!activeSeller()) return say("Business Profile তৈরি করতে সক্রিয় Seller অ্যাকাউন্ট প্রয়োজন।");
    const v = Object.fromEntries(new FormData(form));
    setBusy(form, true);
    try {
      const payload = {
        seller_id: user().id,
        display_name: v.display_name.trim(),
        description: v.description.trim() || null,
        country: v.country.trim(), city: v.city.trim(),
        sales_center_address: v.sales_center_address.trim()
      };
      const result = state.business
        ? await client().from("business_profiles").update(payload).eq("id", state.business.id)
        : await client().from("business_profiles").insert(payload);
      if (result.error) throw result.error;
      say("Business Profile জমা হয়েছে। Admin অনুমোদনের অপেক্ষায় থাকবে।", true);
      await loadBusinessProfile();
    } catch (err) { say("Business Profile সংরক্ষণ হয়নি: " + err.message); }
    finally { setBusy(form, false); }
  }

  async function loadProducts() {
    const host = $("productList");
    if (!host) return;
    host.textContent = "পণ্য লোড হচ্ছে…";
    // Always keep the homepage populated with clearly labelled sample ads,
    // even if the visitor has no session or the database is temporarily unavailable.
    if (!client()) {
      state.products = [];
      renderProducts();
      return;
    }
    const { data, error } = await client().from("products")
      .select("id,product_code,slug,product_name,category,image_urls,description,origin,specifications_quality,price,currency,listing_status,business_id")
      .eq("listing_status", "approved")
      .order("created_at", { ascending: false });
    if (error) {
      console.error("NEXORA products could not be loaded:", error.message);
      state.products = [];
      renderProducts();
      return;
    }
    state.products = data || [];
    const { data: businesses, error: businessError } = await client().from("public_businesses")
      .select("business_id,display_name,country,city");
    if (businessError) console.warn("NEXORA public business names unavailable:", businessError.message);
    state.businessMap = new Map((businesses || []).map(b => [b.business_id, b]));
    renderProducts();
    await loadDemands();
  }

  async function startProductChat(product) {
    if (!activeBuyer() || !signedIn()) return;
    if (!product || product.listing_status !== "approved") return say("এই পণ্যটি বর্তমানে যোগাযোগের অনুরোধ গ্রহণ করছে না।");
    const button = $("productContactSeller");
    const status = $("productInquiryStatus");
    if (button) { button.disabled = true; button.textContent = "Chat প্রস্তুত হচ্ছে…"; }
    try {
      const { data, error } = await client().rpc("create_product_inquiry", {
        p_product_id: product.id,
        p_message: null
      });
      if (error) throw error;
      const conversationId = typeof data === "string" ? data : data?.conversation_id || data?.id;
      if (!conversationId) throw new Error("Chat conversation ID পাওয়া যায়নি।");
      if (typeof window.NEXORA_OPEN_CONVERSATION !== "function") throw new Error("Chat এখন প্রস্তুত নয়।");
      await window.NEXORA_OPEN_CONVERSATION(conversationId);
    } catch (err) {
      if (status) status.textContent = "Chat খোলা যায়নি: " + (err.message || "অজানা সমস্যা");
      say("Chat খোলা যায়নি: " + (err.message || "অজানা সমস্যা"));
      if (button) { button.disabled = false; button.innerHTML = '<span aria-hidden="true">▣</span> Chat with Seller'; }
    }
  }
  function renderProducts() {
    const businessMap = state.businessMap;
    const host = $("productList");
    if (!host) return;
    const detailPanel = $("productDetailPanel");
    const requestedSlug = new URLSearchParams(window.location.search).get("product");
    if (requestedSlug && detailPanel) {
      $("nx-search-panel")?.classList.add("hidden");
      document.querySelector(".nx-search-panel")?.classList.add("hidden");
      host.classList.add("hidden");
      $("publicDemandBoard")?.classList.add("hidden");
      const selected = state.products.find(p => p.slug === requestedSlug);
      if (!selected) {
        detailPanel.classList.remove("hidden");
        detailPanel.innerHTML = '<p>পণ্যটি পাওয়া যায়নি অথবা বর্তমানে অনুমোদিত নয়।</p><a href="' + esc(window.location.pathname) + '">Marketplace-এ ফিরে যান</a>';
        return;
      }
      const business = state.businessMap.get(selected.business_id);
      const images = (selected.image_urls || []).filter(Boolean);
      detailPanel.classList.remove("hidden");
      detailPanel.innerHTML = `
        <p><a href="${esc(window.location.pathname)}">← Marketplace-এ ফিরে যান</a></p>
        <span class="tag">${esc(selected.category)}</span>
        <h2>${esc(selected.product_name)}</h2>
        ${images.length ? `<div class="grid">${images.map((src,i) => `<img class="product-image" src="${esc(src)}" alt="${esc(selected.product_name)} image ${i+1}" loading="lazy" onerror="this.style.display='none'">`).join("")}</div>` : ""}
        <p>${esc(selected.description)}</p>
        <h3>পণ্যের তথ্য</h3>
        <p><strong>উৎপত্তি:</strong> ${esc(selected.origin)}</p>
        <p><strong>Specifications & Quality:</strong> ${esc(selected.specifications_quality || "তথ্য দেওয়া হয়নি")}</p>
        <p class="price"><strong>পাইকারি মূল্য:</strong> ${esc(selected.price)} ${esc(selected.currency)}</p>
        <p><strong>Business Display Name:</strong> ${esc(business?.display_name || "Approved Seller")}</p>
        <p><strong>Product ID:</strong> ${esc(selected.product_code)}</p>
        
        <div id="productInquiryArea" class="card nx-product-contact"><h3>Seller-এর সঙ্গে যোগাযোগ</h3><div id="productInquiryControls"></div><p id="productInquiryStatus" class="muted" aria-live="polite"></p></div>
      `;
      const contactArea = $("productInquiryArea");
      if (contactArea) contactArea.classList.toggle("hidden", !(activeBuyer() && signedIn()));
      const controls = $("productInquiryControls");
      if (controls && activeBuyer() && signedIn()) {
        controls.innerHTML = '<button class="primary nx-contact-seller-button" type="button" id="productContactSeller"><span aria-hidden="true">▣</span> Chat with Seller</button>';
      }
      $("productContactSeller")?.addEventListener("click", () => startProductChat(selected));
      return;
    }
    if (detailPanel) detailPanel.classList.add("hidden");
    document.querySelector(".nx-search-panel")?.classList.remove("hidden");
    host.classList.remove("hidden");
    $("publicDemandBoard")?.classList.remove("hidden");
    const search = ($("productSearch")?.value || "").trim().toLowerCase();
    const category = $("categoryFilter")?.value || "";
    const minRaw = $("priceMin")?.value || "";
    const maxRaw = $("priceMax")?.value || "";
    const currency = $("priceCurrency")?.value || "";
    const quality = ($("qualityFilter")?.value || "").trim().toLowerCase();
    const origin = ($("originFilter")?.value || "").trim().toLowerCase();
    const spec = ($("specFilter")?.value || "").trim().toLowerCase();
    const min = minRaw === "" ? null : Number(minRaw);
    const max = maxRaw === "" ? null : Number(maxRaw);
    const rows = state.products.filter(p => {
      const searchable = [p.product_name,p.description,p.origin,p.specifications_quality].join(" ").toLowerCase();
      const productPrice = Number(p.price);
      const productCurrency = String(p.currency || "").toUpperCase();
      const matchesPrice = (min === null || (Number.isFinite(productPrice) && productPrice >= min)) &&
        (max === null || (Number.isFinite(productPrice) && productPrice <= max)) &&
        (!currency || productCurrency === currency);
      return searchable.includes(search) &&
        (!category || p.category === category) &&
        matchesPrice &&
        (!quality || String(p.specifications_quality || "").toLowerCase().includes(quality)) &&
        (!origin || String(p.origin || "").toLowerCase().includes(origin)) &&
        (!spec || String(p.specifications_quality || "").toLowerCase().includes(spec));
    });
    if ($("productCount")) $("productCount").textContent = rows.length + " Products";

    // Clearly labelled visual samples appear only until real approved listings exist.
    if (!state.products.length) {
      const demos = [
        {name:"Fresh Mango",category:"Food & Agriculture",description:"বাংলাদেশি আমের নমুনা পণ্য বিজ্ঞাপন।",origin:"Bangladesh",image:"https://images.unsplash.com/photo-1553279768-865429fa0078?auto=format&fit=crop&w=900&q=80"},
        {name:"Premium Cotton Fabric",category:"Textile & Garments",description:"কটন কাপড়ের নমুনা পণ্য বিজ্ঞাপন।",origin:"Bangladesh",image:"https://images.unsplash.com/photo-1521572163474-6864f9cf17ab?auto=format&fit=crop&w=900&q=80"},
        {name:"Handcrafted Decor",category:"Handicrafts",description:"হস্তশিল্পের নমুনা পণ্য বিজ্ঞাপন।",origin:"Bangladesh",image:"https://images.unsplash.com/photo-1513519245088-0e12902e5a38?auto=format&fit=crop&w=900&q=80"},
        {name:"Electronic Components",category:"Electronics",description:"ইলেকট্রনিক যন্ত্রাংশের নমুনা পণ্য বিজ্ঞাপন।",origin:"International",image:"https://images.unsplash.com/photo-1518770660439-4636190af475?auto=format&fit=crop&w=900&q=80"}
      ].filter(p =>
        (p.name + " " + p.description + " " + p.origin).toLowerCase().includes(search) &&
        (!category || p.category === category)
      );
      host.innerHTML = demos.length ? demos.map(p => `<article class="card">
        <img class="product-image" src="${esc(p.image)}" alt="${esc(p.name)}" loading="lazy" onerror="this.style.display='none'">
        <span class="tag">DEMO • নমুনা বিজ্ঞাপন</span>
        <span class="tag">${esc(p.category)}</span>
        <h3>${esc(p.name)}</h3>
        <p class="muted">${esc(p.description)}</p>
        <p class="muted">Origin: ${esc(p.origin)}</p>
        <p class="price">দাম জানতে যোগাযোগ করুন</p>
      </article>`).join("") : '<div class="card">কোনো নমুনা পণ্য মেলেনি।</div>';
      return;
    }

    host.innerHTML = rows.length ? rows.map(p => {
      const b = businessMap.get(p.business_id);
      const image = (p.image_urls || [])[0];
      return `<article class="card">
        ${image ? `<img class="product-image" src="${esc(image)}" alt="Product image" onerror="this.style.display='none'">` : ""}
        <span class="tag">${esc(p.category)}</span>
        <h3><a href="?product=${esc(encodeURIComponent(p.slug))}">${esc(p.product_name)}</a></h3><p class="muted">${esc(p.description)}</p>
        <p><a href="?product=${esc(encodeURIComponent(p.slug))}">পণ্যের বিস্তারিত দেখুন →</a></p>
        <p class="muted">Origin: ${esc(p.origin)}</p>
        <p class="muted">Business: ${esc(b?.display_name || "Approved Seller")}</p>
        <p class="price">${esc(p.price)} ${esc(p.currency)}</p>
        <p class="muted">Product ID: ${esc(p.product_code)}</p>
        <p class="muted">Permanent URL slug: ${esc(p.slug)}</p>
      </article>`;
    }).join("") : '<div class="card">কোনো অনুমোদিত পণ্য পাওয়া যায়নি।</div>';
  }

  async function loadBuyerDashboardProducts() {
    const host = $("buyerProductList");
    if (!host) return;
    if (!activeBuyer() || !signedIn()) { host.textContent = "সক্রিয় Buyer অ্যাকাউন্ট প্রয়োজন।"; return; }
    host.textContent = "অনুমোদিত পণ্য লোড হচ্ছে…";
    try {
      const { data, error } = await client().from("products").select("id,slug,product_code,product_name,category,image_urls,description,price,currency,origin,listing_status").eq("listing_status", "approved").order("created_at", { ascending: false }).limit(100);
      if (error) throw error;
      state.buyerProducts = data || [];
      renderBuyerDashboardProducts();
    } catch (err) { host.textContent = "পণ্য লোড হয়নি: " + (err.message || "অজানা সমস্যা"); }
  }
  function renderBuyerDashboardProducts() {
    const host = $("buyerProductList");
    if (!host) return;
    const term = ($("buyerProductSearch")?.value || "").trim().toLowerCase();
    const rows = (state.buyerProducts || []).filter(p => [p.product_name,p.category,p.description,p.origin].join(" ").toLowerCase().includes(term));
    if ($("buyerProductCount")) $("buyerProductCount").textContent = rows.length + " Products";
    if (!rows.length) { host.innerHTML = '<div class="card muted">এখনো কোনো Admin অনুমোদিত পণ্য নেই অথবা অনুসন্ধানের সঙ্গে মেলে এমন পণ্য পাওয়া যায়নি।</div>'; return; }
    host.innerHTML = rows.map(p => {
      const image = (p.image_urls || []).find(Boolean);
      return '<article class="card">' + (image ? '<img class="product-image" src="' + esc(image) + '" alt="' + esc(p.product_name) + '" loading="lazy" onerror="this.style.display=\'none\'">' : '') +
        '<span class="tag">' + esc(p.category) + '</span><h3>' + esc(p.product_name) + '</h3><p class="price">' + esc(p.price) + ' ' + esc(p.currency) + '</p><p class="muted">' + esc(p.origin || '') + '</p>' +
        '<p class="muted">' + esc(p.description || '') + '</p>' + (p.slug ? '<a href="' + esc(window.location.pathname) + '?product=' + encodeURIComponent(p.slug) + '">পণ্য বিস্তারিত দেখুন</a>' : '<span class="muted">Product ID: ' + esc(p.product_code) + '</span>') + '</article>';
    }).join("");
  }
  $("buyerProductSearch")?.addEventListener("input", renderBuyerDashboardProducts);
  $("buyerProductSearchButton")?.addEventListener("click", renderBuyerDashboardProducts);

  async function loadBuyerDashboard() {
    loadBuyerDashboardProducts();
    const host = $("buyerDemandList");
    if (!host) return;
    if (!signedIn() || !activeBuyer()) {
      host.textContent = "Buyer Dashboard ব্যবহার করতে সক্রিয় Buyer অ্যাকাউন্ট প্রয়োজন।";
      return;
    }
    host.textContent = "আপনার চাহিদা লোড হচ্ছে…";
    try {
      const { data, error } = await client().from("buyer_demands")
        .select("id,demand_code,product_name,category,description,specifications_quality,required_quantity,budget,currency,destination_country,destination_city,required_date,demand_status,created_at")
        .eq("buyer_id", user().id).order("created_at", { ascending: false });
      if (error) throw error;
      state.buyerDemands = data || [];
      const ids = state.buyerDemands.map(d => d.id);
      let offers = [];
      if (ids.length) {
        const result = await client().from("seller_offers")
          .select("id,demand_id,offer_price,currency,available_quantity,message,offer_status,created_at")
          .in("demand_id", ids).order("created_at", { ascending: false });
        if (result.error) throw result.error;
        offers = result.data || [];
      }
      renderBuyerDashboard(offers);
    } catch (err) {
      host.textContent = "Buyer Dashboard লোড হয়নি: " + (err.message || "অজানা সমস্যা");
    }
  }

  function renderBuyerDashboard(offers) {
    const host = $("buyerDemandList");
    const demands = state.buyerDemands || [];
    const offerMap = new Map();
    (offers || []).forEach(o => {
      if (!offerMap.has(o.demand_id)) offerMap.set(o.demand_id, []);
      offerMap.get(o.demand_id).push(o);
    });
    if ($("buyerDemandTotal")) $("buyerDemandTotal").textContent = String(demands.length);
    if ($("buyerDemandOpen")) $("buyerDemandOpen").textContent = String(demands.filter(d => d.demand_status === "open").length);
    if ($("buyerOfferTotal")) $("buyerOfferTotal").textContent = String((offers || []).length);
    if (!host) return;
    if (!demands.length) {
      host.innerHTML = '<div class="offer">আপনি এখনো কোনো Buyer Demand পোস্ট করেননি। নতুন চাহিদা পোস্ট করে শুরু করুন।</div>';
      return;
    }
    const labels = { open: "চলমান", closed: "বন্ধ", cancelled: "বাতিল" };
    host.innerHTML = demands.map(d => {
      const list = offerMap.get(d.id) || [];
      const offerHTML = list.length ? list.map(o =>
        '<div class="offer"><strong>বিক্রেতার Price Offer</strong>' +
        '<p class="price">' + esc(o.offer_price) + ' ' + esc(o.currency) + '</p>' +
        '<p class="muted">সরবরাহযোগ্য পরিমাণ: ' + esc(o.available_quantity) + '</p>' +
        (o.message ? '<p class="muted">' + esc(o.message) + '</p>' : '') +
        '<p class="muted">Offer Status: ' + esc(o.offer_status) + '</p></div>'
      ).join("") : '<p class="muted">এখনো কোনো Price Offer আসেনি।</p>';
      const actions = d.demand_status === "open" ?
        '<div class="form-actions"><button class="light" type="button" data-demand-status="closed" data-demand-id="' + esc(d.id) + '">চাহিদা বন্ধ করুন</button>' +
        '<button class="danger" type="button" data-demand-status="cancelled" data-demand-id="' + esc(d.id) + '">চাহিদা বাতিল করুন</button></div>' : '';
      return '<article class="card"><div class="section-head"><div><span class="tag">' + esc(d.category) +
        '</span><span class="tag">' + esc(labels[d.demand_status] || d.demand_status) + '</span></div><strong>' +
        esc(d.demand_code) + '</strong></div><h3>' + esc(d.product_name) + '</h3><p>' + esc(d.description) +
        '</p><p class="muted"><strong>স্পেসিফিকেশন:</strong> ' + esc(d.specifications_quality || "উল্লেখ করা হয়নি") +
        '</p><div class="grid"><div><p class="muted">পরিমাণ</p><strong>' + esc(d.required_quantity) +
        '</strong></div><div><p class="muted">বাজেট</p><strong>' +
        (d.budget === null ? "উল্লেখ করা হয়নি" : esc(d.budget + " " + d.currency)) +
        '</strong></div><div><p class="muted">গন্তব্য</p><strong>' + esc(d.destination_city) + ', ' +
        esc(d.destination_country) + '</strong></div></div><p><span class="demand-date">প্রয়োজনের তারিখ: ' +
        esc(d.required_date) + '</span></p><p><strong>' + list.length + 'টি Price Offer</strong></p>' +
        offerHTML + actions + '</article>';
    }).join("");
    host.querySelectorAll("button[data-demand-status][data-demand-id]").forEach(button => {
      button.addEventListener("click", () => updateBuyerDemandStatus(button.dataset.demandId, button.dataset.demandStatus));
    });
  }

  async function updateBuyerDemandStatus(demandId, nextStatus) {
    if (!activeBuyer() || !["closed","cancelled"].includes(nextStatus)) return;
    const label = nextStatus === "closed" ? "বন্ধ" : "বাতিল";
    if (!confirm("আপনি কি নিজের এই চাহিদাটি " + label + " করতে চান?")) return;
    try {
      const { data, error } = await client().from("buyer_demands").update({ demand_status: nextStatus })
        .eq("id", demandId).eq("buyer_id", user().id).eq("demand_status", "open")
        .select("id").maybeSingle();
      if (error) throw error;
      if (!data) throw new Error("চাহিদাটি পরিবর্তন করা যায়নি। এটি হয়তো ইতোমধ্যে পরিবর্তিত হয়েছে।");
      say("আপনার চাহিদার অবস্থা আপডেট হয়েছে।", true);
      await loadBuyerDashboard();
      if ($("market") && !$("market").classList.contains("hidden")) await loadDemands();
    } catch (err) {
      say("চাহিদার অবস্থা পরিবর্তন হয়নি: " + err.message);
    }
  }

  async function loadDemands() {
    const host = $("demandList");
    const publicDb = window.NEXORA_AUTH?.publicClient;
    if (!host || !publicDb) return;
    host.textContent = "প্রকাশ্য চাহিদা লোড হচ্ছে…";
    const { data, error } = await publicDb.from("public_buyer_demands")
      .select("id,demand_code,product_name,category,description,specifications_quality,required_quantity,budget,currency,destination_country,destination_city,required_date,demand_status,created_at")
      .eq("demand_status", "open").order("created_at", { ascending: false }).limit(100);
    if (error) { host.textContent = "প্রকাশ্য চাহিদা লোড হয়নি: " + error.message; return; }
    state.demands = data || [];
    renderDemands();
  }

  function renderDemands() {
    const host = $("demandList");
    if (!host) return;
    if (!state.demands.length) {
      host.innerHTML = '<div class="demand-card muted">এখনো কোনো প্রকাশ্য খোলা পাইকারি চাহিদা নেই।</div>';
      return;
    }
    host.innerHTML = state.demands.map(d => `<article class="demand-card">
      <span class="tag">${esc(d.category)}</span><span class="tag">চলমান</span>
      <h3>${esc(d.product_name)}</h3>
      <p class="demand-description">${esc(d.description)}</p>
      <div class="demand-meta">
        <span>পরিমাণ: <strong>${esc(d.required_quantity)}</strong></span>
        <span>গন্তব্য: <strong>${esc(d.destination_city)}, ${esc(d.destination_country)}</strong></span>
      </div>
      <p><span class="demand-date">প্রয়োজন: ${esc(d.required_date)}</span></p>
      <p class="muted" style="font-size:11px;margin:5px 0 0">Demand ID: ${esc(d.demand_code)}</p>
      ${activeSeller() ? `<button class="secondary" type="button" data-offer="${esc(d.id)}">Submit Price Offer</button>` : ""}
    </article>`).join("");
    host.querySelectorAll("button[data-offer]").forEach(b => b.addEventListener("click", () => submitOffer(b.dataset.offer)));
  }

  async function submitOffer(demandId) {
    if (!activeSeller()) return say("Offer দিতে সক্রিয় Seller অ্যাকাউন্ট প্রয়োজন।");
    if (!state.business || state.business.approval_status !== "approved") return say("Offer পাঠাতে Admin অনুমোদিত Business Profile প্রয়োজন।");
    const price = prompt("প্রস্তাবিত দাম লিখুন:");
    if (price === null || price.trim() === "" || !Number.isFinite(Number(price)) || Number(price) < 0) return;
    const currency = (prompt("Currency (USD / BDT / EUR):", "USD") || "").toUpperCase();
    if (!currencyOK(currency)) return say("Currency অবশ্যই ৩ অক্ষরের ISO কোড হতে হবে।");
    const quantity = prompt("আপনি কত পরিমাণ সরবরাহ করতে পারবেন?");
    if (!quantity?.trim()) return;
    const message = prompt("অতিরিক্ত বার্তা (ঐচ্ছিক):", "") || null;
    const { error } = await client().from("seller_offers").insert({
      demand_id: demandId, seller_id: user().id, offer_price: Number(price),
      currency, available_quantity: quantity.trim(), message
    });
    if (error) return say("Offer জমা হয়নি: " + error.message);
    say("Price Offer জমা হয়েছে।", true);
    await loadDemands();
  }

  async function loadSellerDashboard() {
    ensureBusinessForm();
    const status = $("businessProfileStatus");
    if (!signedIn() || !activeSeller()) {
      if (status) status.textContent = "Seller Dashboard ব্যবহার করতে সক্রিয় Seller হিসেবে লগইন করুন।";
      $("sellerProducts").textContent = "";
      $("matchedDemands").textContent = "";
      return;
    }
    try {
      await loadBusinessProfile();
      const { data, error } = await client().from("products")
        .select("id,product_code,product_name,category,origin,price,currency,listing_status")
        .eq("seller_id", user().id).order("created_at", { ascending: false });
      if (error) throw error;
      const products = data || [];
      const approvedCount = products.filter(p => p.listing_status === "approved").length;
      const pendingCount = products.filter(p => p.listing_status === "pending").length;
      const setMetric = (id, value) => { const node = $(id); if (node) node.textContent = String(value); };
      setMetric("nxSellerTotalProducts", products.length);
      setMetric("nxSellerApprovedProducts", approvedCount);
      setMetric("nxSellerPendingProducts", pendingCount);
      const businessStatus = state.business?.approval_status || "not_created";
      setMetric("nxSellerBusinessStatus", ({
        approved: "অনুমোদিত", pending: "পর্যালোচনাধীন",
        rejected: "প্রত্যাখ্যাত", not_created: "তৈরি হয়নি"
      })[businessStatus] || "অবস্থা অজানা");

      const productHost = $("sellerProducts");
      productHost.innerHTML = products.length ? products.map(p => `
        <article class="nx-seller-product-item" data-seller-product data-status="${esc(p.listing_status)}" data-search="${esc([p.product_name,p.category,p.product_code,p.origin].join(" ").toLowerCase())}">
          <div class="section-head"><strong>${esc(p.product_name)}</strong><span class="tag">${esc(({approved:"অনুমোদিত",pending:"পর্যালোচনাধীন",rejected:"প্রত্যাখ্যাত"})[p.listing_status] || "অবস্থা অজানা")}</span></div>
          <p class="muted">${esc(p.category)} | ${esc(p.origin)}</p>
          <p class="price">${esc(p.price)} ${esc(p.currency)}</p>
          <p class="muted">Product ID: ${esc(p.product_code)}</p>
          ${p.listing_status === "pending" ? `<button class="danger" type="button" data-delete-product="${esc(p.id)}">Delete pending product</button>` : ""}
        </article>`).join("") : '<p class="muted">এখনো কোনো পণ্য যোগ করা হয়নি। Add Product দিয়ে আপনার প্রথম পাইকারি পণ্য যোগ করুন।</p>';
      productHost.querySelectorAll("button[data-delete-product]").forEach(b => b.addEventListener("click", () => deleteProduct(b.dataset.deleteProduct)));

      const applyProductFilters = () => {
        const query = String($("nxSellerProductSearch")?.value || "").trim().toLowerCase();
        const selectedStatus = $("nxSellerProductStatus")?.value || "all";
        productHost.querySelectorAll("[data-seller-product]").forEach(card => {
          const matchesText = !query || (card.dataset.search || "").includes(query);
          const matchesStatus = selectedStatus === "all" || card.dataset.status === selectedStatus ||
            (selectedStatus === "rejected" && ["rejected","declined"].includes(card.dataset.status));
          card.hidden = !(matchesText && matchesStatus);
        });
      };
      const productSearch = $("nxSellerProductSearch");
      const productStatus = $("nxSellerProductStatus");
      if (productSearch) productSearch.oninput = applyProductFilters;
      if (productStatus) productStatus.onchange = applyProductFilters;
      applyProductFilters();

      const matchedHost = $("matchedDemands");
      if (!state.business || state.business.approval_status !== "approved") {
        matchedHost.innerHTML = '<p class="muted">Business Profile Admin অনুমোদনের পর প্রাসঙ্গিক Buyer Demand ও Offer পাঠানোর সুবিধা চালু হবে।</p>';
        return;
      }
      const approvedCategories = [...new Set(products.filter(p => p.listing_status === "approved").map(p => p.category).filter(Boolean))];
      if (!approvedCategories.length) {
        matchedHost.innerHTML = '<p class="muted">আপনার কোনো Admin অনুমোদিত পণ্য নেই। পণ্য অনুমোদিত হলে সংশ্লিষ্ট Category-এর Buyer Demand এখানে দেখানো হবে।</p>';
        return;
      }
      const { data: demands, error: demandError } = await client().from("buyer_demands")
        .select("id,demand_code,product_name,category,description,specifications_quality,required_quantity,destination_country,destination_city,required_date")
        .eq("demand_status", "open").in("category", approvedCategories)
        .order("created_at", { ascending: false });
      if (demandError) throw demandError;
      const { data: offers, error: offerError } = await client().from("seller_offers")
        .select("demand_id").eq("seller_id", user().id);
      if (offerError) throw offerError;
      const offeredDemandIds = new Set((offers || []).map(o => o.demand_id));
      matchedHost.innerHTML = (demands || []).map(d => `
        <div class="offer">
          <strong>${esc(d.product_name)}</strong>
          <p class="muted">${esc(d.category)} · Demand ID: ${esc(d.demand_code)}</p>
          <p>${esc(d.description)}</p>
          ${d.specifications_quality ? `<p class="muted">মান/বৈশিষ্ট্য: ${esc(d.specifications_quality)}</p>` : ""}
          <p class="muted">পরিমাণ: ${esc(d.required_quantity)} · গন্তব্য: ${esc([d.destination_city,d.destination_country].filter(Boolean).join(", "))}</p>
          <p><span class="demand-date">প্রয়োজন: ${esc(d.required_date)}</span></p>
          ${offeredDemandIds.has(d.id) ? '<span class="tag">Offer পাঠানো হয়েছে</span>' : `<button class="primary" type="button" data-offer-demand="${esc(d.id)}">প্রস্তাব পাঠান</button>`}
        </div>`).join("") || '<p class="muted">আপনার অনুমোদিত পণ্যের Category-এর সঙ্গে মেলে এমন কোনো খোলা Buyer Demand নেই।</p>';
      matchedHost.querySelectorAll("button[data-offer-demand]").forEach(b => b.addEventListener("click", () => submitOffer(b.dataset.offerDemand)));
    } catch (err) { say("Seller Dashboard লোড হয়নি: " + err.message); }
  }



  async function loadAdminPorterOptions() {
    const select=$("nxAdminPorterSelect");
    if(!select)return;
    select.innerHTML='<option value="">Porter তালিকা লোড হচ্ছে…</option>';
    try{
      const {data,error}=await client().rpc("list_active_nexora_porters_for_logistics");
      if(error)throw error;
      select.innerHTML='<option value="">Porter নির্বাচন করুন</option>'+(data||[]).map(p=>'<option value="'+esc(p.porter_id)+'">'+esc(p.full_name||"Porter")+'</option>').join("");
      if(!data?.length)select.innerHTML='<option value="">কোনো সক্রিয় Porter পাওয়া যায়নি</option>';
    }catch(err){
      select.innerHTML='<option value="">Logistics permission / database migration প্রয়োজন</option>';
      const status=$("nxAdminLogisticsStatus");if(status)status.textContent="Porter তালিকা লোড হয়নি: "+err.message;
    }
  }
  const logisticsStatusLabels = {
    assigned:"নতুন বরাদ্দ",accepted:"গ্রহণ করা হয়েছে",pickup_in_progress:"সংগ্রহ চলছে",
    picked_up:"পণ্য সংগ্রহ সম্পন্ন",in_transit:"পথে রয়েছে",delivered:"ডেলিভারি সম্পন্ন",
    declined:"প্রত্যাখ্যাত",failed:"সমস্যা হয়েছে",cancelled:"বাতিল"
  };
  const logisticsActiveStatuses=["accepted","pickup_in_progress","picked_up","in_transit"];
  async function loadAdminLogisticsMonitor(){
    const host=$("nxAdminLogisticsJobs"), historyHost=$("nxAdminLogisticsHistory");
    if(!host)return;
    if(!signedIn()||profile()?.role!=="admin"||profile()?.account_status!=="active"){
      host.textContent="শুধু সক্রিয় Admin অ্যাকাউন্টে এই অংশ ব্যবহার করা যাবে।";
      if(historyHost)historyHost.textContent="";
      return;
    }
    host.innerHTML='<p class="muted">ডেলিভারি কাজ লোড হচ্ছে…</p>';
    try{
      const {data:jobs,error}=await client().from("porter_delivery_jobs")
        .select("id,job_code,assigned_porter_id,package_description,package_count,status,pickup_city,pickup_country,dropoff_city,dropoff_country,scheduled_pickup_at,created_at,updated_at,porter_note")
        .order("created_at",{ascending:false}).limit(200);
      if(error)throw error;
      const rows=jobs||[];
      const count=statuses=>rows.filter(job=>statuses.includes(job.status)).length;
      const metric=(id,value)=>{const node=$(id);if(node)node.textContent=String(value);};
      metric("nxLogisticsTotal",rows.length);
      metric("nxLogisticsActive",count(logisticsActiveStatuses));
      metric("nxLogisticsDelivered",count(["delivered"]));
      metric("nxLogisticsIssues",count(["failed","declined"]));
      const porterIds=[...new Set(rows.map(job=>job.assigned_porter_id).filter(Boolean))];
      let porterNames={};
      if(porterIds.length){
        const {data:porters,error:porterError}=await client().from("profiles").select("id,full_name").in("id",porterIds);
        if(!porterError)porterNames=Object.fromEntries((porters||[]).map(p=>[p.id,p.full_name||"Porter"]));
      }
      const filter=$("nxAdminLogisticsFilter")?.value||"all";
      const filtered=rows.filter(job=>{
        if(filter==="all")return true;
        if(filter==="active")return logisticsActiveStatuses.includes(job.status);
        if(filter==="issues")return ["failed","declined"].includes(job.status);
        return job.status===filter;
      });
      host.innerHTML=filtered.length?filtered.map(job=>`
        <article class="nx-logistics-job">
          <div class="nx-logistics-job-head"><div><div class="nx-logistics-job-code">${esc(job.job_code)}</div><h5>${esc(job.package_description)}</h5></div><span class="nx-logistics-status">${esc(logisticsStatusLabels[job.status]||job.status)}</span></div>
          <p><strong>Porter:</strong> ${esc(porterNames[job.assigned_porter_id]||"Assigned Porter")} · <strong>প্যাকেজ:</strong> ${esc(job.package_count)}</p>
          <p><strong>সংগ্রহ:</strong> ${esc([job.pickup_city,job.pickup_country].filter(Boolean).join(", ")||"তথ্য নেই")} → <strong>গন্তব্য:</strong> ${esc([job.dropoff_city,job.dropoff_country].filter(Boolean).join(", ")||"তথ্য নেই")}</p>
          <p>বরাদ্দ: ${esc(new Date(job.created_at).toLocaleString("bn-BD"))}${job.scheduled_pickup_at?" · নির্ধারিত সংগ্রহ: "+esc(new Date(job.scheduled_pickup_at).toLocaleString("bn-BD")):""}</p>
          ${job.porter_note?'<p>সর্বশেষ নোট: '+esc(job.porter_note)+'</p>':""}
        </article>`).join(""):'<p class="muted">এই ফিল্টারে কোনো ডেলিভারি কাজ পাওয়া যায়নি।</p>';
      if(historyHost){
        const jobIds=rows.map(job=>job.id);
        if(!jobIds.length)historyHost.innerHTML='<p class="muted">এখনো কোনো ডেলিভারি ইতিহাস নেই।</p>';
        else{
          const {data:events,error:eventError}=await client().from("porter_delivery_job_events")
            .select("id,job_id,from_status,to_status,note,created_at")
            .in("job_id",jobIds).order("created_at",{ascending:false}).limit(100);
          if(eventError)throw eventError;
          const codes=Object.fromEntries(rows.map(job=>[job.id,job.job_code]));
          historyHost.innerHTML=events?.length?events.map(event=>`
            <article class="nx-logistics-event"><div><strong>${esc(codes[event.job_id]||"Delivery Job")} · ${esc(logisticsStatusLabels[event.to_status]||event.to_status)}</strong>
            ${event.from_status?'<p>আগের অবস্থা: '+esc(logisticsStatusLabels[event.from_status]||event.from_status)+'</p>':""}
            ${event.note?'<p>নোট: '+esc(event.note)+'</p>':""}</div><time>${esc(new Date(event.created_at).toLocaleString("bn-BD"))}</time></article>`).join(""):'<p class="muted">এখনো কোনো Status History নেই।</p>';
        }
      }
    }catch(err){
      host.innerHTML='<p class="muted">ডেলিভারি মনিটর লোড হয়নি: '+esc(err.message)+'</p>';
      if(historyHost)historyHost.innerHTML='<p class="muted">ইতিহাস লোড করা যায়নি।</p>';
    }
  }
  $("nxAdminLogisticsRefresh")?.addEventListener("click",loadAdminLogisticsMonitor);
  $("nxAdminLogisticsFilter")?.addEventListener("change",loadAdminLogisticsMonitor);
  $("nxAdminPorterJobForm")?.addEventListener("submit",async e=>{
    e.preventDefault();
    const form=e.currentTarget, v=Object.fromEntries(new FormData(form));
    const status=$("nxAdminLogisticsStatus");
    if(!v.assigned_porter_id)return;
    const args={
      p_assigned_porter_id:v.assigned_porter_id,
      p_package_description:v.package_description.trim(),
      p_package_count:Number(v.package_count),
      p_pickup_contact_name:v.pickup_contact_name.trim()||null,
      p_pickup_contact_phone:v.pickup_contact_phone.trim()||null,
      p_pickup_address:v.pickup_address.trim(),p_pickup_city:v.pickup_city.trim(),p_pickup_country:v.pickup_country.trim(),
      p_dropoff_contact_name:v.dropoff_contact_name.trim()||null,
      p_dropoff_contact_phone:v.dropoff_contact_phone.trim()||null,
      p_dropoff_address:v.dropoff_address.trim(),p_dropoff_city:v.dropoff_city.trim(),p_dropoff_country:v.dropoff_country.trim(),
      p_scheduled_pickup_at:v.scheduled_pickup_at?new Date(v.scheduled_pickup_at).toISOString():null
    };
    if(!Number.isInteger(args.p_package_count)||args.p_package_count<1)return say("প্যাকেজ সংখ্যা ১ বা তার বেশি পূর্ণসংখ্যা হতে হবে।");
    setBusy(form,true);
    try{
      const {data,error}=await client().rpc("admin_assign_porter_delivery_job",args);
      if(error)throw error;
      form.reset();
      if(status)status.textContent="ডেলিভারি কাজ বরাদ্দ হয়েছে। Job ID: "+data;
      say("Porter-কে ডেলিভারি কাজ বরাদ্দ হয়েছে।",true);
      await loadAdminPorterOptions(); await loadAdminLogisticsMonitor();
    }catch(err){if(status)status.textContent="কাজ বরাদ্দ হয়নি: "+err.message;say("কাজ বরাদ্দ হয়নি: "+err.message);}
    finally{setBusy(form,false);}
  });

  const porterStatusLabels = {
    assigned: "নতুন কাজ", accepted: "গ্রহণ করা হয়েছে",
    pickup_in_progress: "পণ্য সংগ্রহ চলছে", picked_up: "পণ্য সংগ্রহ সম্পন্ন",
    in_transit: "পথে রয়েছে", delivered: "ডেলিভারি সম্পন্ন",
    declined: "প্রত্যাখ্যাত", failed: "সমস্যা হয়েছে", cancelled: "বাতিল"
  };
  const porterActiveStatuses = ["accepted","pickup_in_progress","picked_up","in_transit"];
  function porterNextActions(status) {
    return ({
      assigned: [["accepted","কাজ গ্রহণ"],["declined","কাজ প্রত্যাখ্যান"]],
      accepted: [["pickup_in_progress","সংগ্রহ শুরু"]],
      pickup_in_progress: [["picked_up","পণ্য সংগ্রহ নিশ্চিত"]],
      picked_up: [["in_transit","পরিবহন শুরু"]],
      in_transit: [["delivered","ডেলিভারি সম্পন্ন"],["failed","সমস্যা রিপোর্ট"]]
    })[status] || [];
  }
  async function updatePorterJob(jobId, nextStatus) {
    const prompts = {
      accepted: "এই ডেলিভারি কাজটি গ্রহণ করছেন?",
      declined: "এই কাজটি প্রত্যাখ্যান করার কারণ লিখুন:",
      pickup_in_progress: "পণ্য সংগ্রহ শুরু করার বিষয়টি নিশ্চিত করুন।",
      picked_up: "পণ্যটি সংগ্রহ করেছেন—নিশ্চিত করুন।",
      in_transit: "পণ্যটি গন্তব্যের উদ্দেশ্যে পাঠানো হয়েছে—নিশ্চিত করুন।",
      delivered: "ডেলিভারি সম্পন্ন হওয়ার সংক্ষিপ্ত প্রমাণ/নোট লিখুন:",
      failed: "ডেলিভারিতে কী সমস্যা হয়েছে তা লিখুন:"
    };
    const promptText = prompts[nextStatus] || "নোট (ঐচ্ছিক):";
    const note = window.prompt(promptText, "");
    if (note === null) return;
    if (["declined","delivered","failed"].includes(nextStatus) && note.trim().length < 5)
      return say("এই স্ট্যাটাসের জন্য কমপক্ষে ৫ অক্ষরের নোট প্রয়োজন।");
    try {
      const { error } = await client().rpc("porter_update_delivery_job_status", {
        p_job_id: jobId, p_new_status: nextStatus, p_note: note.trim() || null
      });
      if (error) throw error;
      say("ডেলিভারি কাজের অবস্থা আপডেট হয়েছে।", true);
      await loadPorterDashboard();
    } catch (err) { say("স্ট্যাটাস আপডেট হয়নি: " + err.message); }
  }
  async function loadPorterDashboard() {
    const host = $("nxPorterJobs");
    if (!host) return;
    if (!signedIn() || profile()?.role !== "porter" || profile()?.account_status !== "active") {
      host.textContent = "সক্রিয় অনুমোদিত Porter অ্যাকাউন্ট প্রয়োজন।";
      return;
    }
    host.innerHTML = '<p class="muted">ডেলিভারি কাজ লোড হচ্ছে…</p>';
    try {
      const { data, error } = await client().from("porter_delivery_jobs")
        .select("id,job_code,status,pickup_contact_name,pickup_contact_phone,pickup_address,pickup_city,pickup_country,dropoff_contact_name,dropoff_contact_phone,dropoff_address,dropoff_city,dropoff_country,package_description,package_count,scheduled_pickup_at,created_at,porter_note")
        .eq("assigned_porter_id", user().id).order("created_at", {ascending:false});
      if (error) throw error;
      const jobs = data || [];
      const historyHost = $("nxPorterHistory");
      if (historyHost) {
        if (!jobs.length) {
          historyHost.innerHTML = '<p class="muted">এখনো কোনো ডেলিভারি ইতিহাস নেই।</p>';
        } else {
          try {
            const { data: events, error: historyError } = await client().from("porter_delivery_job_events")
              .select("id,job_id,from_status,to_status,note,created_at")
              .in("job_id", jobs.map(job => job.id))
              .order("created_at", { ascending: false }).limit(50);
            if (historyError) throw historyError;
            const jobCodes = Object.fromEntries(jobs.map(job => [job.id, job.job_code]));
            historyHost.innerHTML = events?.length ? events.map(event => `
              <article class="nx-porter-history-item">
                <div><strong>${esc(jobCodes[event.job_id] || "Delivery Job")} · ${esc(porterStatusLabels[event.to_status] || event.to_status)}</strong>
                ${event.note ? '<p>নোট: '+esc(event.note)+'</p>' : ""}
                ${event.from_status ? '<p>আগের অবস্থা: '+esc(porterStatusLabels[event.from_status] || event.from_status)+'</p>' : ""}</div>
                <time>${esc(new Date(event.created_at).toLocaleString("bn-BD"))}</time>
              </article>`).join("") : '<p class="muted">এখনো কোনো স্ট্যাটাস পরিবর্তনের রেকর্ড নেই।</p>';
          } catch (historyError) {
            historyHost.innerHTML = '<p class="muted">ইতিহাস এখন লোড করা যাচ্ছে না: '+esc(historyError.message)+'</p>';
          }
        }
      }
      const count = (statuses) => jobs.filter(j => statuses.includes(j.status)).length;
      const setMetric = (id,value) => {const n=$(id);if(n)n.textContent=String(value);};
      setMetric("nxPorterAssigned",count(["assigned"]));
      setMetric("nxPorterActive",count(porterActiveStatuses));
      setMetric("nxPorterDelivered",count(["delivered"]));
      setMetric("nxPorterTotal",jobs.length);
      const labelAddress = (address,city,country) => [address,city,country].filter(Boolean).map(esc).join(", ") || "তথ্য দেওয়া হয়নি";
      host.innerHTML = jobs.length ? jobs.map(job => {
        const actions = porterNextActions(job.status).map(([status,label]) =>
          '<button type="button" class="'+(status==="declined"||status==="failed"?"danger":"primary")+'" data-porter-job="'+esc(job.id)+'" data-next-status="'+status+'">'+label+'</button>'
        ).join("");
        return `<article class="nx-porter-job" data-porter-card data-status="${esc(job.status)}">
          <div class="nx-porter-job-head"><div><div class="nx-porter-job-code">${esc(job.job_code)}</div><h3>${esc(job.package_description || "পণ্য পরিবহন")}</h3></div><span class="nx-porter-job-status">${esc(porterStatusLabels[job.status] || "অবস্থা অজানা")}</span></div>
          <div class="nx-porter-route">
            <div><strong>পণ্য সংগ্রহ</strong><p>${labelAddress(job.pickup_address,job.pickup_city,job.pickup_country)}</p>${job.pickup_contact_name?'<p>যোগাযোগ: '+esc(job.pickup_contact_name)+'</p>':''}${job.pickup_contact_phone?'<p>ফোন: '+esc(job.pickup_contact_phone)+'</p>':''}</div>
            <div><strong>ডেলিভারি গন্তব্য</strong><p>${labelAddress(job.dropoff_address,job.dropoff_city,job.dropoff_country)}</p>${job.dropoff_contact_name?'<p>প্রাপক: '+esc(job.dropoff_contact_name)+'</p>':''}${job.dropoff_contact_phone?'<p>ফোন: '+esc(job.dropoff_contact_phone)+'</p>':''}</div>
          </div>
          <p class="muted">প্যাকেজ সংখ্যা: ${esc(job.package_count ?? "উল্লেখ নেই")} ${job.scheduled_pickup_at ? " · সংগ্রহের সময়: "+esc(new Date(job.scheduled_pickup_at).toLocaleString("bn-BD")) : ""}</p>
          ${job.porter_note ? '<p class="muted">নোট: '+esc(job.porter_note)+'</p>' : ""}
          <div class="nx-porter-job-actions">${actions || '<span class="muted">এই কাজের জন্য এখন কোনো পদক্ষেপ নেই।</span>'}</div>
        </article>`;
      }).join("") : '<div class="offer"><strong>এখনো কোনো কাজ বরাদ্দ হয়নি</strong><p class="muted">Admin আপনাকে পরিবহন কাজ বরাদ্দ করলে এখানে দেখা যাবে।</p></div>';
      const applyFilter = () => {
        const filter = $("nxPorterJobFilter")?.value || "all";
        host.querySelectorAll("[data-porter-card]").forEach(card => {
          const status=card.dataset.status;
          const group=status==="assigned"?"assigned":porterActiveStatuses.includes(status)?"active":status;
          card.hidden=filter!=="all" && filter!==group;
        });
      };
      const filterEl=$("nxPorterJobFilter");
      if(filterEl)filterEl.onchange=applyFilter;
      applyFilter();
      host.querySelectorAll("button[data-porter-job]").forEach(button => button.addEventListener("click",() => updatePorterJob(button.dataset.porterJob,button.dataset.nextStatus)));
    } catch (err) {
      const missing = /porter_delivery_jobs|schema cache|does not exist/i.test(err.message || "");
      host.innerHTML = missing
        ? '<div class="offer"><strong>Porter Database প্রস্তুত হয়নি</strong><p class="muted">নিরাপদ Delivery Workflow migration এখনো ডাটাবেজে প্রয়োগ করা হয়নি। সেটি অনুমোদিতভাবে প্রয়োগের পর কাজের তালিকা চালু হবে।</p></div>'
        : '<p class="muted">ডেলিভারি কাজ লোড হয়নি: '+esc(err.message)+'</p>';
    }
  }
  $("nxPorterRefresh")?.addEventListener("click",loadPorterDashboard);

  async function deleteProduct(id) {
    if (!confirm("এই pending পণ্যটি মুছে ফেলতে চান?")) return;
    const { error } = await client().from("products").delete().eq("id", id);
    if (error) return say("পণ্য মুছতে সমস্যা: " + error.message);
    say("পণ্য মুছে ফেলা হয়েছে।", true);
    await loadSellerDashboard(); await loadProducts();
  }

  $("productForm")?.addEventListener("submit", async e => {
    e.preventDefault();
    const form = e.currentTarget;
    if (!activeSeller()) return say("পণ্য যোগ করতে সক্রিয় Seller হিসেবে লগইন করুন।");
    if (!state.business || state.business.approval_status !== "approved") return say("পণ্য যোগ করার আগে Admin-এর Business Profile অনুমোদন প্রয়োজন।");
    const v = Object.fromEntries(new FormData(form));
    const images = String(v.images || "").split(/\r?\n/).map(x => x.trim()).filter(Boolean);
    if (images.some(x => !/^https:\/\//i.test(x))) return say("প্রতিটি Product Image URL অবশ্যই HTTPS হতে হবে।");
    if (!Number.isFinite(Number(v.price)) || Number(v.price) <= 0) return say("পাইকারি মূল্য শূন্যের বেশি হতে হবে।");
    setBusy(form, true);
    try {
      const { error } = await client().from("products").insert({
        business_id: state.business.id, seller_id: user().id,
        product_name: v.name.trim(), category: v.category, image_urls: images,
        description: v.description.trim(), origin: v.origin.trim(),
        specifications_quality: v.specifications.trim(),
        price: Number(v.price), currency: String(v.currency).toUpperCase(),
      });
      if (error) throw error;
      form.reset(); form.classList.add("hidden");
      say("পণ্য জমা হয়েছে। Marketplace-এ প্রকাশের আগে Admin অনুমোদন লাগবে।", true);
      await loadSellerDashboard(); await loadProducts();
    } catch (err) { say("পণ্য সংরক্ষণ হয়নি: " + err.message); }
    finally { setBusy(form, false); }
  });

  $("demandForm")?.addEventListener("submit", async e => {
    e.preventDefault();
    const form = e.currentTarget;
    if (!activeBuyer()) return say("চাহিদা প্রকাশ করতে সক্রিয় Buyer হিসেবে লগইন করুন।");
    const v = Object.fromEntries(new FormData(form));
    if (v.budget !== "" && (!Number.isFinite(Number(v.budget)) || Number(v.budget) < 0)) return say("সঠিক Budget লিখুন।");
    setBusy(form, true);
    try {
      const { error } = await client().from("buyer_demands").insert({
        buyer_id: user().id, product_name: v.name.trim(), category: v.category,
        description: v.description.trim(), specifications_quality: v.specifications.trim(),
        required_quantity: v.quantity.trim(), budget: v.budget === "" ? null : Number(v.budget), currency: String(v.currency).toUpperCase(),
        destination_country: v.country.trim(), destination_city: v.destination.trim(), required_date: v.requiredDate
      });
      if (error) throw error;
      form.reset(); say("Buyer Demand প্রকাশিত হয়েছে।", true); showSection("buyerDashboard");
    } catch (err) { say("Demand প্রকাশ হয়নি: " + err.message); }
    finally { setBusy(form, false); }
  });

  document.querySelectorAll("[data-nx-category]").forEach(button => {
    button.addEventListener("click", () => {
      const category = button.getAttribute("data-nx-category") || "";
      const select = $("categoryFilter");
      if (!select) return;
      select.value = category;
      renderProducts();
      document.querySelector(".nx-search-panel")?.scrollIntoView({ behavior: "smooth", block: "center" });
    });
  });

  ["productSearch","categoryFilter","priceMin","priceMax","priceCurrency","qualityFilter","originFilter","specFilter"].forEach(id => {
    const el = $(id);
    if (!el) return;
    el.addEventListener(el.tagName === "SELECT" ? "change" : "input", () => renderProducts());
  });
  $("resetProductFilters")?.addEventListener("click", () => {
    ["productSearch","priceMin","priceMax","qualityFilter","originFilter","specFilter"].forEach(id => { if ($(id)) $(id).value = ""; });
    ["categoryFilter","priceCurrency"].forEach(id => { if ($(id)) $(id).value = ""; });
    if ($("filterHint")) $("filterHint").textContent = "সব ফিল্টার মুছে ফেলা হয়েছে।";
    renderProducts();
  });
  $("applyProductFilters")?.addEventListener("click", () => {
    const hasPriceRange = Boolean(($("priceMin")?.value || "").trim() || ($("priceMax")?.value || "").trim());
    const currency = $("priceCurrency")?.value || "";
    if (hasPriceRange && !currency) {
      if ($("filterHint")) $("filterHint").textContent = "দামের ফিল্টার ব্যবহার করতে আগে মুদ্রা নির্বাচন করুন।";
      $("priceCurrency")?.focus();
      return;
    }
    renderProducts();
    const filterDetails = $("applyProductFilters")?.closest("details");
    if (filterDetails) filterDetails.open = false;
    $("productList")?.scrollIntoView({ behavior: "smooth", block: "start" });
  });
  $("nxAdmin")?.addEventListener("click", handleAssistantModeration);
  window.addEventListener("nexora:auth-change", async () => {
    state.business = null;
    await loadAdminQueue();
    await loadAdminActions();
    if ($("market") && !$("market").classList.contains("hidden")) await loadProducts();
    if ($("demandBoard") && !$("demandBoard").classList.contains("hidden")) await loadDemands();
    if ($("sellerDashboard") && !$("sellerDashboard").classList.contains("hidden")) await loadSellerDashboard();
    if ($("buyerDashboard") && !$("buyerDashboard").classList.contains("hidden")) await loadBuyerDashboard();
  });

  const today = new Date();
  const localToday = new Date(today.getTime() - today.getTimezoneOffset() * 60000).toISOString().split("T")[0];
  if ($("requiredDate")) $("requiredDate").min = localToday;
  if ($("market")) { loadProducts(); loadDemands(); }
})();