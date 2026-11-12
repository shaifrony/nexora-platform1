/* NEXORA Marketplace — Supabase-backed MVP */
(() => {
  "use strict";
  const state = { products: [], demands: [], business: null, businessMap: new Map(), offers: {} };
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

  async function loadAdminQueue() {
    if (profile()?.role !== "admin" || profile()?.account_status !== "active") return;
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
      <p class="muted">${esc(p.product_code)} | ${esc(p.category)} | ${esc(p.price)} ${esc(p.currency)}</p>
      <div class="form-actions">
        <button class="primary" data-review-type="product" data-review-id="${esc(p.id)}" data-decision="approved">Approve</button>
        <button class="danger" data-review-type="product" data-review-id="${esc(p.id)}" data-decision="rejected">Reject</button>
      </div></div>`).join("") || "কোনো Pending Product নেই।";
  }

  async function handleAdminDecision(e) {
    const button = e.target.closest("button[data-review-type]");
    if (!button || profile()?.role !== "admin" || profile()?.account_status !== "active") return;
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

  window.showSection = function(id) {
    if (id === "postDemand" && !(signedIn() && activeBuyer())) {
      document.querySelectorAll("main section.section").forEach(s => s.classList.add("hidden"));
      $("accountSection")?.classList.remove("hidden");
      const hint = $("nxCurrent");
      if (hint) hint.textContent = signedIn()
        ? "Post a Demand ব্যবহার করতে Active Buyer অ্যাকাউন্ট প্রয়োজন।"
        : "Post a Demand করতে আগে Buyer হিসেবে লগইন করুন।";
      $("accountSection")?.scrollIntoView({ behavior: "smooth", block: "start" });
      return;
    }
    document.querySelectorAll("main section.section").forEach(s => s.classList.toggle("hidden", s.id !== id));
    if (id === "market") loadProducts();
    if (id === "demandBoard") loadDemands();
    if (id === "sellerDashboard") loadSellerDashboard();
    window.scrollTo({ top: 0, behavior: "smooth" });
  };

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
    if (!host || !client()) return;
    if (!signedIn()) { host.textContent = "অনুমোদিত পণ্য দেখতে আগে লগইন করুন।"; return; }
    host.textContent = "পণ্য লোড হচ্ছে…";
    const { data, error } = await client().from("products")
      .select("id,product_code,slug,product_name,category,image_urls,description,origin,specifications_quality,price,currency,listing_status,business_id")
      .eq("listing_status", "approved")
      .order("created_at", { ascending: false });
    if (error) { host.textContent = "পণ্য লোড হয়নি: " + error.message; return; }
    state.products = data || [];
    const { data: businesses } = await client().from("public_businesses")
      .select("business_id,display_name,country,city");
    state.businessMap = new Map((businesses || []).map(b => [b.business_id, b]));
    renderProducts();
  }

  function renderProducts() {
    const businessMap = state.businessMap;
    const host = $("productList");
    if (!host) return;
    const search = ($("productSearch")?.value || "").toLowerCase();
    const category = $("categoryFilter")?.value || "";
    const rows = state.products.filter(p =>
      (p.product_name + " " + p.description + " " + p.origin).toLowerCase().includes(search) &&
      (!category || p.category === category)
    );
    if ($("productCount")) $("productCount").textContent = rows.length + " Products";
    host.innerHTML = rows.length ? rows.map(p => {
      const b = businessMap.get(p.business_id);
      const image = (p.image_urls || [])[0];
      return `<article class="card">
        ${image ? `<img class="product-image" src="${esc(image)}" alt="Product image" onerror="this.style.display='none'">` : ""}
        <span class="tag">${esc(p.category)}</span>
        <h3>${esc(p.product_name)}</h3><p class="muted">${esc(p.description)}</p>
        <p class="muted">Origin: ${esc(p.origin)}</p>
        <p class="muted">Business: ${esc(b?.display_name || "Approved Seller")}</p>
        <p class="price">${esc(p.price)} ${esc(p.currency)}</p>
        <p class="muted">Product ID: ${esc(p.product_code)}</p>
        <p class="muted">Permanent URL slug: ${esc(p.slug)}</p>
      </article>`;
    }).join("") : '<div class="card">কোনো অনুমোদিত পণ্য পাওয়া যায়নি।</div>';
  }

  async function loadDemands() {
    const host = $("demandList");
    if (!host || !client()) return;
    if (!signedIn()) { host.textContent = "চাহিদা দেখতে লগইন করুন।"; return; }
    host.textContent = "চাহিদা লোড হচ্ছে…";
    const { data, error } = await client().from("buyer_demands")
      .select("id,demand_code,product_name,category,description,specifications_quality,required_quantity,budget,currency,destination_country,destination_city,required_date,demand_status")
      .eq("demand_status", "open").order("created_at", { ascending: false });
    if (error) { host.textContent = "চাহিদা লোড হয়নি: " + error.message; return; }
    state.demands = data || [];
    renderDemands();
  }

  async function renderDemands() {
    const host = $("demandList");
    if (!host) return;
    if (!state.demands.length) { host.innerHTML = '<div class="card">এখনো কোনো খোলা চাহিদা নেই।</div>'; return; }
    const cards = [];
    for (const d of state.demands) {
      const { data: offers } = await client().from("seller_offers")
        .select("id,seller_id,offer_price,currency,available_quantity,message,offer_status")
        .eq("demand_id", d.id);
      const ownOffer = (offers || []).find(o => o.seller_id === user()?.id);
      const offerHTML = (offers || []).map(o => `<div class="offer">
        <strong>${o.seller_id === user()?.id ? "আপনার প্রস্তাব" : "Price Offer"}</strong>
        <p class="price">${esc(o.offer_price)} ${esc(o.currency)}</p>
        <p class="muted">Available Quantity: ${esc(o.available_quantity)}</p>
        <p class="muted">${esc(o.message || "")}</p>
      </div>`).join("");
      cards.push(`<article class="card">
        <span class="tag">${esc(d.category)}</span><span class="tag">${esc(d.demand_status)}</span>
        <h3>${esc(d.product_name)}</h3><p>${esc(d.description)}</p>
        <p class="muted"><strong>Specifications:</strong> ${esc(d.specifications_quality || "")}</p>
        <div class="grid">
          <div><p class="muted">Quantity</p><strong>${esc(d.required_quantity)}</strong></div>
          <div><p class="muted">Budget</p><strong>${esc(d.budget ?? "Not specified")} ${esc(d.currency)}</strong></div>
          <div><p class="muted">Destination</p><strong>${esc(d.destination_city)}, ${esc(d.destination_country)}</strong></div>
        </div>
        <p><span class="demand-date">Required by: ${esc(d.required_date)}</span></p>
        <p class="muted">Demand ID: ${esc(d.demand_code)}</p>
        <p><strong>${(offers || []).length} Price Offer(s)</strong></p>
        ${offerHTML}
        ${activeSeller() ? (ownOffer ? '<p class="muted">এই চাহিদায় আপনার Offer জমা আছে।</p>' : `<button class="secondary" type="button" data-offer="${esc(d.id)}">Submit Price Offer</button>`) : ""}
      </article>`);
    }
    host.innerHTML = cards.join("");
    host.querySelectorAll("button[data-offer]").forEach(b => b.addEventListener("click", () => submitOffer(b.dataset.offer)));
  }

  async function submitOffer(demandId) {
    if (!activeSeller()) return say("Offer দিতে সক্রিয় Seller অ্যাকাউন্ট প্রয়োজন।");
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
      $("sellerProducts").innerHTML = (data || []).length ? data.map(p => `
        <div class="offer"><strong>${esc(p.product_name)}</strong>
        <p class="muted">${esc(p.category)} | ${esc(p.origin)}</p>
        <p class="price">${esc(p.price)} ${esc(p.currency)}</p>
        <p class="muted">Product ID: ${esc(p.product_code)} | Approval: ${esc(p.listing_status)}</p>
        ${p.listing_status === "pending" ? `<button class="danger" data-delete-product="${esc(p.id)}">Delete</button>` : ""}
        </div>`).join("") : '<p class="muted">এখনো কোনো পণ্য যোগ করা হয়নি।</p>';
      $("sellerProducts").querySelectorAll("button[data-delete-product]").forEach(b => b.addEventListener("click", () => deleteProduct(b.dataset.deleteProduct)));
      const { data: demands, error: demandError } = await client().from("buyer_demands")
        .select("id,product_name,category,description,required_date")
        .eq("demand_status", "open").order("created_at", { ascending: false });
      if (demandError) throw demandError;
      $("matchedDemands").innerHTML = (demands || []).map(d => `
        <div class="offer"><strong>${esc(d.product_name)}</strong>
        <p class="muted">${esc(d.category)}</p><p>${esc(d.description)}</p>
        <p><span class="demand-date">Required by: ${esc(d.required_date)}</span></p></div>`).join("") || '<p class="muted">এখনো কোনো খোলা Buyer Demand নেই।</p>';
    } catch (err) { say("Seller Dashboard লোড হয়নি: " + err.message); }
  }

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
    if (!Number.isFinite(Number(v.price)) || Number(v.price) < 0) return say("সঠিক মূল্য লিখুন।");
    setBusy(form, true);
    try {
      const { error } = await client().from("products").insert({
        business_id: state.business.id, seller_id: user().id,
        product_name: v.name.trim(), category: v.category, image_urls: images,
        description: v.description.trim(), origin: v.origin.trim(),
        specifications_quality: v.specifications.trim(),
        price: Number(v.price), currency: String(v.currency).toUpperCase()
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
    if (!Number.isFinite(Number(v.budget)) || Number(v.budget) < 0) return say("সঠিক Budget লিখুন।");
    setBusy(form, true);
    try {
      const { error } = await client().from("buyer_demands").insert({
        buyer_id: user().id, product_name: v.name.trim(), category: v.category,
        description: v.description.trim(), specifications_quality: v.specifications.trim(),
        required_quantity: v.quantity.trim(), budget: Number(v.budget), currency: String(v.currency).toUpperCase(),
        destination_country: v.country.trim(), destination_city: v.destination.trim(), required_date: v.requiredDate
      });
      if (error) throw error;
      form.reset(); say("Buyer Demand প্রকাশিত হয়েছে।", true); showSection("demandBoard");
    } catch (err) { say("Demand প্রকাশ হয়নি: " + err.message); }
    finally { setBusy(form, false); }
  });

  $("productSearch")?.addEventListener("input", () => renderProducts());
  $("categoryFilter")?.addEventListener("change", () => renderProducts());
  window.addEventListener("nexora:auth-change", async () => {
    state.business = null;
    await loadAdminQueue();
    if ($("market") && !$("market").classList.contains("hidden")) await loadProducts();
    if ($("demandBoard") && !$("demandBoard").classList.contains("hidden")) await loadDemands();
    if ($("sellerDashboard") && !$("sellerDashboard").classList.contains("hidden")) await loadSellerDashboard();
  });

  const today = new Date();
  const localToday = new Date(today.getTime() - today.getTimezoneOffset() * 60000).toISOString().split("T")[0];
  if ($("requiredDate")) $("requiredDate").min = localToday;
  if ($("market")) loadProducts();
})();