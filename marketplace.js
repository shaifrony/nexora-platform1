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
  const activePorter = () => profile()?.role === "porter" && profile()?.account_status === "active";
  const currencyOK = (v) => /^[A-Z]{3}$/.test(String(v || "").toUpperCase());
  function parseProductPriceTiers(raw,moq){const lines=String(raw||"").split(/\r?\n/).map(x=>x.trim()).filter(Boolean);if(lines.length>20)throw new Error("সর্বোচ্চ ২০টি Price Tier দেওয়া যাবে।");const tiers=[];let previous=Number(moq);for(const line of lines){const m=line.match(/^(\d+(?:\.\d+)?)\s*[:=]\s*(\d+(?:\.\d+)?)$/);if(!m)throw new Error("প্রতি লাইনে পরিমাণ=একক মূল্য লিখুন, যেমন 100=95");const min=Number(m[1]),price=Number(m[2]);if(!Number.isInteger(min)||min<=previous||price<=0)throw new Error("Tier-এর পরিমাণ MOQ-এর বেশি ও ক্রমানুসারে হতে হবে; মূল্য শূন্যের বেশি দিন।");tiers.push({min_quantity:min,unit_price:price});previous=min;}return tiers;}
  const setBusy = (form, busy) => form.querySelectorAll("button").forEach(b => b.disabled = busy);
  const listingImageBucket = "nexora-listing-images";
  const listingImageTypes = new Set(["image/jpeg","image/png","image/webp","image/avif"]);
  const listingImageExtensions = {"image/jpeg":"jpg","image/png":"png","image/webp":"webp","image/avif":"avif"};

  function bindListingImagePicker(inputId, previewId, maxFiles) {
    const input=$(inputId), preview=$(previewId);
    if(!input||!preview||input.dataset.nxBound==="true")return;
    input.dataset.nxBound="true";
    input.addEventListener("change",()=>{
      const selected=Array.from(input.files||[]);
      if(selected.length>maxFiles){
        const transfer=new DataTransfer();
        selected.slice(0,maxFiles).forEach(file=>transfer.items.add(file));
        input.files=transfer.files;
        say("সর্বোচ্চ "+maxFiles+"টি ছবি নির্বাচন করা যাবে।");
      }
      preview.querySelectorAll("img").forEach(img=>{if(img.src.startsWith("blob:"))URL.revokeObjectURL(img.src);});
      preview.replaceChildren();
      Array.from(input.files||[]).forEach((file,index)=>{
        const figure=document.createElement("figure");
        const img=document.createElement("img");
        img.src=URL.createObjectURL(file);img.alt="নির্বাচিত ছবি "+(index+1);
        const caption=document.createElement("figcaption");caption.textContent=file.name;
        const remove=document.createElement("button");remove.type="button";remove.textContent="বাদ দিন";remove.setAttribute("aria-label",file.name+" বাদ দিন");
        remove.addEventListener("click",()=>{
          const transfer=new DataTransfer();
          Array.from(input.files||[]).forEach((item,i)=>{if(i!==index)transfer.items.add(item);});
          input.files=transfer.files;input.dispatchEvent(new Event("change"));
        });
        figure.append(img,caption,remove);preview.appendChild(figure);
      });
    });
  }

  async function uploadListingImages(files,kind) {
    const selected=Array.from(files||[]);
    if(!selected.length)return {urls:[],paths:[]};
    if(!user()?.id||!activeSeller()||!state.business||state.business.approval_status!=="approved")
      throw new Error("ছবি আপলোড করতে সক্রিয় Seller এবং অনুমোদিত Business Profile প্রয়োজন।");
    if(selected.some(file=>!listingImageTypes.has(file.type)||file.size>5*1024*1024))
      throw new Error("শুধু JPG, PNG, WEBP বা AVIF ছবি দিন; প্রতিটি ছবির আকার সর্বোচ্চ ৫ MB।");
    const urls=[],paths=[];
    for(const file of selected){
      const path=user().id+"/"+kind+"/"+crypto.randomUUID()+"."+listingImageExtensions[file.type];
      const {error}=await client().storage.from(listingImageBucket).upload(path,file,{
        contentType:file.type,cacheControl:"31536000",upsert:false
      });
      if(error){if(paths.length)await client().storage.from(listingImageBucket).remove(paths);throw error;}
      paths.push(path);
      const {data}=client().storage.from(listingImageBucket).getPublicUrl(path);
      if(!data?.publicUrl){await client().storage.from(listingImageBucket).remove(paths);throw new Error("ছবির Public URL তৈরি করা যায়নি।");}
      urls.push(data.publicUrl);
    }
    return {urls,paths};
  }

  async function removeListingImages(paths) {
    const clean=(paths||[]).filter(Boolean);
    if(!clean.length||!client())return;
    const {error}=await client().storage.from(listingImageBucket).remove(clean);
    if(error)console.warn("NEXORA listing image cleanup failed:",error.message);
  }

  function listingImagePathsFromUrls(urls) {
    const marker="/storage/v1/object/public/"+listingImageBucket+"/";
    return (urls||[]).flatMap(value=>{
      try{const path=new URL(value).pathname;const index=path.indexOf(marker);return index>=0?[decodeURIComponent(path.slice(index+marker.length))]:[];}
      catch(_){return [];}
    });
  }

  bindListingImagePicker("nxProductImageFiles","nxProductImagePreview",5);
  bindListingImagePicker("nxServiceImageFiles","nxServiceImagePreview",3);

  window.toggleProductForm = function() {
    $("productForm")?.classList.toggle("hidden");
  };

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
        .in("role",["buyer","seller"]).order("created_at",{ascending:false}).limit(100);
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
    if (id === "servicesMarketplace") loadServicesMarketplace();
    if (id === "administrationDashboard" || id === "accountSection") loadAdminServiceQueue();
    if (id === "administrationDashboard" || id === "accountSection") loadAdminListingEditRequests();
    if (id === "administrationDashboard" || id === "accountSection") loadAdminActions();
    if (id === "buyerDashboard") loadBuyerDashboard();
    if (id === "sellerDashboard") loadSellerDashboard();
    if (id === "porterDashboard") loadPorterDashboard();
    // Legacy Porter-role logistics queries are paused until provider/vehicle schema replaces them.
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

  window.openMyDashboard = function() {
    const identity = window.NEXORA_AUTH;
    const p = identity?.profile || profile();
    if (!p || p.account_status !== "active") return window.showSection("accountSection");
    if (p.role === "buyer") return window.showSection("buyerDashboard");
    if (p.role === "seller") return window.showSection("sellerDashboard");
    if (p.role === "porter") return window.showSection("porterDashboard");
    if (p.role === "admin") return window.showSection("administrationDashboard");
    return window.showSection("accountSection");
  };

  window.showSection = function(id, options = {}) {
    const role = profile()?.role;
    const access = {
      buyer: signedIn() && activeBuyer(),
      seller: signedIn() && activeSeller(),
      porter: signedIn() && activePorter()
    };
    const requiredRole = {
      postDemand: "buyer", buyerDashboard: "buyer",
      sellerDashboard: "seller", porterDashboard: "porter"
    }[id];
    if (id === "administrationDashboard") {
      const identity = window.NEXORA_AUTH;
      const allowed = role === "admin" && identity?.profile?.account_status === "active" &&
        identity?.adminStaff?.is_active === true && identity?.mfaVerified === true;
      if (!allowed) {
        const hint = $("nxCurrent");
        if (hint) hint.textContent = "Administration Dashboard-এর জন্য সক্রিয় Admin Account এবং MFA যাচাই প্রয়োজন।";
        id = "accountSection";
      }
    }
    if (id === "transportProviderCenter" &&
        !(signedIn() && ["buyer","seller","porter"].includes(role) && profile()?.account_status === "active")) {
      const hint = $("nxCurrent");
      if (hint) hint.textContent = "Transport Provider Center ব্যবহার করতে সক্রিয় Buyer, Seller অথবা Admin-অনুমোদিত Porter অ্যাকাউন্ট প্রয়োজন।";
      id = "accountSection";
    }
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
    let productQuery = client().from("products")
      .select("id,product_code,slug,product_name,category,subcategory,image_urls,description,origin,specifications_quality,price,currency,listing_status,business_id,minimum_order_quantity,stock_tracking,stock_quantity,reserved_quantity,price_tiers")
      .eq("listing_status", "approved");
    const { data, error } = await productQuery.order("created_at", { ascending: false });
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
        p_message: String($("productInquiryMessage")?.value || "").trim() || null
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
  const orderStatusLabels={pending:"Seller-এর অপেক্ষায়",accepted:"Seller গ্রহণ করেছেন",ready_for_confirmation:"সম্পন্ন নিশ্চিত করুন",completed:"সম্পন্ন",cancelled:"বাতিল",rejected:"Seller গ্রহণ করেননি"};
  async function submitCommerceOrder(listingType,listingId,quantity,location,note,statusNode,button){
    if(!activeBuyer()||!signedIn())return say("অর্ডার করতে Active Buyer হিসেবে লগইন করুন।");
    if(button)button.disabled=true;
    if(statusNode)statusNode.textContent="অর্ডার অনুরোধ পাঠানো হচ্ছে…";
    try{
      const {data,error}=await client().rpc("create_commerce_order",{
        p_listing_type:listingType,p_listing_id:listingId,p_quantity:Number(quantity),
        p_fulfilment_location:String(location||"").trim(),p_buyer_note:String(note||"").trim()||null
      });
      if(error)throw error;
      say("অর্ডার অনুরোধ পাঠানো হয়েছে। Seller গ্রহণ করলে অগ্রগতি দেখতে পারবেন।",true);
      if(statusNode)statusNode.textContent="অর্ডার নম্বর: "+data;
      await loadBuyerOrders();
      if(button)button.disabled=false;
      return data;
    }catch(err){
      if(statusNode)statusNode.textContent="অর্ডার হয়নি: "+(err.message||"অজানা সমস্যা");
      if(button)button.disabled=false;
      return null;
    }
  }
  async function loadBuyerPriceNegotiations(){
    const host=$("nxBuyerPriceNegotiations");if(!host)return;
    if(!signedIn()||!activeBuyer()){host.textContent="Buyer হিসেবে লগইন করলে আপনার ব্যক্তিগত দরদাম দেখা যাবে।";return;}
    try{
      const {data,error}=await client().from("product_price_negotiations")
        .select("id,product_id,conversation_id,quantity,current_unit_price,currency,fulfilment_location,negotiation_status,last_actor_id,order_id,created_at,updated_at")
        .eq("buyer_id",user().id).order("updated_at",{ascending:false}).limit(50);
      if(error)throw error;const rows=data||[];
      const productIds=[...new Set(rows.map(n=>n.product_id))];let products={};
      if(productIds.length){const p=await client().from("products").select("id,product_name,price,listing_status").in("id",productIds);if(p.error)throw p.error;(p.data||[]).forEach(x=>products[x.id]=x);}
      const labels={buyer_countered:"Seller-এর জবাবের অপেক্ষায়",seller_countered:"আপনার জবাবের অপেক্ষায়",ordered:"Order তৈরি হয়েছে",rejected:"প্রত্যাখ্যাত"};
      host.innerHTML=rows.map(n=>'<article class="card"><div class="section-head"><strong>'+esc(products[n.product_id]?.product_name||"Product")+'</strong><span class="tag">'+esc(labels[n.negotiation_status]||n.negotiation_status)+'</span></div><p>ওয়েবসাইটের প্রকাশ্য মূল্য: '+esc(products[n.product_id]?.price??"—")+' '+esc(n.currency)+' / ইউনিট</p><p><b>আপনার দর:</b> '+esc(n.quantity)+' × '+esc(n.current_unit_price)+' '+esc(n.currency)+'</p><p class="muted">শুধু আপনি ও সংশ্লিষ্ট Seller এই আলোচনা দেখতে পান।</p>'+(n.negotiation_status==="seller_countered"?'<div class="form-actions"><button class="primary" data-buyer-product-neg="accept" data-neg-id="'+esc(n.id)+'">Seller-এর দাম গ্রহণ</button><button class="light" data-buyer-product-neg="counter" data-neg-id="'+esc(n.id)+'" data-qty="'+esc(n.quantity)+'" data-price="'+esc(n.current_unit_price)+'">আরেকটি দাম প্রস্তাব</button><button class="danger" data-buyer-product-neg="reject" data-neg-id="'+esc(n.id)+'">প্রত্যাখ্যান</button></div>':'')+(n.order_id?'<p><b>Order ID:</b> '+esc(n.order_id)+'</p>':'')+(n.conversation_id?'<button class="light" type="button" data-open-negotiation-chat="'+esc(n.conversation_id)+'">এই Product Chat খুলুন</button>':'')+'</article>').join("")||'<p class="muted">এখনো কোনো Product দরদাম নেই।</p>';
      host.querySelectorAll("[data-open-negotiation-chat]").forEach(b=>b.addEventListener("click",()=>window.NEXORA_OPEN_CONVERSATION?.(b.dataset.openNegotiationChat)));
      host.querySelectorAll("[data-buyer-product-neg]").forEach(b=>b.addEventListener("click",()=>respondToProductNegotiation(b.dataset.negId,b.dataset.buyerProductNeg,Number(b.dataset.qty)||null,Number(b.dataset.price)||null)));
    }catch(err){host.textContent="দরদামের তথ্য লোড হয়নি: "+err.message;}
  }

  async function loadBuyerOrders(){
    const host=$("nxBuyerOrders");if(!host)return;
    if(!signedIn()||!activeBuyer()){host.textContent="Buyer হিসেবে লগইন করলে আপনার অর্ডার দেখা যাবে।";return;}
    try{
      const {data,error}=await client().from("commerce_orders")
        .select("id,order_code,listing_type,listing_id,quantity,unit_price,total_price,delivery_charge,grand_total,currency,order_status,created_at,seller_note")
        .eq("buyer_id",user().id).order("created_at",{ascending:false}).limit(50);
      if(error)throw error;
      const rows=data||[];
      host.innerHTML=rows.map(o=>'<article class="card nx-order-card"><div class="section-head"><strong>'+esc(o.order_code)+'</strong><span class="tag">'+esc(orderStatusLabels[o.order_status]||o.order_status)+'</span></div><p>'+esc(o.listing_type==="product"?"পণ্য অর্ডার":o.listing_type==="buyer_demand"?"Buyer Demand অর্ডার":"সেবা বুকিং")+' · '+esc(o.quantity)+' × '+esc(o.unit_price)+' '+esc(o.currency)+'</p><strong>'+esc(o.grand_total??o.total_price)+' '+esc(o.currency)+'</strong>'+(Number(o.delivery_charge||0)>0?'<p class="muted">পণ্যের মূল্য: '+esc(o.total_price)+' '+esc(o.currency)+' · ডেলিভারি চার্জ: '+esc(o.delivery_charge)+' '+esc(o.currency)+'</p>':'')'+(o.seller_note?'<p class="muted">'+esc(o.seller_note)+'</p>':'')+(o.order_status==="ready_for_confirmation"?'<button class="primary" type="button" data-order-action="complete" data-order-id="'+esc(o.id)+'" data-order-type="'+esc(o.listing_type)+'">আমি পণ্য/সেবা পেয়েছি — সম্পন্ন করুন</button>':'')+(o.order_status==="pending"?'<button class="light" type="button" data-order-action="cancel" data-order-id="'+esc(o.id)+'" data-order-type="'+esc(o.listing_type)+'">অর্ডার বাতিল</button>':'')+'</article>').join("")||'<p class="muted">আপনার কোনো অর্ডার নেই।</p>';
      host.querySelectorAll("[data-order-action]").forEach(b=>b.addEventListener("click",()=>transitionCommerceOrder(b.dataset.orderId,b.dataset.orderAction,b.dataset.orderType)));
    }catch(err){host.textContent="অর্ডার লোড হয়নি: "+err.message;}
  }
  async function updateSellerProductInventory(productId){
    const product=(window.NEXORA_SELLER_PRODUCTS||[]).find(p=>p.id===productId);if(!product)return say("পণ্যের তথ্য পাওয়া যায়নি।");
    const enabled=confirm("OK চাপলে Stock Tracking চালু হবে; Cancel চাপলে সীমাহীন স্টক থাকবে।");let quantity=null;
    if(enabled){const raw=prompt("মোট হাতে থাকা স্টক লিখুন (সংরক্ষিত অর্ডারসহ):",String(product.stock_quantity??""));if(raw===null)return;quantity=Number(raw);if(!Number.isFinite(quantity)||quantity<Number(product.reserved_quantity||0))return say("স্টক সংরক্ষিত অর্ডারের পরিমাণের কম হতে পারবে না।");}
    try{const {error}=await client().rpc("set_product_inventory",{p_product_id:productId,p_stock_tracking:enabled,p_stock_quantity:quantity});if(error)throw error;say("স্টক তথ্য আপডেট হয়েছে।",true);await loadSellerDashboard();}catch(err){say("স্টক আপডেট হয়নি: "+err.message);}
  }

  async function loadSellerPriceNegotiations(){
    const host=$("nxSellerPriceNegotiations");if(!host)return;
    if(!signedIn()||!activeSeller()){host.textContent="Active Seller লগইন প্রয়োজন।";return;}
    try{
      const {data,error}=await client().from("product_price_negotiations")
        .select("id,product_id,conversation_id,buyer_id,quantity,current_unit_price,currency,fulfilment_location,negotiation_status,last_actor_id,order_id,updated_at")
        .eq("seller_id",user().id).order("updated_at",{ascending:false}).limit(100);
      if(error)throw error;const rows=data||[];
      const ids=[...new Set(rows.map(n=>n.product_id))];let products={};
      if(ids.length){const p=await client().from("products").select("id,product_name,price").in("id",ids);if(p.error)throw p.error;(p.data||[]).forEach(x=>products[x.id]=x);}
      const labels={buyer_countered:"Buyer-এর প্রস্তাব—আপনার জবাব প্রয়োজন",seller_countered:"আপনার পাল্টা প্রস্তাব পাঠানো হয়েছে",ordered:"Order তৈরি হয়েছে",rejected:"প্রত্যাখ্যাত"};
      host.innerHTML=rows.map(n=>'<article class="card"><div class="section-head"><strong>'+esc(products[n.product_id]?.product_name||"Product")+'</strong><span class="tag">'+esc(labels[n.negotiation_status]||n.negotiation_status)+'</span></div><p>আপনার প্রকাশ্য মূল্য: '+esc(products[n.product_id]?.price??"—")+' '+esc(n.currency)+' / ইউনিট</p><p><b>সর্বশেষ প্রস্তাব:</b> '+esc(n.quantity)+' × '+esc(n.current_unit_price)+' '+esc(n.currency)+'</p><p class="muted">Buyer-এর ডেলিভারি ঠিকানা: '+esc(n.fulfilment_location)+'</p><p class="muted">এই দরদাম শুধু আপনি ও সংশ্লিষ্ট Buyer দেখতে পান।</p>'+(n.negotiation_status==="buyer_countered"?'<div class="form-actions"><button class="primary" data-seller-product-neg="accept" data-neg-id="'+esc(n.id)+'">Buyer-এর দাম গ্রহণ</button><button class="light" data-seller-product-neg="counter" data-neg-id="'+esc(n.id)+'" data-qty="'+esc(n.quantity)+'" data-price="'+esc(n.current_unit_price)+'">পাল্টা দাম দিন</button><button class="danger" data-seller-product-neg="reject" data-neg-id="'+esc(n.id)+'">প্রত্যাখ্যান</button></div>':'')+(n.order_id?'<p><b>Order ID:</b> '+esc(n.order_id)+'</p>':'')+(n.conversation_id?'<button class="light" type="button" data-open-negotiation-chat="'+esc(n.conversation_id)+'">এই Product Chat খুলুন</button>':'')+'</article>').join("")||'<p class="muted">কোনো Buyer দরদামের প্রস্তাব দেয়নি।</p>';
      host.querySelectorAll("[data-open-negotiation-chat]").forEach(b=>b.addEventListener("click",()=>window.NEXORA_OPEN_CONVERSATION?.(b.dataset.openNegotiationChat)));
      host.querySelectorAll("[data-seller-product-neg]").forEach(b=>b.addEventListener("click",()=>respondToProductNegotiation(b.dataset.negId,b.dataset.sellerProductNeg,Number(b.dataset.qty)||null,Number(b.dataset.price)||null)));
    }catch(err){host.textContent="দরদামের প্রস্তাব লোড হয়নি: "+err.message;}
  }

  async function respondToProductNegotiation(id,action,currentQuantity,currentPrice){
    let quantity=null,unitPrice=null,note=null;
    if(action==="counter"){
      const q=prompt("কত ইউনিটের প্রস্তাব দেবেন?",String(currentQuantity||1));if(q===null)return;quantity=Number(q);
      if(!Number.isFinite(quantity)||quantity<=0)return say("পরিমাণ ০-এর বেশি হতে হবে।");
      const p=prompt("প্রতি ইউনিটে আপনার প্রস্তাবিত দাম লিখুন:",String(currentPrice||""));if(p===null)return;unitPrice=Number(p);
      if(!Number.isFinite(unitPrice)||unitPrice<=0)return say("দাম ০-এর বেশি হতে হবে।");
      note=prompt("অতিরিক্ত শর্ত (ঐচ্ছিক):")||null;
    }else if(action==="reject"&&!confirm("এই দরদাম প্রত্যাখ্যান করবেন?"))return;
    else if(action==="accept"&&!confirm("সর্বশেষ প্রস্তাব গ্রহণ করে Order তৈরি করবেন?"))return;
    try{
      const {data,error}=await client().rpc("respond_to_product_price_negotiation",{p_negotiation_id:id,p_action:action,p_quantity:quantity,p_unit_price:unitPrice,p_note:note,p_fulfilment_location:null});
      if(error)throw error;
      say(action==="accept"?"দরদাম গৃহীত; Order তৈরি হয়েছে।":action==="counter"?"আপনার পাল্টা দাম পাঠানো হয়েছে।":"দরদাম প্রত্যাখ্যান করা হয়েছে।",true);
      await Promise.all([loadBuyerPriceNegotiations(),loadSellerPriceNegotiations(),loadBuyerOrders(),loadSellerOrders()]);
    }catch(err){say("দরদাম আপডেট হয়নি: "+err.message);}
  }

  async function loadSellerOrders(){
    const host=$("nxSellerOrders");if(!host)return;
    if(!signedIn()||!activeSeller()){host.textContent="Active Seller লগইন প্রয়োজন।";return;}
    try{
      const {data,error}=await client().from("commerce_orders")
        .select("id,order_code,listing_type,listing_id,buyer_id,quantity,unit_price,total_price,delivery_charge,grand_total,currency,fulfilment_location,buyer_note,order_status,created_at")
        .eq("seller_id",user().id).order("created_at",{ascending:false}).limit(100);
      if(error)throw error;
      const rows=data||[];
      const counts={pending:0,accepted:0,ready_for_confirmation:0,completed:0,cancelled:0,rejected:0};
      rows.forEach(o=>{counts[o.order_status]=(counts[o.order_status]||0)+1;});
      host.innerHTML='<div class="nx-order-summary"><span>মোট '+rows.length+'</span><span>নতুন '+counts.pending+'</span><span>চলমান '+(counts.accepted+counts.ready_for_confirmation)+'</span><span>সম্পন্ন '+counts.completed+'</span></div><label>অর্ডার ফিল্টার <select id="nxSellerOrderStatusFilter"><option value="all">সব অর্ডার</option><option value="pending">নতুন অর্ডার</option><option value="accepted">গ্রহণ করা</option><option value="ready_for_confirmation">Buyer নিশ্চিত করবেন</option><option value="completed">সম্পন্ন</option><option value="cancelled">বাতিল</option><option value="rejected">প্রত্যাখ্যাত</option></select></label><div id="nxSellerOrderRows">'+(rows.map(o=>'<article class="card nx-order-card" data-seller-order-card data-status="'+esc(o.order_status)+'"><div class="section-head"><strong>'+esc(o.order_code)+'</strong><span class="tag">'+esc(orderStatusLabels[o.order_status]||o.order_status)+'</span></div><p>'+esc(o.listing_type==="product"?"পণ্য অর্ডার":o.listing_type==="buyer_demand"?"Buyer Demand অর্ডার":"সেবা বুকিং")+' · পরিমাণ '+esc(o.quantity)+' × '+esc(o.unit_price)+' '+esc(o.currency)+'</p><strong>'+esc(o.grand_total??o.total_price)+' '+esc(o.currency)+'</strong>'+(Number(o.delivery_charge||0)>0?'<p class="muted">পণ্যের মূল্য: '+esc(o.total_price)+' '+esc(o.currency)+' · ডেলিভারি চার্জ: '+esc(o.delivery_charge)+' '+esc(o.currency)+'</p>':'')<p><b>ডেলিভারি/সেবার স্থান:</b> '+esc(o.fulfilment_location)+'</p>'+(o.buyer_note?'<p><b>Buyer-এর নোট:</b> '+esc(o.buyer_note)+'</p>':'')+(o.order_status==="pending"?'<div class="form-actions"><button class="primary" data-order-action="accept" data-order-id="'+esc(o.id)+'" data-order-type="'+esc(o.listing_type)+'">অর্ডার গ্রহণ</button><button class="danger" data-order-action="reject" data-order-id="'+esc(o.id)+'" data-order-type="'+esc(o.listing_type)+'">প্রত্যাখ্যান</button></div>':'')+(o.order_status==="accepted"?'<button class="primary" data-order-action="ready" data-order-id="'+esc(o.id)+'" data-order-type="'+esc(o.listing_type)+'">'+(o.listing_type==="service"?"সেবা সম্পন্ন হয়েছে":"পণ্য পাঠানো হয়েছে")+'</button>':'')+'</article>').join("")||'<p class="muted">এখনো কোনো অর্ডার আসেনি।</p>')+'</div>';
      const filter=$("nxSellerOrderStatusFilter");
      if(filter)filter.addEventListener("change",()=>host.querySelectorAll("[data-seller-order-card]").forEach(card=>{card.hidden=filter.value!=="all"&&card.dataset.status!==filter.value;}));
      host.querySelectorAll("[data-order-action]").forEach(b=>b.addEventListener("click",()=>transitionCommerceOrder(b.dataset.orderId,b.dataset.orderAction,b.dataset.orderType)));
    }catch(err){host.textContent="অর্ডার লোড হয়নি: "+err.message;}
  }
  async function transitionCommerceOrder(orderId,action,listingType){
    let note=null;
    if(action==="reject"){note=prompt("অর্ডার প্রত্যাখ্যানের কারণ লিখুন (কমপক্ষে ৫ অক্ষর):");if(!note||note.trim().length<5)return say("কারণ দেওয়া আবশ্যক।");}
    if(action==="ready")note=prompt("পাঠানো/সেবা সম্পন্নের তথ্য (ঐচ্ছিক):")||null;
    try{
      const rpcName=listingType==="buyer_demand"?"transition_buyer_demand_order":"transition_commerce_order";
      const {error}=await client().rpc(rpcName,{p_order_id:orderId,p_action:action,p_note:note});
      if(error)throw error;
      say("অর্ডারের অবস্থা আপডেট হয়েছে।",true);
      await Promise.all([loadBuyerOrders(),loadSellerOrders()]);
      if(action==="complete"&&listingType!=="buyer_demand")say("অর্ডার সম্পন্ন হয়েছে। এখন আপনার Verified Review দেওয়ার অনুমতি তৈরি হয়েছে।",true);
    }catch(err){say("অর্ডার আপডেট হয়নি: "+err.message);}
  }

  async function loadListingReviews(listingType, listingId, hostId) {
    const host=$(hostId); if(!host)return;
    host.innerHTML='<p class="muted">Review লোড হচ্ছে…</p>';
    try{
      const {data,error}=await client().from("listing_reviews")
        .select("id,rating,review_title,review_body,reviewer_label,purchased_quantity,created_at")
        .eq("listing_type",listingType).eq("listing_id",listingId)
        .eq("review_status","published").order("created_at",{ascending:false}).limit(30);
      if(error)throw error;
      const rows=data||[];
      const summaryResult=await client().rpc("get_listing_review_summary",{p_listing_type:listingType,p_listing_id:listingId});
      if(summaryResult.error)throw summaryResult.error;
      const summaryData=Array.isArray(summaryResult.data)?summaryResult.data[0]:null;
      const reviewCount=Number(summaryData?.review_count||0);
      const average=Number(summaryData?.average_rating||0);
      let eligibility={can_review:false,already_reviewed:false};
      if(activeBuyer()&&signedIn()){
        const result=await client().rpc("get_my_review_eligibility",{p_listing_type:listingType,p_listing_id:listingId});
        if(!result.error&&Array.isArray(result.data)&&result.data[0])eligibility=result.data[0];
      }
      const summary=reviewCount
        ? '<div class="nx-review-summary"><strong>★ '+average.toFixed(1)+'/5</strong><span>'+reviewCount+'টি Verified Review</span></div>'
        : '<p class="muted">এখনো কোনো Verified Review নেই।';
      const cards=rows.map(r=>'<article class="nx-review-card"><div class="nx-review-card-top"><strong>'+esc(r.reviewer_label||"Verified Buyer")+'</strong><span class="nx-review-stars" aria-label="'+Number(r.rating)+' out of 5 stars">'+('★'.repeat(Number(r.rating)))+('☆'.repeat(5-Number(r.rating)))+'</span></div>'+(r.review_title?'<h4>'+esc(r.review_title)+'</h4>':'')+'<p>'+esc(r.review_body)+'</p><small class="muted">'+new Date(r.created_at).toLocaleDateString('bn-BD')+(r.purchased_quantity?' · ক্রয়ের পরিমাণ: '+esc(r.purchased_quantity):'')+'</small></article>').join("");
      const form=eligibility.can_review
        ? '<form class="nx-review-form" data-nx-review-form><h3>আপনার কেনাকাটার অভিজ্ঞতা লিখুন</h3><label>Rating<select name="rating" required><option value="5">★★★★★ — চমৎকার</option><option value="4">★★★★☆ — ভালো</option><option value="3">★★★☆☆ — মোটামুটি</option><option value="2">★★☆☆☆ — খারাপ</option><option value="1">★☆☆☆☆ — খুব খারাপ</option></select></label><label>শিরোনাম (ঐচ্ছিক)<input name="title" maxlength="100" placeholder="সংক্ষেপে অভিজ্ঞতা"></label><label>আপনার Review<textarea name="body" minlength="10" maxlength="2000" required placeholder="আপনার প্রকৃত কেনাকাটার অভিজ্ঞতা লিখুন"></textarea></label><button class="primary" type="submit">Verified Review জমা দিন</button><p class="muted" data-review-status aria-live="polite"></p></form>'
        : eligibility.already_reviewed
          ? '<p class="nx-review-note">আপনি এই Listing-এর জন্য ইতিমধ্যে Review দিয়েছেন।</p>'
          : '<p class="nx-review-note">শুধু NEXORA-তে সম্পন্ন ও যাচাইকৃত কেনাকাটা/সেবা গ্রহণকারী Buyer Review দিতে পারবেন। অর্ডার সম্পন্ন হওয়ার রেকর্ড না থাকলে Review দেওয়া যাবে না।</p>';
      host.innerHTML='<div class="nx-reviews-heading"><h3>Review & Rating</h3>'+summary+'</div>'+cards+form;
      const reviewForm=host.querySelector("[data-nx-review-form]");
      reviewForm?.addEventListener("submit",async event=>{
        event.preventDefault();
        const button=reviewForm.querySelector("button[type=submit]"),status=reviewForm.querySelector("[data-review-status]");
        const values=new FormData(reviewForm);button.disabled=true;status.textContent="জমা হচ্ছে…";
        try{
          const result=await client().rpc("submit_verified_listing_review",{
            p_listing_type:listingType,p_listing_id:listingId,p_rating:Number(values.get("rating")),
            p_review_title:values.get("title")||null,p_review_body:values.get("body")
          });
          if(result.error)throw result.error;
          say("আপনার Verified Review জমা হয়েছে।",true);
          await loadListingReviews(listingType,listingId,hostId);
        }catch(err){status.textContent="Review জমা হয়নি: "+(err.message||"অজানা সমস্যা");button.disabled=false;}
      });
    }catch(err){
      host.innerHTML='<p class="muted">Review লোড করা যায়নি। প্রয়োজনীয় Database Migration এখনো প্রয়োগ না হলে এটি স্বাভাবিক।</p>';
      console.warn("NEXORA reviews:",err.message);
    }
  }

  function renderProducts() {
    const businessMap = state.businessMap;
    const host = $("productList");
    if (!host) return;
    const detailPanel = $("productDetailPanel");
    const requestedSlug = new URLSearchParams(window.location.search).get("product");
    if (requestedSlug && detailPanel) {
      document.querySelector(".nx-market-hero")?.classList.add("hidden");
      document.querySelector(".nx-discovery-section")?.classList.add("hidden");
      document.querySelector(".nx-category-section")?.classList.add("hidden");
      document.querySelector(".nx-market-section-title")?.classList.add("hidden");
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
        <p><strong>ক্যাটাগরি:</strong> ${esc(selected.category)} · ${esc(selected.subcategory||"")}</p>
        <p><strong>Specifications & Quality:</strong> ${esc(selected.specifications_quality || "তথ্য দেওয়া হয়নি")}</p>
        <p class="price"><strong>মূল্য:</strong> ${esc(selected.price)} ${esc(selected.currency)} / ইউনিট</p>
        <p><strong>MOQ:</strong> ${esc(selected.minimum_order_quantity||1)} ইউনিট</p>
        ${(selected.price_tiers||[]).length?'<div class="card"><strong>পরিমাণভিত্তিক মূল্য</strong>'+selected.price_tiers.map(t=>'<p>'+esc(t.min_quantity)+'+ ইউনিট: '+esc(t.unit_price)+' '+esc(selected.currency)+' / ইউনিট</p>').join('')+'</div>':''}
        ${selected.stock_tracking?'<p><strong>উপলব্ধ স্টক:</strong> '+esc(Math.max(0,Number(selected.stock_quantity)-Number(selected.reserved_quantity)))+' ইউনিট</p>':'<p class="muted">স্টক সীমা প্রকাশ করা হয়নি।</p>'}
        <p><strong>Business Display Name:</strong> ${esc(business?.display_name || "Approved Seller")}</p>
        <p><strong>Product ID:</strong> ${esc(selected.product_code)}</p>
        
        ${activeBuyer()&&signedIn()?`<form id="nxProductNegotiationForm" class="card nx-order-form"><h3>দরদাম করুন</h3><p class="muted">Seller-এর নির্ধারিত মূল্য ${esc(selected.price)} ${esc(selected.currency)} / ইউনিট। আপনার প্রস্তাবিত মূল্য দিন।</p><label>কত ইউনিট কিনবেন? *<input name="quantity" type="number" min="${esc(selected.minimum_order_quantity||1)}" step="0.001" value="${esc(selected.minimum_order_quantity||1)}" required></label><label>আপনার প্রস্তাবিত প্রতি ইউনিট দাম *<input name="unit_price" type="number" min="0.01" step="0.01" max="${esc(selected.price)}" required placeholder="যেমন: 90"></label><label>ডেলিভারি ঠিকানা *<textarea name="location" minlength="5" maxlength="500" required placeholder="সম্পূর্ণ ডেলিভারি ঠিকানা লিখুন"></textarea></label><label>Seller-এর জন্য বার্তা (ঐচ্ছিক)<textarea name="note" maxlength="1000" placeholder="যেমন: ১০০ টাকার বদলে ৯০ টাকা দিতে চাই"></textarea></label><button class="primary" type="submit">দরদামের প্রস্তাব পাঠান</button><p data-negotiation-status aria-live="polite"></p><small class="muted">Seller গ্রহণ করলে অর্ডার তৈরি হবে। Seller পাল্টা দাম দিলে আপনি গ্রহণ বা নতুন প্রস্তাব দিতে পারবেন।</small></form>`:""}
        <div id="productInquiryArea" class="card nx-product-contact"><h3>Seller-এর সঙ্গে যোগাযোগ</h3><div id="productInquiryControls"></div><p id="productInquiryStatus" class="muted" aria-live="polite"></p></div>
        ${activeBuyer()&&signedIn()?`<form id="nxProductOrderForm" class="card nx-order-form"><h3>অর্ডার অনুরোধ</h3><label>পরিমাণ *<input name="quantity" type="number" min="${esc(selected.minimum_order_quantity||1)}" step="0.001" value="${esc(selected.minimum_order_quantity||1)}" required></label><label>ডেলিভারি ঠিকানা/গন্তব্য *<textarea name="location" minlength="5" maxlength="500" required placeholder="সম্পূর্ণ ডেলিভারি ঠিকানা লিখুন"></textarea></label><label>অতিরিক্ত নির্দেশনা (ঐচ্ছিক)<textarea name="note" maxlength="1500"></textarea></label><button class="primary" type="submit">অর্ডার অনুরোধ পাঠান</button><p data-order-status aria-live="polite"></p><small class="muted">এটি অর্ডার অনুরোধ; পেমেন্ট বা ডেলিভারি বুকিং এখনো অন্তর্ভুক্ত নয়।</small></form>`:""}
        <section id="nxProductReviews" class="nx-listing-reviews" aria-live="polite"></section>
      `;
      loadListingReviews("product",selected.id,"nxProductReviews");
      const contactArea = $("productInquiryArea");
      if (contactArea) contactArea.classList.toggle("hidden", !(activeBuyer() && signedIn()));
      const controls = $("productInquiryControls");
      if (controls && activeBuyer() && signedIn()) {
        controls.innerHTML = '<label for="productInquiryMessage">প্রাথমিক বার্তা (ঐচ্ছিক)</label><textarea id="productInquiryMessage" maxlength="500" placeholder="পণ্যের পরিমাণ, মান বা দাম সম্পর্কে জানতে লিখুন"></textarea><button class="primary nx-contact-seller-button" type="button" id="productContactSeller"><span aria-hidden="true">▣</span> Chat with Seller</button>';
      }
      $("productContactSeller")?.addEventListener("click", () => startProductChat(selected));
      $("nxProductOrderForm")?.addEventListener("submit",e=>{e.preventDefault();const v=new FormData(e.currentTarget);submitCommerceOrder("product",selected.id,v.get("quantity"),v.get("location"),v.get("note"),e.currentTarget.querySelector("[data-order-status]"),e.currentTarget.querySelector("button[type=submit]"));});
      $("nxProductNegotiationForm")?.addEventListener("submit",async e=>{
        e.preventDefault();const form=e.currentTarget,v=new FormData(form),status=form.querySelector("[data-negotiation-status]"),button=form.querySelector("button[type=submit]");
        const quantity=Number(v.get("quantity")),price=Number(v.get("unit_price")),min=Number(selected.minimum_order_quantity||1),available=selected.stock_tracking?Math.max(0,Number(selected.stock_quantity)-Number(selected.reserved_quantity)):null;
        if(!Number.isFinite(quantity)||quantity<min||(available!==null&&quantity>available)){status.textContent="পরিমাণ MOQ এবং উপলব্ধ স্টকের মধ্যে হতে হবে।";return;}
        if(!Number.isFinite(price)||price<=0){status.textContent="প্রস্তাবিত দাম ০-এর বেশি হতে হবে।";return;}
        button.disabled=true;status.textContent="দরদামের প্রস্তাব পাঠানো হচ্ছে…";
        try{const {data,error}=await client().rpc("start_product_price_negotiation",{p_product_id:selected.id,p_quantity:quantity,p_unit_price:price,p_note:String(v.get("note")||"").trim()||null,p_fulfilment_location:String(v.get("location")||"").trim()});if(error)throw error;status.textContent="প্রস্তাব Seller-এর কাছে পাঠানো হয়েছে। Negotiation ID: "+data;say("দরদামের প্রস্তাব পাঠানো হয়েছে।",true);await loadBuyerPriceNegotiations();const thread=await client().from("product_price_negotiations").select("conversation_id").eq("id",data).single();if(!thread.error&&thread.data?.conversation_id&&typeof window.NEXORA_OPEN_CONVERSATION==="function")await window.NEXORA_OPEN_CONVERSATION(thread.data.conversation_id);}
        catch(err){status.textContent="প্রস্তাব পাঠানো যায়নি: "+err.message;}finally{button.disabled=false;}
      });
      return;
    }
    if (detailPanel) detailPanel.classList.add("hidden");
    document.querySelector(".nx-market-hero")?.classList.remove("hidden");
    document.querySelector(".nx-discovery-section")?.classList.remove("hidden");
    document.querySelector(".nx-category-section")?.classList.remove("hidden");
    document.querySelector(".nx-market-section-title")?.classList.remove("hidden");
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
        {name:"Electronic Components",category:"Electronics",description:"ইলেকট্রনিক যন্ত্রাংশের নমুনা পণ্য বিজ্ঞাপন।",origin:"International",image:"https://images.unsplash.com/photo-1518770660439-4636190af475?auto=format&fit=crop&w=900&q=80"},
        {name:"Cotton T-Shirt",category:"Textile & Garments",description:"টি-শার্টের নমুনা পণ্য বিজ্ঞাপন।",origin:"Bangladesh",image:"https://images.unsplash.com/photo-1521572163474-6864f9cf17ab?auto=format&fit=crop&w=900&q=80"},
        {name:"Home Decor",category:"Handicrafts",description:"ঘর সাজানোর নমুনা পণ্য বিজ্ঞাপন।",origin:"Bangladesh",image:"https://images.unsplash.com/photo-1513519245088-0e12902e5a38?auto=format&fit=crop&w=900&q=80"}
      ].filter(p =>
        (p.name + " " + p.description + " " + p.origin).toLowerCase().includes(search) &&
        (!category || p.category === category)
      );
      host.innerHTML = demos.length ? demos.map(p => `<article class="card product-card nx-product-card nx-demo-product-card">
        <div class="nx-product-card-media nx-demo-media"><img class="product-image" src="${esc(p.image)}" alt="${esc(p.name)}" loading="lazy" onerror="this.style.display='none'"></div>
        <div class="nx-product-card-body"><span class="tag">DEMO • নমুনা বিজ্ঞাপন</span><span class="tag">${esc(p.category)}</span>
        <h3>${esc(p.name)}</h3><p class="muted nx-product-description">${esc(p.description)}</p>
        <p class="muted nx-product-origin">📍 ${esc(p.origin)}</p><p class="price">দাম জানতে যোগাযোগ করুন</p></div>
      </article>`).join("") : '<div class="card">কোনো নমুনা পণ্য মেলেনি।</div>';
      return;
    }

    host.innerHTML = rows.length ? rows.map(p => {
      const b = businessMap.get(p.business_id);
      const image = (p.image_urls || []).find(Boolean);
      return `<article class="card product-card nx-product-card">
        <a class="nx-product-card-media" href="?product=${encodeURIComponent(p.slug)}" aria-label="${esc(p.product_name)} বিস্তারিত দেখুন">
          ${image ? `<img class="product-image" src="${esc(image)}" alt="${esc(p.product_name)}" loading="lazy" onerror="this.style.display='none'">` : '<span class="nx-product-image-fallback" aria-hidden="true">📦</span>'}
          
        </a>
        <div class="nx-product-card-body">
          <span class="tag">${esc(p.category)}</span>
          <h3><a href="?product=${encodeURIComponent(p.slug)}">${esc(p.product_name)}</a></h3>
          <p class="muted nx-product-description">${esc(p.description || "বিস্তারিত জানতে পণ্যটি দেখুন।")}</p>
          <p class="muted nx-product-origin">📍 ${esc(p.origin || "উৎপত্তি উল্লেখ নেই")}</p>
          <div class="nx-product-card-footer"><strong class="price">${esc(p.price)} ${esc(p.currency)}</strong><a class="nx-product-detail-link" href="?product=${encodeURIComponent(p.slug)}">বিস্তারিত দেখুন <span aria-hidden="true">→</span></a></div>
          <p class="muted nx-product-business">Business: ${esc(b?.display_name || "Approved Seller")}</p>
        </div>
      </article>`;
    }).join("") : '<div class="card nx-empty-market">কোনো অনুমোদিত পণ্য পাওয়া যায়নি।</div>';
  }

  async function loadBuyerDashboardProducts() {
    const host = $("buyerProductList");
    if (!host) return;
    if (!activeBuyer() || !signedIn()) { host.textContent = "সক্রিয় Buyer অ্যাকাউন্ট প্রয়োজন।"; return; }
    host.textContent = "অনুমোদিত পণ্য লোড হচ্ছে…";
    try {
      const { data, error } = await client().from("products").select("id,slug,product_code,product_name,category,subcategory,image_urls,description,price,currency,origin,listing_status").eq("listing_status", "approved").order("created_at", { ascending: false }).limit(100);
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
    loadBuyerOrders();
    loadBuyerPriceNegotiations();
    const host = $("buyerDemandList");
    if (!host) return;
    if (!signedIn() || !activeBuyer()) {
      host.textContent = "Buyer Dashboard ব্যবহার করতে সক্রিয় Buyer অ্যাকাউন্ট প্রয়োজন।";
      return;
    }
    host.textContent = "আপনার চাহিদা লোড হচ্ছে…";
    try {
      const { data, error } = await client().from("buyer_demands")
        .select("id,demand_code,product_name,category,subcategory,description,specifications_quality,required_quantity,budget,currency,destination_country,destination_city,required_date,demand_status,created_at")
        .eq("buyer_id", user().id).order("created_at", { ascending: false });
      if (error) throw error;
      state.buyerDemands = data || [];
      const ids = state.buyerDemands.map(d => d.id);
      let offers = [];
      if (ids.length) {
        const result = await client().from("seller_offers")
          .select("id,demand_id,offer_price,currency,available_quantity,message,offer_status,created_at,product_brand,product_model,product_condition,price_basis,estimated_delivery_date,warranty,offer_valid_until,delivery_charge,negotiation_status,current_quantity,current_unit_price,last_negotiator_id,accepted_quantity,accepted_unit_price,demand_order_id")
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
    const host=$("buyerDemandList"),demands=state.buyerDemands||[],offerMap=new Map();
    (offers||[]).forEach(o=>{if(!offerMap.has(o.demand_id))offerMap.set(o.demand_id,[]);offerMap.get(o.demand_id).push(o);});
    if($("buyerDemandTotal"))$("buyerDemandTotal").textContent=String(demands.length);
    if($("buyerDemandOpen"))$("buyerDemandOpen").textContent=String(demands.filter(d=>d.demand_status==="open").length);
    if($("buyerOfferTotal"))$("buyerOfferTotal").textContent=String((offers||[]).length);
    if(!host)return;
    if(!demands.length){host.innerHTML='<div class="offer">আপনি এখনো কোনো Buyer Demand পোস্ট করেননি। নতুন চাহিদা পোস্ট করে শুরু করুন।</div>';return;}
    const labels={open:"চলমান",closed:"বন্ধ",cancelled:"বাতিল"};
    host.innerHTML=demands.map(d=>{
      const list=offerMap.get(d.id)||[];
      const offerHTML=list.length?list.map(o=>{
        const qty=Number(o.current_quantity||o.available_quantity),unit=Number(o.current_unit_price||(o.price_basis==="total"?Number(o.offer_price)/Number(o.available_quantity):o.offer_price));
        const total=qty*unit, canRespond=d.demand_status==="open"&&["open","buyer_countered","seller_countered"].includes(o.negotiation_status||"open")&&!o.demand_order_id&&o.offer_status==="pending";
        const latestBySeller=o.last_negotiator_id!==user().id;
        const actions=canRespond&&latestBySeller?
          '<div class="form-actions"><button class="primary" type="button" data-quote-action="accept" data-offer-id="'+esc(o.id)+'" data-max-quantity="'+esc(qty)+'">এই শর্তে গ্রহণ</button><button class="light" type="button" data-quote-action="counter" data-offer-id="'+esc(o.id)+'" data-max-quantity="'+esc(qty)+'">Counter-offer</button><button class="danger" type="button" data-quote-action="reject" data-offer-id="'+esc(o.id)+'">প্রত্যাখ্যান</button></div>':'';
        return '<div class="offer"><strong>Seller Quotation</strong><p class="price">'+esc(unit.toFixed(2))+' '+esc(o.currency)+' / ইউনিট</p>'+
          '<p class="muted">সরবরাহযোগ্য সর্বোচ্চ: '+esc(qty)+' · এই শর্তে মোট: '+esc(total.toFixed(2))+' '+esc(o.currency)+'</p>'+
          '<p class="muted">ব্র্যান্ড/মডেল: '+esc([o.product_brand,o.product_model].filter(Boolean).join(" · ")||"উল্লেখ নেই")+'</p>'+
          '<p class="muted">অবস্থা: '+esc(({new:"নতুন",refurbished:"রিফারবিশড",used:"ব্যবহৃত",any:"যেকোনো"})[o.product_condition]||"উল্লেখ নেই")+
          (o.estimated_delivery_date?' · সম্ভাব্য সরবরাহ: '+esc(o.estimated_delivery_date):'')+'</p>'+
          (o.warranty?'<p class="muted">ওয়ারেন্টি: '+esc(o.warranty)+'</p>':'')+
          (o.delivery_charge!==null?'<p class="muted">ডেলিভারি চার্জ: '+esc(o.delivery_charge)+' '+esc(o.currency)+'</p>':'')+
          (o.offer_valid_until?'<p class="muted">Quotation বৈধ: '+esc(o.offer_valid_until)+'</p>':'')+
          (o.message?'<p class="muted">'+esc(o.message)+'</p>':'')+
          '<p class="muted">আলোচনার অবস্থা: '+esc(({open:"আপনার জবাবের অপেক্ষায়",buyer_countered:"Seller-এর জবাবের অপেক্ষায়",seller_countered:"আপনার জবাবের অপেক্ষায়",ordered:"Order তৈরি হয়েছে",declined:"প্রত্যাখ্যাত",agreed:"সম্মত"})[o.negotiation_status]||o.offer_status)+'</p>'+
          (o.accepted_quantity?'<p><b>গৃহীত Order:</b> '+esc(o.accepted_quantity)+' × '+esc(o.accepted_unit_price)+' '+esc(o.currency)+' · Order ID '+esc(o.demand_order_id)+'</p>':'')+actions+'</div>';
      }).join(""):'<p class="muted">এখনো কোনো Price Offer আসেনি।</p>';
      const actions=d.demand_status==="open"?'<div class="form-actions"><button class="light" type="button" data-demand-status="closed" data-demand-id="'+esc(d.id)+'">চাহিদা বন্ধ করুন</button><button class="danger" type="button" data-demand-status="cancelled" data-demand-id="'+esc(d.id)+'">চাহিদা বাতিল করুন</button></div>':'';
      return '<article class="card"><div class="section-head"><div><span class="tag">'+esc(d.category)+'</span><span class="tag">'+esc(labels[d.demand_status]||d.demand_status)+'</span></div><strong>'+esc(d.demand_code)+'</strong></div><h3>'+esc(d.product_name)+'</h3><p class="muted">Subcategory: '+esc(d.subcategory||"—")+'</p><p>'+esc(d.description)+'</p><p class="muted"><strong>স্পেসিফিকেশন:</strong> '+esc(d.specifications_quality||"উল্লেখ করা হয়নি")+'</p><div class="grid"><div><p class="muted">পরিমাণ</p><strong>'+esc(d.required_quantity)+'</strong></div><div><p class="muted">বাজেট</p><strong>'+(d.budget===null?"উল্লেখ করা হয়নি":esc(d.budget+" "+d.currency))+'</strong></div><div><p class="muted">গন্তব্য</p><strong>'+esc(d.destination_city)+', '+esc(d.destination_country)+'</strong></div></div><p><span class="demand-date">প্রয়োজনের তারিখ: '+esc(d.required_date)+'</span></p><p><strong>'+list.length+'টি Price Offer</strong></p>'+offerHTML+actions+'</article>';
    }).join("");
    host.querySelectorAll("button[data-demand-status][data-demand-id]").forEach(b=>b.addEventListener("click",()=>updateBuyerDemandStatus(b.dataset.demandId,b.dataset.demandStatus)));
    host.querySelectorAll("button[data-quote-action]").forEach(b=>b.addEventListener("click",()=>respondToDemandQuotation(b.dataset.offerId,b.dataset.quoteAction,Number(b.dataset.maxQuantity)||null)));
  }

  async function respondToDemandQuotation(offerId,action,maxQuantity){
    if(!activeBuyer()||!signedIn())return say("এই কাজটি করতে Active Buyer লগইন প্রয়োজন।");
    let quantity=null,unitPrice=null,note=null;
    if(action==="accept"){
      const raw=prompt("কত ইউনিট কিনতে চান? Seller-এর সর্বোচ্চ সরবরাহযোগ্য পরিমাণ "+maxQuantity+"।",String(maxQuantity));
      if(raw===null)return;quantity=Number(raw);
      if(!Number.isFinite(quantity)||quantity<=0||quantity>maxQuantity)return say("পরিমাণ ০-এর বেশি এবং Seller-এর সরবরাহযোগ্য পরিমাণের মধ্যে হতে হবে।");
      if(!confirm(quantity+" ইউনিটের জন্য Quotation গ্রহণ করে Order তৈরি করবেন?"))return;
    }else if(action==="counter"){
      const q=prompt("আপনি কত ইউনিট চান? সর্বোচ্চ "+maxQuantity+"।",String(maxQuantity));if(q===null)return;quantity=Number(q);
      if(!Number.isFinite(quantity)||quantity<=0||quantity>maxQuantity)return say("পরিমাণ সঠিক নয় বা Seller-এর সক্ষমতার বেশি।");
      const p=prompt("আপনার প্রস্তাবিত প্রতি ইউনিট মূল্য লিখুন:");if(p===null)return;unitPrice=Number(p);
      if(!Number.isFinite(unitPrice)||unitPrice<=0)return say("প্রতি ইউনিট মূল্য ০-এর বেশি হতে হবে।");
      note=prompt("অতিরিক্ত শর্ত (ঐচ্ছিক):")||null;
    }else if(action==="reject"&&!confirm("এই Quotation প্রত্যাখ্যান করবেন?"))return;
    try{
      const {data,error}=await client().rpc("respond_to_demand_offer",{p_offer_id:offerId,p_action:action,p_quantity:quantity,p_unit_price:unitPrice,p_note:note});
      if(error)throw error;
      say(action==="accept"?"Quotation গ্রহণ হয়েছে এবং Order তৈরি হয়েছে।":action==="counter"?"আপনার Counter-offer Seller-এর কাছে পাঠানো হয়েছে।":"Quotation প্রত্যাখ্যান করা হয়েছে।",true);
      await Promise.all([loadBuyerDashboard(),loadBuyerOrders()]);
    }catch(err){say("Quotation আপডেট হয়নি: "+err.message);}
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
      .select("id,demand_code,product_name,category,subcategory,description,specifications_quality,required_quantity,budget,currency,destination_country,destination_city,required_date,demand_status,created_at")
      .eq("demand_status", "open").order("created_at", { ascending: false }).limit(100);
    if (error) { host.textContent = "প্রকাশ্য চাহিদা লোড হয়নি: " + error.message; return; }
    state.demands = data || [];
    renderDemands();
  }

  function renderDemands() {
    const host = $("demandList");
    if (!host) return;
    if (!state.demands.length) {
      host.innerHTML = '<div class="demand-card muted">এখনো কোনো প্রকাশ্য খোলা Buyer Demand নেই।</div>';
      return;
    }
    host.innerHTML = state.demands.map(d => `<article class="demand-card">
      <span class="tag">${esc(d.category)}</span><span class="tag">${esc(d.subcategory||"")}</span><span class="tag">চলমান</span>
      <h3>${esc(d.product_name)}</h3>
      <p class="demand-description">${esc(d.description)}</p>
      <div class="demand-meta">
        <span>পরিমাণ: <strong>${esc(d.required_quantity)}</strong></span>
        <span>গন্তব্য: <strong>${esc(d.destination_city)}, ${esc(d.destination_country)}</strong></span>
      </div>
      <p><span class="demand-date">প্রয়োজন: ${esc(d.required_date)}</span></p>
      <p class="muted" style="font-size:11px;margin:5px 0 0">Demand ID: ${esc(d.demand_code)}</p>
      ${activeSeller() ? '<span class="muted">Quotation পাঠাতে Seller Dashboard-এর Buyer Demand Inbox দেখুন।</span>' : ""}
    </article>`).join("");
    // Seller quotations are sent only from the targeted Buyer Demand Inbox.
  }

  async function submitDemandQuotation(form,demandId){
    if(!activeSeller()||!signedIn())return say("Quotation পাঠাতে Active Seller লগইন প্রয়োজন।");
    if(!state.business||state.business.approval_status!=="approved")return say("Quotation পাঠাতে Admin অনুমোদিত Business Profile প্রয়োজন।");
    const v=Object.fromEntries(new FormData(form));
    const price=Number(v.offer_price),deliveryCharge=v.delivery_charge===""?null:Number(v.delivery_charge);
    if(!Number.isFinite(price)||price<=0)return say("প্রতি ইউনিট বা মোট মূল্য শূন্যের বেশি দিন।");
    if(!currencyOK(String(v.currency||"").toUpperCase()))return say("সঠিক Currency নির্বাচন করুন।");
    if(!Number.isFinite(Number(v.available_quantity))||Number(v.available_quantity)<=0)return say("সরবরাহযোগ্য পরিমাণ সঠিকভাবে লিখুন।");
    if(deliveryCharge!==null&&(!Number.isFinite(deliveryCharge)||deliveryCharge<0))return say("ডেলিভারি চার্জ সঠিকভাবে লিখুন।");
    const button=form.querySelector('button[type="submit"]');if(button)button.disabled=true;
    try{
      const {error}=await client().from("seller_offers").insert({
        demand_id:demandId,seller_id:user().id,offer_price:price,currency:String(v.currency).toUpperCase(),
        available_quantity:String(v.available_quantity),message:String(v.message||"").trim()||null,
        product_brand:String(v.product_brand||"").trim()||null,product_model:String(v.product_model||"").trim()||null,
        product_condition:v.product_condition||null,price_basis:v.price_basis||"per_unit",
        estimated_delivery_date:v.estimated_delivery_date||null,warranty:String(v.warranty||"").trim()||null,
        offer_valid_until:v.offer_valid_until||null,delivery_charge:deliveryCharge
      });
      if(error)throw error;
      say("আপনার Quotation Buyer-এর কাছে পাঠানো হয়েছে।",true);
      await loadSellerDemandInbox();
    }catch(err){say("Quotation পাঠানো যায়নি: "+err.message);if(button)button.disabled=false;}
  }

  async function respondToDemandQuotationSeller(offerId,action,currentQuantity){
    if(!activeSeller()||!signedIn())return say("Active Seller লগইন প্রয়োজন।");
    let quantity=null,unitPrice=null,note=null;
    if(action==="counter"){
      const q=prompt("আপনি কত ইউনিট সরবরাহ করতে পারবেন? Buyer-এর প্রস্তাবিত পরিমাণ "+currentQuantity+"।",String(currentQuantity));if(q===null)return;quantity=Number(q);
      if(!Number.isFinite(quantity)||quantity<=0)return say("পরিমাণ ০-এর বেশি হতে হবে।");
      const p=prompt("আপনার প্রস্তাবিত প্রতি ইউনিট মূল্য লিখুন:");if(p===null)return;unitPrice=Number(p);
      if(!Number.isFinite(unitPrice)||unitPrice<=0)return say("প্রতি ইউনিট মূল্য ০-এর বেশি হতে হবে।");
      note=prompt("Buyer-এর জন্য অতিরিক্ত শর্ত (ঐচ্ছিক):")||null;
    }else if(action==="reject"&&!confirm("Buyer-এর Counter-offer প্রত্যাখ্যান করবেন?"))return;
    else if(action==="accept"&&!confirm("Buyer-এর Counter-offer গ্রহণ করে Order তৈরি করবেন?"))return;
    try{
      const {data,error}=await client().rpc("respond_to_demand_offer",{p_offer_id:offerId,p_action:action,p_quantity:quantity,p_unit_price:unitPrice,p_note:note});
      if(error)throw error;
      say(action==="accept"?"Counter গ্রহণ হয়েছে এবং Order তৈরি হয়েছে।":action==="counter"?"আপনার নতুন Counter-offer Buyer-এর কাছে পাঠানো হয়েছে।":"Counter-offer প্রত্যাখ্যান করা হয়েছে।",true);
      await Promise.all([loadSellerDemandInbox(),loadSellerOrders()]);
    }catch(err){say("Quotation response ব্যর্থ: "+err.message);}
  }

  async function loadSellerDemandInbox(){
    const host=$("matchedDemands");if(!host)return;
    if(!activeSeller()||!signedIn()){host.textContent="Active Seller হিসেবে লগইন করুন।";return;}
    if(!state.business||state.business.approval_status!=="approved"){host.textContent="Buyer Demand Inbox দেখতে Admin অনুমোদিত Business Profile প্রয়োজন।";return;}
    host.innerHTML='<p class="muted">আপনার জন্য প্রাসঙ্গিক Buyer Demand খোঁজা হচ্ছে…</p>';
    try{
      const {data,error}=await client().from("buyer_demand_inbox")
        .select("id,created_at,buyer_demands!inner(id,demand_code,product_name,category,subcategory,description,specifications_quality,required_quantity,budget,currency,destination_country,destination_city,required_date,demand_status)")
        .eq("seller_id",user().id).eq("buyer_demands.demand_status","open")
        .order("created_at",{ascending:false}).limit(100);
      if(error)throw error;
      const rows=(data||[]).map(r=>({...r.buyer_demands,inbox_created_at:r.created_at})).filter(d=>d.id);
      if(!rows.length){host.innerHTML='<p class="muted">আপনার অনুমোদিত পণ্যের Category ও Subcategory-এর সঙ্গে মেলে এমন কোনো খোলা Buyer Demand নেই। নতুন মিল পাওয়া গেলে এখানে আসবে।</p>';return;}
      const ids=rows.map(d=>d.id);
      const {data:offers,error:offerError}=await client().from("seller_offers")
        .select("id,demand_id,offer_price,currency,available_quantity,product_brand,product_model,product_condition,price_basis,estimated_delivery_date,warranty,offer_valid_until,delivery_charge,message,offer_status,negotiation_status,current_quantity,current_unit_price,last_negotiator_id,demand_order_id")
        .eq("seller_id",user().id).in("demand_id",ids);
      if(offerError)throw offerError;
      const sent=new Map((offers||[]).map(o=>[o.demand_id,o]));
      host.innerHTML=rows.map(d=>{
        const offer=sent.get(d.id);
        return '<article class="card nx-demand-inbox-card"><div class="section-head"><div><span class="tag">'+esc(d.category)+'</span><span class="tag">'+esc(d.subcategory||"সব Subcategory")+'</span></div><strong>'+esc(d.demand_code)+'</strong></div><h3>'+esc(d.product_name)+'</h3><p>'+esc(d.description)+'</p><p class="muted"><b>স্পেসিফিকেশন:</b> '+esc(d.specifications_quality||"উল্লেখ করা হয়নি")+'</p><div class="grid"><div><small>পরিমাণ</small><strong>'+esc(d.required_quantity)+'</strong></div><div><small>Buyer বাজেট</small><strong>'+(d.budget===null?"উল্লেখ নেই":esc(d.budget+" "+d.currency))+'</strong></div><div><small>গন্তব্য</small><strong>'+esc([d.destination_city,d.destination_country].filter(Boolean).join(", "))+'</strong></div></div><p class="muted">প্রয়োজনের তারিখ: <b>'+esc(d.required_date)+'</b></p>'+
        (offer?'<div class="offer"><strong>আপনার পাঠানো Quotation</strong><p class="price">'+esc(offer.current_unit_price||offer.offer_price)+' '+esc(offer.currency)+' / ইউনিট</p><p class="muted">'+esc(offer.current_quantity||offer.available_quantity)+' ইউনিটের শর্ত · সর্বোচ্চ '+esc(offer.available_quantity)+' সরবরাহযোগ্য</p><p class="muted">আলোচনার অবস্থা: '+esc(({open:"Buyer-এর জবাবের অপেক্ষায়",buyer_countered:"আপনার জবাবের অপেক্ষায়",seller_countered:"Buyer-এর জবাবের অপেক্ষায়",ordered:"Order তৈরি হয়েছে",declined:"প্রত্যাখ্যাত"})[offer.negotiation_status]||offer.offer_status)+'</p>'+(offer.negotiation_status==="buyer_countered"&&!offer.demand_order_id?'<div class="form-actions"><button class="primary" type="button" data-seller-quote-action="accept" data-offer-id="'+esc(offer.id)+'" data-quantity="'+esc(offer.current_quantity)+'">Buyer-এর Counter গ্রহণ</button><button class="light" type="button" data-seller-quote-action="counter" data-offer-id="'+esc(offer.id)+'" data-quantity="'+esc(offer.current_quantity)+'">নতুন Counter দিন</button><button class="danger" type="button" data-seller-quote-action="reject" data-offer-id="'+esc(offer.id)+'">প্রত্যাখ্যান</button></div>':'')+'</div>':
        '<form class="nx-demand-quote-form card" data-quote-demand="'+esc(d.id)+'"><h4>এই Demand-এর জন্য Quotation দিন</h4><div class="grid"><label>ব্র্যান্ড<input name="product_brand" maxlength="100" placeholder="যেমন: Samsung"></label><label>মডেল<input name="product_model" maxlength="120" placeholder="যেমন: Galaxy A55"></label></div><div class="grid"><label>পণ্যের অবস্থা<select name="product_condition"><option value="new">নতুন</option><option value="refurbished">রিফারবিশড</option><option value="used">ব্যবহৃত</option><option value="any">যেকোনো</option></select></label><label>মূল্যের ধরন<select name="price_basis"><option value="per_unit">প্রতি ইউনিট</option><option value="total">মোট মূল্য</option></select></label></div><div class="grid"><label>প্রস্তাবিত মূল্য *<input name="offer_price" type="number" min="0.01" step="0.01" required></label><label>মুদ্রা *<select name="currency"><option value="BDT">BDT</option><option value="USD">USD</option><option value="EUR">EUR</option><option value="GBP">GBP</option><option value="CNY">CNY</option></select></label><label>সরবরাহ করতে পারবেন *<input name="available_quantity" type="number" min="0.001" step="0.001" required></label><label>ডেলিভারি চার্জ (ঐচ্ছিক)<input name="delivery_charge" type="number" min="0" step="0.01"></label></div><div class="grid"><label>সম্ভাব্য সরবরাহের তারিখ<input name="estimated_delivery_date" type="date"></label><label>Quotation-এর মেয়াদ<input name="offer_valid_until" type="date"></label></div><label>ওয়ারেন্টি / গ্যারান্টি<input name="warranty" maxlength="300" placeholder="যেমন: ১ বছর অফিসিয়াল ওয়ারেন্টি"></label><label>অতিরিক্ত শর্ত ও বিবরণ<textarea name="message" maxlength="2000" placeholder="পণ্যের বৈশিষ্ট্য, accessories, delivery terms, payment terms ইত্যাদি"></textarea></label><button class="primary" type="submit">Quotation পাঠান</button></form>')+'</article>';
      }).join("");
      host.querySelectorAll("form[data-quote-demand]").forEach(form=>form.addEventListener("submit",e=>{e.preventDefault();submitDemandQuotation(form,form.dataset.quoteDemand);}));
       host.querySelectorAll("button[data-seller-quote-action]").forEach(b=>b.addEventListener("click",()=>respondToDemandQuotationSeller(b.dataset.offerId,b.dataset.sellerQuoteAction,Number(b.dataset.quantity)||null)));
    }catch(err){host.textContent="Buyer Demand Inbox লোড হয়নি: "+err.message;}
  }

  const serviceCategoryLabels = {
    household:"গৃহস্থালি সেবা",tutoring:"শিক্ষা ও টিউশন",plumbing:"প্লাম্বিং",
    electrical:"ইলেকট্রিক্যাল",mechanic:"মেকানিক ও মেরামত",
    appliance_repair:"ইলেকট্রনিক/হোম অ্যাপ্লায়েন্স মেরামত",
    it_support:"আইটি ও কম্পিউটার",beauty_laundry:"বিউটি ও লন্ড্রি",other:"অন্যান্য"
  };
  const servicePriceLabels = {
    negotiable:"আলোচনা সাপেক্ষে",per_hour:"প্রতি ঘণ্টা",per_day:"প্রতি দিন",
    per_visit:"প্রতি ভিজিট",per_job:"প্রতি কাজ",per_month:"প্রতি মাস"
  };
  const serviceCategoryIcons = {
    household:"🧹",tutoring:"📚",plumbing:"🔧",electrical:"⚡",mechanic:"🛠️",
    appliance_repair:"🧰",it_support:"💻",beauty_laundry:"✨",other:"🧑‍🔧"
  };
  function renderServiceCards(rows,host) {
    if(!host)return;
    const detailPanel=$("nxServiceDetailPanel");
    const requestedService=new URLSearchParams(window.location.search).get("service");
    const selected=requestedService?(state.services||[]).find(s=>s.service_code===requestedService):null;
    if(requestedService){
      host.classList.add("hidden");
      $("nxServiceFilters")?.classList.add("hidden");
      if(detailPanel){
        detailPanel.classList.remove("hidden");
        if(!selected){
          detailPanel.innerHTML='<p class="muted">সেবাটি পাওয়া যায়নি অথবা বর্তমানে অনুমোদিত নয়।</p><a class="nx-back-link" href="'+esc(window.location.pathname)+'">← সেবা মার্কেটপ্লেসে ফিরে যান</a>';
        }else{
          const amount=selected.price_amount!==null&&selected.price_amount!==undefined?esc(Number(selected.price_amount).toLocaleString("en-US"))+" "+esc(selected.currency)+" · ":"";
          detailPanel.innerHTML=`
            <a class="nx-back-link" href="${esc(window.location.pathname)}">← সব সেবা দেখুন</a>
            <div class="nx-service-detail-hero">
              ${selected.image_urls?.[0]?'<img class="nx-service-detail-image" src="'+esc(selected.image_urls[0])+'" alt="'+esc(selected.service_name)+'" loading="lazy">':'<span class="nx-service-detail-icon" aria-hidden="true">'+(serviceCategoryIcons[selected.service_category]||"🧰")+'</span>'}
              <div><span class="tag">${esc(serviceCategoryLabels[selected.service_category]||selected.service_category)}</span><span class="nx-service-detail-kicker">NEXORA SERVICE</span><h1>${esc(selected.service_name)}</h1><p>${esc([selected.service_area,selected.city,selected.country].filter(Boolean).join(", "))}</p></div>
            </div>
            <div class="nx-service-detail-grid">
              <section class="nx-service-detail-main"><h2>সেবার বিবরণ</h2><p>${esc(selected.description)}</p><h3>সেবার এলাকা</h3><p>${esc([selected.service_area,selected.city,selected.country].filter(Boolean).join(", ")||"তথ্য দেওয়া হয়নি")}</p><h3>সময় ও Availability</h3><p>${esc(selected.availability||"সেবাদাতার সঙ্গে আলোচনা করুন")}</p></section>
              <aside class="nx-service-detail-aside"><span class="nx-service-detail-kicker">PRICE</span><strong>${amount}${esc(servicePriceLabels[selected.price_basis]||"আলোচনা সাপেক্ষে")}</strong><small>Service ID: ${esc(selected.service_code)}</small><p>সেবাদাতার ব্যক্তিগত ফোন নম্বর ও সঠিক বাসার ঠিকানা প্রকাশ করা হয় না। যোগাযোগের সুবিধা চালু হলে এই পৃষ্ঠা থেকে অনুরোধ করা যাবে।</p></aside>
            </div>${activeBuyer()&&signedIn()&&selected.price_amount?`<form id="nxServiceOrderForm" class="card nx-order-form"><h3>সেবা বুকিং অনুরোধ</h3><label>সেবা গ্রহণের ঠিকানা/এলাকা *<textarea name="location" minlength="5" maxlength="500" required></textarea></label><label>কাজের বিবরণ (ঐচ্ছিক)<textarea name="note" maxlength="1500"></textarea></label><button class="primary" type="submit">সেবা বুকিং অনুরোধ পাঠান</button><p data-order-status aria-live="polite"></p><small class="muted">আলোচনা সাপেক্ষ মূল্য হলে আগে Seller-এর সঙ্গে মূল্য নিশ্চিত করুন।</small></form>`:""}<section id="nxServiceReviews" class="nx-listing-reviews" aria-live="polite"></section>`;
          loadListingReviews("service",selected.id,"nxServiceReviews");
          $("nxServiceOrderForm")?.addEventListener("submit",e=>{e.preventDefault();const v=new FormData(e.currentTarget);submitCommerceOrder("service",selected.id,1,v.get("location"),v.get("note"),e.currentTarget.querySelector("[data-order-status]"),e.currentTarget.querySelector("button[type=submit]"));});
        }
      }
      return;
    }
    $("nxServiceFilters")?.classList.remove("hidden");
    if(detailPanel)detailPanel.classList.add("hidden");
    host.classList.remove("hidden");
    if(!rows.length){host.innerHTML='<div class="card muted nx-empty-market">এই অনুসন্ধানে কোনো অনুমোদিত সেবা পাওয়া যায়নি।</div>';return;}
    host.innerHTML=rows.map(s=>{
      const icon=serviceCategoryIcons[s.service_category]||"🧰";
      const amount=s.price_amount!==null&&s.price_amount!==undefined?esc(Number(s.price_amount).toLocaleString("en-US"))+" "+esc(s.currency)+" · ":"";
      return `<article class="card nx-service-card">
        <a class="nx-service-card-art" href="?service=${encodeURIComponent(s.service_code)}" aria-label="${esc(s.service_name)} বিস্তারিত দেখুন">${s.image_urls?.[0]?'<img class="nx-service-uploaded-image" src="'+esc(s.image_urls[0])+'" alt="'+esc(s.service_name)+'" loading="lazy">':'<span aria-hidden="true">'+icon+'</span>'}<small>NEXORA SERVICES</small></a>
        <div class="nx-service-card-body"><span class="tag">${esc(serviceCategoryLabels[s.service_category]||s.service_category)}</span><h3><a href="?service=${encodeURIComponent(s.service_code)}">${esc(s.service_name)}</a></h3><p class="nx-service-card-description">${esc(s.description)}</p><p class="muted">📍 ${esc([s.service_area,s.city,s.country].filter(Boolean).join(", "))}</p><div class="nx-service-card-footer"><strong>${amount}${esc(servicePriceLabels[s.price_basis]||"আলোচনা সাপেক্ষে")}</strong><a href="?service=${encodeURIComponent(s.service_code)}">বিস্তারিত <span aria-hidden="true">→</span></a></div><small class="muted">Service ID: ${esc(s.service_code)}</small></div>
      </article>`;
    }).join("");
  }
  async function loadServicesMarketplace() {
    const host=$("nxServiceList"); if(!host)return;
    host.innerHTML='<p class="muted">সেবা লোড হচ্ছে…</p>';
    try{
      const {data,error}=await client().from("service_listings")
        .select("id,service_code,service_name,service_category,description,country,city,service_area,price_basis,price_amount,currency,availability,image_urls")
        .eq("listing_status","approved").order("created_at",{ascending:false}).limit(100);
      if(error)throw error;
      state.services=data||[];
      applyServiceFilters();
    }catch(err){host.innerHTML='<div class="card muted">সেবা তালিকা এখনো চালু হয়নি। Database migration প্রয়োগের পর এখানে অনুমোদিত সেবা দেখা যাবে।</div>';console.warn("Services marketplace unavailable:",err.message);}
  }
  function applyServiceFilters(){
    const term=String($("nxServiceSearch")?.value||"").trim().toLowerCase();
    const category=$("nxServiceCategoryFilter")?.value||"";
    const area=String($("nxServiceAreaFilter")?.value||"").trim().toLowerCase();
    const rows=(state.services||[]).filter(s=>
      (!category||s.service_category===category)&&
      (!area||[s.service_area,s.city,s.country].join(" ").toLowerCase().includes(area))&&
      (!term||[s.service_name,s.description,s.service_area,s.city,s.country,serviceCategoryLabels[s.service_category]].join(" ").toLowerCase().includes(term))
    );
    if($("nxServiceCount"))$("nxServiceCount").textContent=rows.length+"টি সেবা";
    renderServiceCards(rows,$("nxServiceList"));
  }
  ["nxServiceSearch","nxServiceCategoryFilter","nxServiceAreaFilter"].forEach(id=>{
    $(id)?.addEventListener($(id)?.tagName==="SELECT"?"change":"input",applyServiceFilters);
  });
  async function loadSellerServices(){
    const host=$("nxSellerServiceList"); if(!host)return;
    if(!activeSeller()||!signedIn()){host.textContent="সক্রিয় Seller হিসেবে লগইন করুন।";return;}
    try{
      const {data,error}=await client().from("service_listings")
        .select("id,service_code,service_name,service_category,description,country,city,service_area,price_basis,price_amount,currency,availability,listing_status,admin_note,image_urls")
        .eq("seller_id",user().id).order("created_at",{ascending:false});
      if(error)throw error;
      if(!data?.length){host.innerHTML='<p class="muted">আপনি এখনো কোনো সেবা যোগ করেননি।</p>';return;}
      window.NEXORA_SELLER_SERVICES=data;
      host.innerHTML=data.map(s=>'<article class="card" data-seller-service>'+(s.image_urls?.[0]?'<img class="product-image" src="'+esc(s.image_urls[0])+'" alt="'+esc(s.service_name)+'" loading="lazy">':'')+'<div class="section-head"><strong>'+esc(s.service_name)+'</strong><span class="tag">'+esc(({pending:"পর্যালোচনাধীন",approved:"অনুমোদিত",rejected:"প্রত্যাখ্যাত",suspended:"স্থগিত"})[s.listing_status]||s.listing_status)+'</span></div><p class="muted">'+esc(serviceCategoryLabels[s.service_category]||s.service_category)+' · '+esc(s.service_area)+' · '+esc(s.city)+'</p><small>Service ID: '+esc(s.service_code)+'</small>'+(s.admin_note?'<p class="muted">Admin Note: '+esc(s.admin_note)+'</p>':'')+(s.listing_status==="pending"?'<div class="form-actions"><button class="primary" type="button" data-edit-service="'+esc(s.id)+'">সেবা সম্পাদনা</button><button class="danger" type="button" data-delete-service="'+esc(s.id)+'">Pending সেবা মুছুন</button></div>':s.listing_status==="approved"?'<div class="form-actions"><button class="light" type="button" data-request-service-edit="'+esc(s.id)+'">পরিবর্তন প্রস্তাব করুন</button></div>':'')+'</article>').join("");
      host.querySelectorAll("[data-delete-service]").forEach(b=>b.addEventListener("click",()=>deleteService(b.dataset.deleteService)));
    }catch(err){host.innerHTML='<p class="muted">সেবা তালিকা লোড হয়নি: '+esc(err.message)+'</p>';}
  }
  async function deleteService(id){
    if(!confirm("এই pending সেবাটি মুছে ফেলতে চান?"))return;
    const {data:service,error:readError}=await client().from("service_listings").select("image_urls").eq("id",id).single();
    if(readError)return say("সেবার তথ্য পাওয়া যায়নি: "+readError.message);
    const {error}=await client().from("service_listings").delete().eq("id",id);
    if(error)return say("সেবা মুছতে সমস্যা: "+error.message);
    await removeListingImages(listingImagePathsFromUrls(service?.image_urls||[]));
    say("Pending সেবা মুছে ফেলা হয়েছে।",true);await loadSellerServices();
  }
  async function loadAdminServiceQueue(){
    const host=$("nxAdminServiceQueue");if(!host)return;
    if(!signedIn()||profile()?.role!=="admin"||profile()?.account_status!=="active"){
      host.textContent="শুধু সক্রিয় Admin সেবা পর্যালোচনা করতে পারবেন।";return;
    }
    host.innerHTML='<p class="muted">সেবা আবেদন লোড হচ্ছে…</p>';
    try{
      const {data,error}=await client().from("service_listings")
        .select("id,service_code,service_name,service_category,description,country,city,service_area,price_basis,price_amount,currency,availability,listing_status,seller_id,image_urls")
        .in("listing_status",["pending","approved"]).order("created_at",{ascending:true}).limit(100);
      if(error)throw error;
      host.innerHTML=(data||[]).map(s=>'<article class="card">'+(s.image_urls?.length?'<div class="nx-upload-preview">'+s.image_urls.map(url=>'<img src="'+esc(url)+'" alt="'+esc(s.service_name)+'" loading="lazy">').join('')+'</div>':'')+'<div class="section-head"><strong>'+esc(s.service_name)+'</strong><span class="tag">'+esc(s.listing_status)+'</span></div><p>'+esc(s.description)+'</p><p class="muted">'+esc(serviceCategoryLabels[s.service_category]||s.service_category)+' · '+esc(s.service_area)+' · '+esc([s.city,s.country].join(", "))+'</p><p class="muted">'+esc(servicePriceLabels[s.price_basis]||s.price_basis)+' '+(s.price_amount!==null?esc(s.price_amount)+" "+esc(s.currency):"")+'</p>'+(s.listing_status==="pending"?'<div class="grid"><button class="primary" type="button" data-service-review="approve" data-service-id="'+esc(s.id)+'">Approve</button><button class="danger" type="button" data-service-review="reject" data-service-id="'+esc(s.id)+'">Reject</button></div>':'')+'</article>').join("")||'<p class="muted">কোনো Pending সেবা নেই।</p>';
      host.querySelectorAll("[data-service-review]").forEach(b=>b.addEventListener("click",()=>reviewService(b.dataset.serviceId,b.dataset.serviceReview)));
    }catch(err){host.textContent="সেবা পর্যালোচনা লোড হয়নি: "+err.message;}
  }
  async function reviewService(id,action){
    const reason=action==="reject"?prompt("প্রত্যাখ্যানের কারণ লিখুন (কমপক্ষে ৫ অক্ষর):"):"";
    if(action==="reject"&&(!reason||reason.trim().length<5))return say("প্রত্যাখ্যানের কারণ আবশ্যক।");
    const {error}=await client().from("service_listings").update({
      listing_status:action==="approve"?"approved":"rejected",
      admin_note:reason.trim()||null,reviewed_by:user().id,reviewed_at:new Date().toISOString()
    }).eq("id",id).eq("listing_status","pending");
    if(error)return say("সেবা পর্যালোচনা ব্যর্থ: "+error.message);
    say(action==="approve"?"সেবা অনুমোদিত হয়েছে।":"সেবা প্রত্যাখ্যান করা হয়েছে।",true);
    await loadAdminServiceQueue();await loadServicesMarketplace();
  }
  $("nxServiceForm")?.addEventListener("submit",async e=>{
    e.preventDefault();const form=e.currentTarget;
    if(!activeSeller()||!signedIn())return say("সেবা যোগ করতে সক্রিয় Seller হিসেবে লগইন করুন।");
    if(!state.business||state.business.approval_status!=="approved")return say("সেবা যোগ করার আগে Admin-এর Business Profile অনুমোদন প্রয়োজন।");
    const v=Object.fromEntries(new FormData(form));
    const imageFiles=Array.from(form.querySelector('[name="service_image_files"]')?.files||[]);
    if(imageFiles.length>3)return say("সর্বোচ্চ ৩টি Service Image আপলোড করুন।");
    if(v.price_amount!==""&&(!Number.isFinite(Number(v.price_amount))||Number(v.price_amount)<0))return say("সঠিক মূল্য লিখুন।");
    setBusy(form,true);
    let uploadedPaths=[];
    try{
      const uploaded=await uploadListingImages(imageFiles,"services");
      uploadedPaths=uploaded.paths;
      const {error}=await client().from("service_listings").insert({
        seller_id:user().id,business_id:state.business.id,
        service_name:v.service_name.trim(),service_category:v.service_category,
        description:v.description.trim(),country:v.country.trim(),city:v.city.trim(),
        service_area:v.service_area.trim(),price_basis:v.price_basis,
        price_amount:v.price_amount===""?null:Number(v.price_amount),
        currency:String(v.currency||"BDT").toUpperCase(),availability:v.availability.trim()||null,
        image_urls:uploaded.urls
      });
      if(error)throw error;
      form.reset();form.classList.add("hidden");
      $("nxServiceImageFiles")?.dispatchEvent(new Event("change"));
      say("সেবা ও ছবি Admin Review-এ পাঠানো হয়েছে। অনুমোদনের পর Marketplace-এ দেখা যাবে।",true);
      await loadSellerServices();
    }catch(err){
      if(uploadedPaths.length)await removeListingImages(uploadedPaths);
      say("সেবা সংরক্ষণ হয়নি: "+err.message);
    }
    finally{setBusy(form,false);}
  });

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
      await loadSellerServices();
      await loadSellerOrders();
      await loadSellerPriceNegotiations();
      const { data, error } = await client().from("products")
        .select("id,product_code,product_name,category,subcategory,origin,price,currency,listing_status,image_urls,description,specifications_quality,minimum_order_quantity,stock_tracking,stock_quantity,reserved_quantity,price_tiers")
        .eq("seller_id", user().id).order("created_at", { ascending: false });
      if (error) throw error;
      const products = data || [];
      await loadSellerEditRequests();
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

      window.NEXORA_SELLER_PRODUCTS=products;
      const productHost = $("sellerProducts");
      productHost.innerHTML = products.length ? products.map(p => `
        <article class="nx-seller-product-item" data-seller-product data-status="${esc(p.listing_status)}" data-search="${esc([p.product_name,p.category,p.subcategory,p.product_code,p.origin].join(" ").toLowerCase())}">
          <div class="section-head"><strong>${esc(p.product_name)}</strong><span class="tag">${esc(({approved:"অনুমোদিত",pending:"পর্যালোচনাধীন",rejected:"প্রত্যাখ্যাত"})[p.listing_status] || "অবস্থা অজানা")}</span></div>
          ${p.image_urls?.[0]?'<img class="product-image" src="'+esc(p.image_urls[0])+'" alt="'+esc(p.product_name)+'" loading="lazy">':''}
          <p class="muted">${esc(p.category)} · ${esc(p.subcategory||"")} | ${esc(p.origin)}</p>
          <p class="price">${esc(p.price)} ${esc(p.currency)} / ইউনিট · MOQ ${esc(p.minimum_order_quantity||1)}</p>
          <p class="muted">${p.stock_tracking?'স্টক: '+esc(p.stock_quantity)+' · সংরক্ষিত: '+esc(p.reserved_quantity)+' · উপলব্ধ: '+esc(Math.max(0,Number(p.stock_quantity)-Number(p.reserved_quantity))):'স্টক ট্র্যাকিং বন্ধ'}</p>
          <p class="muted">Product ID: ${esc(p.product_code)}</p>
          ${p.listing_status === "pending" ? `<div class="form-actions"><button class="primary" type="button" data-edit-product="${esc(p.id)}">Edit Product</button><button class="danger" type="button" data-delete-product="${esc(p.id)}">Delete pending product</button><button class="light" type="button" data-inventory-product="${esc(p.id)}">স্টক পরিচালনা</button></div>` : p.listing_status === "approved" ? `<div class="form-actions"><button class="light" type="button" data-request-product-edit="${esc(p.id)}">পরিবর্তন প্রস্তাব করুন</button><button class="light" type="button" data-inventory-product="${esc(p.id)}">স্টক পরিচালনা</button></div>` : ""}
        </article>`).join("") : '<p class="muted">এখনো কোনো পণ্য যোগ করা হয়নি। Add Product দিয়ে নতুন পণ্য যোগ করুন।</p>';
      productHost.querySelectorAll("button[data-delete-product]").forEach(b => b.addEventListener("click", () => deleteProduct(b.dataset.deleteProduct)));
      productHost.querySelectorAll("button[data-inventory-product]").forEach(b=>b.addEventListener("click",()=>updateSellerProductInventory(b.dataset.inventoryProduct)));

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

      await loadSellerDemandInbox();
    } catch (err) { say("Seller Dashboard লোড হয়নি: " + err.message); }
  }



  let activeLogisticsPorters = [];
  async function loadAdminPorterOptions() {
    const select=$("nxAdminPorterSelect");
    if(!select)return;
    select.innerHTML='<option value="">Porter তালিকা লোড হচ্ছে…</option>';
    try{
      const {data,error}=await client().rpc("list_active_nexora_porters_for_logistics");
      if(error)throw error;
      activeLogisticsPorters = data || [];
      select.innerHTML='<option value="">Porter নির্বাচন করুন</option>'+activeLogisticsPorters.map(p=>'<option value="'+esc(p.porter_id)+'">'+esc(p.full_name||"Porter")+'</option>').join("");
      if(!activeLogisticsPorters.length)select.innerHTML='<option value="">কোনো সক্রিয় Porter পাওয়া যায়নি</option>';
    }catch(err){
      activeLogisticsPorters = [];
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
          ${["assigned","accepted"].includes(job.status) ? '<div class="nx-logistics-admin-actions"><label>অন্য Porter-কে বরাদ্দ</label><select data-reassign-select="'+esc(job.id)+'"><option value="">Porter নির্বাচন করুন</option>'+activeLogisticsPorters.filter(p=>p.porter_id!==job.assigned_porter_id).map(p=>'<option value="'+esc(p.porter_id)+'">'+esc(p.full_name||"Porter")+'</option>').join("")+'</select><button type="button" class="light" data-logistics-action="reassign" data-job-id="'+esc(job.id)+'">Reassign</button><button type="button" class="danger" data-logistics-action="cancel" data-job-id="'+esc(job.id)+'">Cancel Job</button></div>' : ""}
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
  $("nxAdminLogisticsJobs")?.addEventListener("click",async e=>{
    const button=e.target.closest("[data-logistics-action]");
    if(!button)return;
    const jobId=button.dataset.jobId, action=button.dataset.logisticsAction;
    if(action==="reassign"){
      const select=$("nxAdminLogisticsJobs").querySelector('[data-reassign-select="'+CSS.escape(jobId)+'"]');
      const newPorterId=select?.value;
      if(!newPorterId)return say("নতুন Porter নির্বাচন করুন।");
      const note=window.prompt("কেন অন্য Porter-কে কাজটি দিচ্ছেন? (কমপক্ষে ৫ অক্ষর)","");
      if(note===null)return;
      if(note.trim().length<5)return say("কমপক্ষে ৫ অক্ষরের কারণ লিখুন।");
      if(!window.confirm("এই কাজটি নতুন Porter-কে বরাদ্দ করবেন?"))return;
      button.disabled=true;
      try{
        const {error}=await client().rpc("admin_reassign_porter_delivery_job",{
          p_job_id:jobId,p_new_porter_id:newPorterId,p_note:note.trim()
        });
        if(error)throw error;
        say("ডেলিভারি কাজ নতুন Porter-কে বরাদ্দ হয়েছে।",true);
        await loadAdminLogisticsMonitor();
      }catch(err){say("Reassign করা যায়নি: "+err.message);}
      finally{button.disabled=false;}
    }else if(action==="cancel"){
      const note=window.prompt("কাজটি বাতিলের কারণ লিখুন (কমপক্ষে ৫ অক্ষর):","");
      if(note===null)return;
      if(note.trim().length<5)return say("কমপক্ষে ৫ অক্ষরের কারণ লিখুন।");
      if(!window.confirm("এই ডেলিভারি কাজটি বাতিল করবেন?"))return;
      button.disabled=true;
      try{
        const {error}=await client().rpc("admin_cancel_porter_delivery_job",{
          p_job_id:jobId,p_note:note.trim()
        });
        if(error)throw error;
        say("ডেলিভারি কাজ বাতিল হয়েছে।",true);
        await loadAdminLogisticsMonitor();
      }catch(err){say("কাজ বাতিল করা যায়নি: "+err.message);}
      finally{button.disabled=false;}
    }
  });
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
    const host = $("nxPorterWorkspaceStatus");
    if (!host) return;
    if (!signedIn() || !activePorter()) {
      host.textContent = "সক্রিয় ও Admin-অনুমোদিত Porter অ্যাকাউন্ট প্রয়োজন।";
      return;
    }
    host.innerHTML = '<p><strong>আপনার Porter Account সক্রিয় ও অনুমোদিত।</strong></p>' +
      '<p class="muted">Transport Provider Center থেকে ব্যক্তি-ভিত্তিক Provider Profile এবং Vehicle নিবন্ধন করুন। Provider ও প্রতিটি Vehicle Admin অনুমোদনের পরই Delivery Assignment-এর যোগ্য হবে। পুরোনো Porter job-table ব্যবহার করা হচ্ছে না।</p>';
  }


  function renderExistingImageChecks(urls,kind) {
    return (urls||[]).map((url,index)=>'<div class="nx-existing-image"><img src="'+esc(url)+'" alt="বর্তমান ছবি '+(index+1)+'" loading="lazy"><label><input type="checkbox" data-existing-image-index="'+index+'" data-image-kind="'+kind+'" checked> রাখুন</label></div>').join("");
  }

  function renderProductEditor(p,requestMode=false) {
    const id=String(p.id), safeId=id.replace(/[^a-zA-Z0-9_-]/g,"");
    const categories=["Food & Agriculture","Textile & Garments","Electronics","Industrial Products","Handicrafts","Other"];
    const categoryOptions=categories.map(v=>'<option '+(p.category===v?"selected":"")+'>'+esc(v)+'</option>').join("");
    const currencies=["BDT","USD","EUR","GBP","CNY"];
    const currencyOptions=currencies.map(v=>'<option '+(p.currency===v?"selected":"")+'>'+v+'</option>').join("");
    return '<form class="nx-listing-editor" '+(requestMode?'data-request-product-form="'+esc(id)+'"':'data-edit-product-form="'+esc(id)+'')+'>'+
      '<h4>পণ্য সম্পাদনা · '+esc(p.product_code)+'</h4>'+
      '<label>Product Name *<input name="name" required maxlength="180" value="'+esc(p.product_name)+'"></label>'+
      '<label>Product Category *<select name="category" required>'+categoryOptions+'</select></label>'+
      '<label>Product Subcategory *<input name="subcategory" required minlength="2" maxlength="120" value="'+esc(p.subcategory||"")+'" placeholder="যেমন: Mobile Phones"></label>'+
      '<label>বর্তমান ছবি — যেগুলো রাখতে চান সেগুলোতে টিক রাখুন</label><div class="nx-existing-images">'+renderExistingImageChecks(p.image_urls||[],"product")+'</div>'+
      '<label>নতুন ছবি যোগ করুন (প্রতিটি সর্বোচ্চ ৫ MB)</label><input id="nxEditProductFiles-'+safeId+'" name="image_files" type="file" accept="image/jpeg,image/png,image/webp,image/avif" multiple>'+
      '<div id="nxEditProductPreview-'+safeId+'" class="nx-upload-preview"></div>'+
      '<label>নতুন বাইরের HTTPS Image URL (ঐচ্ছিক, প্রতি লাইনে একটি)</label><textarea name="images" placeholder="https://example.com/image.jpg"></textarea>'+
      '<label>Product Description *<textarea name="description" required>'+esc(p.description||"")+'</textarea></label>'+
      '<label>Origin *<input name="origin" required value="'+esc(p.origin||"")+'"></label>'+
      '<label>Specifications & Quality<textarea name="specifications">'+esc(p.specifications_quality||"")+'</textarea></label>'+
      '<div class="grid"><label>MOQ *<input name="minimum_order_quantity" type="number" min="1" step="0.001" required value="'+esc(p.minimum_order_quantity||1)+'"></label><label>পরিমাণভিত্তিক মূল্য (ঐচ্ছিক)<textarea name="price_tiers" placeholder="100=95">'+(p.price_tiers||[]).map(t=>esc(t.min_quantity+"="+t.unit_price)).join("\n")+'</textarea></label></div>'+
      '<div class="grid"><label>মূল্য *<input name="price" type="number" min="0.01" step="0.01" required value="'+esc(p.price)+'"></label>'+
      '<label>Currency *<select name="currency" required>'+currencyOptions+'</select></label></div>'+
      '<div class="form-actions"><button class="primary" type="submit">'+(requestMode?'পরিবর্তন Admin Review-এ পাঠান':'পরিবর্তন সংরক্ষণ')+'</button><button class="light" type="button" data-cancel-listing-edit>বাতিল</button></div>'+
      '</form>';
  }

  function renderServiceEditor(s,requestMode=false) {
    const id=String(s.id), safeId=id.replace(/[^a-zA-Z0-9_-]/g,"");
    const cats=[["household","গৃহস্থালি সেবা"],["tutoring","শিক্ষা ও টিউশন"],["plumbing","প্লাম্বিং"],["electrical","ইলেকট্রিক্যাল"],["mechanic","মেকানিক ও মেরামত"],["appliance_repair","ইলেকট্রনিক/হোম অ্যাপ্লায়েন্স মেরামত"],["it_support","আইটি ও কম্পিউটার"],["beauty_laundry","বিউটি ও লন্ড্রি"],["other","অন্যান্য"]];
    const bases=[["negotiable","আলোচনা সাপেক্ষে"],["per_hour","প্রতি ঘণ্টা"],["per_day","প্রতি দিন"],["per_visit","প্রতি ভিজিট"],["per_job","প্রতি কাজ"],["per_month","প্রতি মাস"]];
    const opts=(items,value)=>items.map(([v,label])=>'<option value="'+v+'" '+(value===v?"selected":"")+'>'+label+'</option>').join("");
    return '<form class="nx-listing-editor" '+(requestMode?'data-request-service-form="'+esc(id)+'"':'data-edit-service-form="'+esc(id)+'')+'>'+
      '<h4>সেবা সম্পাদনা · '+esc(s.service_code)+'</h4>'+
      '<label>সেবার নাম *<input name="service_name" required minlength="2" maxlength="160" value="'+esc(s.service_name)+'"></label>'+
      '<label>সেবার বিভাগ *<select name="service_category" required>'+opts(cats,s.service_category)+'</select></label>'+
      '<label>সেবার বিবরণ *<textarea name="description" required minlength="20" maxlength="3000">'+esc(s.description||"")+'</textarea></label>'+
      '<div class="grid"><label>দেশ *<input name="country" required maxlength="100" value="'+esc(s.country||"")+'"></label><label>শহর / জেলা *<input name="city" required maxlength="100" value="'+esc(s.city||"")+'"></label></div>'+
      '<label>সেবা দেওয়ার এলাকা *<input name="service_area" required minlength="2" maxlength="300" value="'+esc(s.service_area||"")+'"></label>'+
      '<div class="grid"><label>মূল্য নির্ধারণ *<select name="price_basis" required>'+opts(bases,s.price_basis)+'</select></label>'+
      '<label>মূল্য (ঐচ্ছিক)<input name="price_amount" type="number" min="0" step="0.01" value="'+(s.price_amount===null||s.price_amount===undefined?"":esc(s.price_amount))+'"></label></div>'+
      '<label>সেবার ছবি — যেগুলো রাখতে চান সেগুলোতে টিক রাখুন</label><div class="nx-existing-images">'+renderExistingImageChecks(s.image_urls||[],"service")+'</div>'+
      '<label>নতুন ছবি যোগ করুন (প্রতিটি সর্বোচ্চ ৫ MB)</label><input id="nxEditServiceFiles-'+safeId+'" name="image_files" type="file" accept="image/jpeg,image/png,image/webp,image/avif" multiple>'+
      '<div id="nxEditServicePreview-'+safeId+'" class="nx-upload-preview"></div>'+
      '<label>নতুন বাইরের HTTPS Image URL (ঐচ্ছিক, প্রতি লাইনে একটি)</label><textarea name="images" placeholder="https://example.com/image.jpg"></textarea>'+
      '<label>মুদ্রা<select name="currency">'+[["BDT","BDT"],["USD","USD"],["EUR","EUR"],["GBP","GBP"],["CNY","CNY"]].map(([v,label])=>'<option value="'+v+'" '+((s.currency||"BDT")===v?"selected":"")+'>'+label+'</option>').join("")+'</select></label>'+
      '<label>Availability<input name="availability" maxlength="300" value="'+esc(s.availability||"")+'"></label>'+
      '<div class="form-actions"><button class="primary" type="submit">'+(requestMode?'পরিবর্তন Admin Review-এ পাঠান':'পরিবর্তন সংরক্ষণ')+'</button><button class="light" type="button" data-cancel-listing-edit>বাতিল</button></div>'+
      '</form>';
  }

  function retainedListingImages(form,oldUrls,kind) {
    return (oldUrls||[]).filter((url,index)=>form.querySelector('[data-existing-image-index="'+index+'"][data-image-kind="'+kind+'"]')?.checked);
  }

  async function saveListingImages(form,oldUrls,kind,maxCount) {
    const kept=retainedListingImages(form,oldUrls,kind);
    const files=Array.from(form.querySelector('[name="image_files"]')?.files||[]);
    const external=String(new FormData(form).get("images")||"").split(/\r?\n/).map(v=>v.trim()).filter(Boolean);
    if(external.some(v=>!/^https:\/\//i.test(v)))throw new Error("প্রতিটি নতুন Image URL অবশ্যই HTTPS হতে হবে।");
    if(kept.length+files.length+external.length>maxCount)throw new Error("মোট ছবি "+maxCount+"টির বেশি হতে পারবে না।");
    const uploaded=await uploadListingImages(files,kind==="product"?"products":"services");
    return {urls:[...kept,...uploaded.urls,...external],uploadedPaths:uploaded.paths,removedPaths:listingImagePathsFromUrls(oldUrls).filter(path=>!listingImagePathsFromUrls(kept).includes(path))};
  }

  async function saveProductEdit(form) {
    const id=form.dataset.editProductForm;
    const old=(await client().from("products").select("image_urls,minimum_order_quantity,price_tiers").eq("id",id).eq("seller_id",user().id).eq("listing_status","pending").single());
    if(old.error)throw old.error;
    const oldUrls=old.data.image_urls||[];
    const v=Object.fromEntries(new FormData(form));
    if(!Number.isFinite(Number(v.price))||Number(v.price)<=0)throw new Error("পণ্যের মূল্য শূন্যের বেশি হতে হবে।");
    const minimumOrderQuantity=v.minimum_order_quantity===undefined?Number(old.data.minimum_order_quantity||1):Number(v.minimum_order_quantity);
    if(!Number.isFinite(minimumOrderQuantity)||minimumOrderQuantity<=0)throw new Error("MOQ শূন্যের বেশি হতে হবে।");
    const tiers=v.price_tiers===undefined?(old.data.price_tiers||[]):parseProductPriceTiers(v.price_tiers,minimumOrderQuantity);
    const images=await saveListingImages(form,oldUrls,"product",5);
    try{
      const {data,error}=await client().from("products").update({
        product_name:v.name.trim(),category:v.category,subcategory:v.subcategory.trim(),
        image_urls:images.urls,description:v.description.trim(),origin:v.origin.trim(),
        specifications_quality:v.specifications.trim()||null,price:Number(v.price),currency:String(v.currency).toUpperCase(),minimum_order_quantity:minimumOrderQuantity,price_tiers:tiers
      }).eq("id",id).eq("seller_id",user().id).eq("listing_status","pending").select("id").maybeSingle();
      if(error)throw error;
      if(!data)throw new Error("পণ্যটি আর Pending অবস্থায় নেই; পৃষ্ঠা Refresh করে দেখুন।");
    }catch(err){if(images.uploadedPaths.length)await removeListingImages(images.uploadedPaths);throw err;}
    await removeListingImages(images.removedPaths);
    say("পণ্যের পরিবর্তন সংরক্ষিত হয়েছে। Admin Review সম্পন্ন হলে প্রকাশিত হবে।",true);
    await loadSellerDashboard();
  }

  async function saveServiceEdit(form) {
    const id=form.dataset.editServiceForm;
    const old=await client().from("service_listings").select("image_urls").eq("id",id).eq("seller_id",user().id).eq("listing_status","pending").single();
    if(old.error)throw old.error;
    const oldUrls=old.data.image_urls||[];
    const v=Object.fromEntries(new FormData(form));
    if(v.price_amount!==""&&(!Number.isFinite(Number(v.price_amount))||Number(v.price_amount)<0))throw new Error("সঠিক মূল্য লিখুন।");
    const images=await saveListingImages(form,oldUrls,"service",3);
    try{
      const {data,error}=await client().from("service_listings").update({
        service_name:v.service_name.trim(),service_category:v.service_category,description:v.description.trim(),
        country:v.country.trim(),city:v.city.trim(),service_area:v.service_area.trim(),
        price_basis:v.price_basis,price_amount:v.price_amount===""?null:Number(v.price_amount),
        currency:String(v.currency||"BDT").toUpperCase(),availability:v.availability.trim()||null,image_urls:images.urls
      }).eq("id",id).eq("seller_id",user().id).eq("listing_status","pending").select("id").maybeSingle();
      if(error)throw error;
      if(!data)throw new Error("সেবাটি আর Pending অবস্থায় নেই; পৃষ্ঠা Refresh করে দেখুন।");
    }catch(err){if(images.uploadedPaths.length)await removeListingImages(images.uploadedPaths);throw err;}
    await removeListingImages(images.removedPaths);
    say("সেবার পরিবর্তন সংরক্ষিত হয়েছে। Admin Review সম্পন্ন হলে প্রকাশিত হবে।",true);
    await loadSellerServices();
  }

  async function submitProductEditRequest(form) {
    const id=form.dataset.requestProductForm;
    const current=await client().from("products").select("image_urls,listing_status,subcategory,minimum_order_quantity,price_tiers").eq("id",id).eq("seller_id",user().id).single();
    if(current.error)throw current.error;
    if(current.data.listing_status!=="approved")throw new Error("এই পণ্য আর Approved অবস্থায় নেই। Refresh করে দেখুন।");
    const v=Object.fromEntries(new FormData(form));
    if(!Number.isFinite(Number(v.price))||Number(v.price)<=0)throw new Error("পণ্যের মূল্য শূন্যের বেশি হতে হবে।");
    const minimumOrderQuantity=Number(v.minimum_order_quantity||1);if(!Number.isFinite(minimumOrderQuantity)||minimumOrderQuantity<=0)throw new Error("MOQ শূন্যের বেশি হতে হবে।");
    const tiers=parseProductPriceTiers(v.price_tiers,minimumOrderQuantity);
    const images=await saveListingImages(form,current.data.image_urls||[],"product",5);
    const changes={
      product_name:v.name.trim(),category:v.category,subcategory:v.subcategory.trim(),
      image_urls:images.urls,description:v.description.trim(),origin:v.origin.trim(),
      specifications_quality:v.specifications.trim()||null,price:Number(v.price),currency:String(v.currency).toUpperCase(),minimum_order_quantity:minimumOrderQuantity,price_tiers:tiers
    };
    try{
      const {data,error}=await client().rpc("submit_listing_edit_request",{
        p_listing_type:"product",p_listing_id:id,p_proposed_changes:changes
      });
      if(error)throw error;
      if(!data?.request_id)throw new Error("Change Request ID পাওয়া যায়নি।");
    }catch(err){if(images.uploadedPaths.length)await removeListingImages(images.uploadedPaths);throw err;}
    say("পণ্যের পরিবর্তন Admin Review-এ পাঠানো হয়েছে। অনুমোদনের আগে Marketplace-এ পুরোনো তথ্যই থাকবে।",true);
    await loadSellerDashboard();await loadSellerEditRequests();
  }

  async function submitServiceEditRequest(form) {
    const id=form.dataset.requestServiceForm;
    const current=await client().from("service_listings").select("image_urls,listing_status").eq("id",id).eq("seller_id",user().id).single();
    if(current.error)throw current.error;
    if(current.data.listing_status!=="approved")throw new Error("এই সেবা আর Approved অবস্থায় নেই। Refresh করে দেখুন।");
    const v=Object.fromEntries(new FormData(form));
    if(v.price_amount!==""&&(!Number.isFinite(Number(v.price_amount))||Number(v.price_amount)<0))throw new Error("সঠিক মূল্য লিখুন।");
    const images=await saveListingImages(form,current.data.image_urls||[],"service",3);
    const changes={
      service_name:v.service_name.trim(),service_category:v.service_category,description:v.description.trim(),
      country:v.country.trim(),city:v.city.trim(),service_area:v.service_area.trim(),
      price_basis:v.price_basis,price_amount:v.price_amount===""?null:Number(v.price_amount),
      currency:String(v.currency||"BDT").toUpperCase(),availability:v.availability.trim()||null,image_urls:images.urls
    };
    try{
      const {data,error}=await client().rpc("submit_listing_edit_request",{
        p_listing_type:"service",p_listing_id:id,p_proposed_changes:changes
      });
      if(error)throw error;
      if(!data?.request_id)throw new Error("Change Request ID পাওয়া যায়নি।");
    }catch(err){if(images.uploadedPaths.length)await removeListingImages(images.uploadedPaths);throw err;}
    say("সেবার পরিবর্তন Admin Review-এ পাঠানো হয়েছে। অনুমোদনের আগে Marketplace-এ পুরোনো তথ্যই থাকবে।",true);
    await loadSellerServices();await loadSellerEditRequests();
  }

  const listingHistoryLabels={
    product_name:"পণ্যের নাম",service_name:"সেবার নাম",category:"পণ্যের বিভাগ",
service_category:"সেবার বিভাগ",description:"বিবরণ",
    origin:"Origin",specifications_quality:"Specifications & Quality",price:"মূল্য",
    price_amount:"সেবার মূল্য",currency:"Currency",image_urls:"ছবি",
    country:"দেশ",city:"শহর",service_area:"সেবার এলাকা",price_basis:"মূল্য নির্ধারণ",
    availability:"Availability"
  };
  function listingHistoryValue(key,value){
    if(value===null||value===undefined||value==="")return "—";
    if(key==="image_urls")return Array.isArray(value)?value.length+"টি ছবি":String(value);
    if(typeof value==="object")return JSON.stringify(value);
    return String(value);
  }
  function listingHistorySnapshot(data){
    const obj=data||{};
    const rows=Object.entries(listingHistoryLabels).filter(([key])=>Object.prototype.hasOwnProperty.call(obj,key))
      .map(([key,label])=>'<tr><th>'+esc(label)+'</th><td>'+esc(listingHistoryValue(key,obj[key]))+'</td></tr>').join("");
    const images=Array.isArray(obj.image_urls)&&obj.image_urls.length
      ?'<div class="nx-upload-preview">'+obj.image_urls.map(url=>'<img src="'+esc(url)+'" alt="Listing history image" loading="lazy">').join("")+'</div>':"";
    return '<div class="table-wrap"><table class="nx-history-table"><tbody>'+rows+'</tbody></table></div>'+images;
  }
  function listingHistoryTimeline(events){
    const names={submitted:"Seller পরিবর্তনের আবেদন জমা দিয়েছেন",approved:"Admin পরিবর্তন অনুমোদন করেছেন",rejected:"Admin পরিবর্তন প্রত্যাখ্যান করেছেন"};
    return '<ol class="nx-history-timeline">'+(events||[]).map(ev=>'<li><strong>'+esc(names[ev.event_type]||ev.event_type)+'</strong><small>'+esc(new Date(ev.created_at).toLocaleString("bn-BD"))+' · '+(ev.actor_role==="seller"?"Seller":ev.actor_role==="admin"?"Admin":"System")+'</small>'+(ev.reason?'<p>'+esc(ev.reason)+'</p>':'')+'</li>').join("")+'</ol>';
  }
  async function loadSellerEditRequests(){
    const host=$("nxSellerEditRequests");if(!host)return;
    if(!signedIn()||!activeSeller()){host.textContent="Seller হিসেবে লগইন করলে Change Request দেখা যাবে।";return;}
    try{
      const {data,error}=await client().from("listing_edit_requests")
        .select("id,listing_type,product_id,service_listing_id,status,review_reason,created_at,reviewed_at,original_data,proposed_changes")
        .eq("seller_id",user().id).order("created_at",{ascending:false}).limit(30);
      if(error)throw error;
      const ids=(data||[]).map(r=>r.id);
      let events=[];
      if(ids.length){
        const result=await client().from("listing_edit_request_events")
          .select("id,request_id,event_type,actor_role,reason,created_at").in("request_id",ids)
          .order("created_at",{ascending:true});
        if(result.error)throw result.error;events=result.data||[];
      }
      const labels={pending:"Admin Review-এ আছে",approved:"পরিবর্তন অনুমোদিত",rejected:"পরিবর্তন প্রত্যাখ্যাত"};
      host.innerHTML=(data||[]).map(r=>{
        const timeline=events.filter(e=>e.request_id===r.id);
        return '<article class="offer nx-history-card"><div class="section-head"><strong>'+(r.listing_type==="product"?"Product":"Service")+'</strong><span class="tag">'+esc(labels[r.status]||r.status)+'</span></div><small>Request: '+esc(r.id)+' · '+esc(new Date(r.created_at).toLocaleString("bn-BD"))+'</small><details><summary>আগের তথ্য ও প্রস্তাবিত তথ্য দেখুন</summary><h5>আগের তথ্য</h5>'+listingHistorySnapshot(r.original_data)+'<h5>প্রস্তাবিত তথ্য</h5>'+listingHistorySnapshot(r.proposed_changes)+'</details><details><summary>সম্পূর্ণ History ('+timeline.length+')</summary>'+listingHistoryTimeline(timeline)+'</details>'+(r.review_reason?'<p class="muted">Admin Note: '+esc(r.review_reason)+'</p>':'')+'</article>';
      }).join("")||'<p class="muted">এখনো কোনো Listing Change Request নেই।</p>';
    }catch(err){host.textContent="Change Request History লোড হয়নি: "+err.message;}
  }

  function listingEditChangeMarkup(request){
    return '<div class="nx-history-compare"><section><h5>বর্তমান প্রকাশিত তথ্য</h5>'+listingHistorySnapshot(request.original_data)+'</section><section><h5>Seller-এর প্রস্তাবিত তথ্য</h5>'+listingHistorySnapshot(request.proposed_changes)+'</section></div>';
  }

  async function loadAdminListingEditRequests(){
    const host=$("nxAdminListingEditQueue");if(!host)return;
    if(!signedIn()||profile()?.role!=="admin"||profile()?.account_status!=="active"){
      host.textContent="শুধু সক্রিয় Admin Change Request পর্যালোচনা করতে পারবেন।";return;
    }
    host.innerHTML='<p class="muted">পরিবর্তনের আবেদন লোড হচ্ছে…</p>';
    try{
      const {data,error}=await client().from("listing_edit_requests")
        .select("id,listing_type,product_id,service_listing_id,seller_id,original_data,proposed_changes,created_at,status,review_reason,reviewed_at")
        .order("created_at",{ascending:false}).limit(100);
      if(error)throw error;
      const ids=(data||[]).map(r=>r.id);let events=[];
      if(ids.length){
        const result=await client().from("listing_edit_request_events")
          .select("id,request_id,event_type,actor_role,reason,created_at").in("request_id",ids)
          .order("created_at",{ascending:true});
        if(result.error)throw result.error;events=result.data||[];
      }
      host.innerHTML=(data||[]).map(r=>'<article class="card nx-history-card"><div class="section-head"><strong>'+(r.listing_type==="product"?"Product Change Request":"Service Change Request")+'</strong><span class="tag">'+esc(({pending:"Pending Review",approved:"Approved",rejected:"Rejected"})[r.status]||r.status)+'</span></div><small>Request ID: '+esc(r.id)+' · Seller: '+esc(r.seller_id)+' · '+esc(new Date(r.created_at).toLocaleString("bn-BD"))+'</small>'+listingEditChangeMarkup(r)+'<details><summary>Request Timeline</summary>'+listingHistoryTimeline(events.filter(e=>e.request_id===r.id))+'</details>'+(r.review_reason?'<p class="muted">Admin Note: '+esc(r.review_reason)+'</p>':'')+(r.status==="pending"?'<div class="form-actions"><button class="primary" type="button" data-listing-edit-review="approve" data-request-id="'+esc(r.id)+'">Approve & Publish Changes</button><button class="danger" type="button" data-listing-edit-review="reject" data-request-id="'+esc(r.id)+'">Reject</button></div>':'')+'</article>').join("")||'<p class="muted">কোনো Listing Change Request নেই।</p>';
    }catch(err){host.textContent="Change Request History লোড হয়নি: "+err.message;}
  }

  async function reviewListingEditRequest(id,action){
    const reason=action==="reject"?prompt("প্রত্যাখ্যানের কারণ লিখুন (কমপক্ষে ৫ অক্ষর):"):"";
    if(action==="reject"&&(!reason||reason.trim().length<5))return say("প্রত্যাখ্যানের কারণ আবশ্যক।");
    const {data,error}=await client().rpc("review_listing_edit_request",{
      p_request_id:id,p_action:action,p_reason:reason||null
    });
    if(error)return say("পরিবর্তন পর্যালোচনা ব্যর্থ: "+error.message);
    if(data?.cleanup_urls?.length)await removeListingImages(listingImagePathsFromUrls(data.cleanup_urls));
    say(action==="approve"?"পরিবর্তন অনুমোদিত ও Marketplace-এ প্রকাশিত হয়েছে।":"পরিবর্তনের আবেদন প্রত্যাখ্যান করা হয়েছে।",true);
    await loadAdminListingEditRequests();await loadProducts();await loadServicesMarketplace();
  }

  document.addEventListener("click",e=>{
    const cancel=e.target.closest("[data-cancel-listing-edit]");
    if(cancel){cancel.closest("form")?.remove();return;}
    const product=e.target.closest("[data-edit-product],[data-request-product-edit]");
    if(product){
      const requestMode=product.hasAttribute("data-request-product-edit");
      const card=product.closest("[data-seller-product]");
      card?.querySelector(".nx-listing-editor")?.remove();
      const item=window.NEXORA_SELLER_PRODUCTS?.find(p=>p.id===(product.dataset.editProduct||product.dataset.requestProductEdit));
      if(!item)return say("পণ্যের তথ্য পাওয়া যায়নি; তালিকা Refresh করুন।");
      card.insertAdjacentHTML("beforeend",renderProductEditor(item,requestMode));
      const safeId=String(item.id).replace(/[^a-zA-Z0-9_-]/g,"");
      bindListingImagePicker("nxEditProductFiles-"+safeId,"nxEditProductPreview-"+safeId,5);
    }
    const service=e.target.closest("[data-edit-service],[data-request-service-edit]");
    if(service){
      const requestMode=service.hasAttribute("data-request-service-edit");
      const card=service.closest("[data-seller-service]");
      card?.querySelector(".nx-listing-editor")?.remove();
      const item=window.NEXORA_SELLER_SERVICES?.find(s=>s.id===(service.dataset.editService||service.dataset.requestServiceEdit));
      if(!item)return say("সেবার তথ্য পাওয়া যায়নি; তালিকা Refresh করুন।");
      card.insertAdjacentHTML("beforeend",renderServiceEditor(item,requestMode));
      const safeId=String(item.id).replace(/[^a-zA-Z0-9_-]/g,"");
      bindListingImagePicker("nxEditServiceFiles-"+safeId,"nxEditServicePreview-"+safeId,3);
    }
    const review=e.target.closest("[data-listing-edit-review]");
    if(review)reviewListingEditRequest(review.dataset.requestId,review.dataset.listingEditReview);
  });
  document.addEventListener("submit",async e=>{
    const productForm=e.target.closest("form[data-edit-product-form]");
    const serviceForm=e.target.closest("form[data-edit-service-form]");
    const requestProductForm=e.target.closest("form[data-request-product-form]");
    const requestServiceForm=e.target.closest("form[data-request-service-form]");
    const form=productForm||serviceForm||requestProductForm||requestServiceForm;if(!form)return;
    e.preventDefault();setBusy(form,true);
    try{
      if(productForm)await saveProductEdit(form);
      else if(serviceForm)await saveServiceEdit(form);
      else if(requestProductForm)await submitProductEditRequest(form);
      else await submitServiceEditRequest(form);
    }catch(err){say("পরিবর্তন সংরক্ষণ হয়নি: "+err.message);}
    finally{setBusy(form,false);}
  });

  async function deleteProduct(id) {
    if (!confirm("এই pending পণ্যটি মুছে ফেলতে চান?")) return;
    const {data:product,error:readError}=await client().from("products").select("image_urls").eq("id",id).single();
    if(readError)return say("পণ্যের তথ্য পাওয়া যায়নি: "+readError.message);
    const { error } = await client().from("products").delete().eq("id", id);
    if (error) return say("পণ্য মুছতে সমস্যা: " + error.message);
    await removeListingImages(listingImagePathsFromUrls(product?.image_urls||[]));
    say("পণ্য মুছে ফেলা হয়েছে।", true);
    await loadSellerDashboard(); await loadProducts();
  }

  $("productForm")?.addEventListener("submit", async e => {
    e.preventDefault();
    const form = e.currentTarget;
    if (!activeSeller()) return say("পণ্য যোগ করতে সক্রিয় Seller হিসেবে লগইন করুন।");
    if (!state.business || state.business.approval_status !== "approved") return say("পণ্য যোগ করার আগে Admin-এর Business Profile অনুমোদন প্রয়োজন।");
    const v = Object.fromEntries(new FormData(form));
    const externalImages = String(v.images || "").split(/\r?\n/).map(x => x.trim()).filter(Boolean);
    if (externalImages.some(x => !/^https:\/\//i.test(x))) return say("প্রতিটি Product Image URL অবশ্যই HTTPS হতে হবে।");
    const imageFiles=Array.from(form.querySelector('[name="image_files"]')?.files||[]);
    if(imageFiles.length>5)return say("সর্বোচ্চ ৫টি Product Image আপলোড করুন।");
    if (!Number.isFinite(Number(v.price)) || Number(v.price) <= 0) return say("পণ্যের মূল্য শূন্যের বেশি হতে হবে।");
    setBusy(form, true);
    let uploadedPaths=[];
    try {
      const uploaded=await uploadListingImages(imageFiles,"products");
      uploadedPaths=uploaded.paths;
      const images=[...uploaded.urls,...externalImages];
      const { error } = await client().from("products").insert({
        business_id: state.business.id, seller_id: user().id,
        product_name: v.name.trim(), category: v.category, subcategory: null,  image_urls: images,
        description: v.description.trim(), origin: v.origin.trim(),
        specifications_quality: v.specifications.trim(),
        price: Number(v.price), currency: String(v.currency).toUpperCase(),
      });
      if (error) throw error;
      form.reset(); form.classList.add("hidden");
      $("nxProductImageFiles")?.dispatchEvent(new Event("change"));
      say("পণ্য ও ছবি জমা হয়েছে। Marketplace-এ প্রকাশের আগে Admin অনুমোদন লাগবে।", true);
      await loadSellerDashboard(); await loadProducts();
    } catch (err) {
      if(uploadedPaths.length)await removeListingImages(uploadedPaths);
      say("পণ্য সংরক্ষণ হয়নি: " + err.message);
    }
    finally { setBusy(form, false); }
  });

  const requiredDateInput = $("requiredDate");
  if (requiredDateInput) {
    const now = new Date();
    requiredDateInput.min = new Date(now.getTime() - now.getTimezoneOffset() * 60000).toISOString().slice(0, 10);
  }

  $("demandForm")?.addEventListener("submit", async e => {
    e.preventDefault();
    const form = e.currentTarget;
    if (!activeBuyer()) return say("চাহিদা প্রকাশ করতে সক্রিয় Buyer হিসেবে লগইন করুন।");
    const v = Object.fromEntries(new FormData(form));
    const now = new Date();
    const todayLocal = new Date(now.getTime() - now.getTimezoneOffset() * 60000).toISOString().slice(0, 10);
    if (!v.requiredDate || v.requiredDate < todayLocal) return say("প্রয়োজনের তারিখ আজকের দিন অথবা ভবিষ্যতের তারিখ হতে হবে।");
    if (v.budget !== "" && (!Number.isFinite(Number(v.budget)) || Number(v.budget) < 0)) return say("সঠিক Budget লিখুন।");
    setBusy(form, true);
    try {
      const { error } = await client().from("buyer_demands").insert({
        buyer_id: user().id, product_name: v.name.trim(), category: v.category, subcategory:v.subcategory.trim(),
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
    if ($("servicesMarketplace") && !$("servicesMarketplace").classList.contains("hidden")) await loadServicesMarketplace();
    await loadAdminServiceQueue();
    if ($("demandBoard") && !$("demandBoard").classList.contains("hidden")) await loadDemands();
    if ($("sellerDashboard") && !$("sellerDashboard").classList.contains("hidden")) await loadSellerDashboard();
    if ($("buyerDashboard") && !$("buyerDashboard").classList.contains("hidden")) await loadBuyerDashboard();
  });

  const today = new Date();
  const localToday = new Date(today.getTime() - today.getTimezoneOffset() * 60000).toISOString().split("T")[0];
  if ($("requiredDate")) $("requiredDate").min = localToday;
  const requestedServicePage = new URLSearchParams(window.location.search).get("service");
  if (requestedServicePage && $("servicesMarketplace")) {
    window.showSection?.("servicesMarketplace", { history: false });
  } else {
    if ($("market")) { loadProducts(); loadDemands(); }
    if ($("servicesMarketplace")) loadServicesMarketplace();
  }
})();