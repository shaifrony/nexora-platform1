/* NEXORA Delivery Network — Admin foundation (staged) */
(() => {
  "use strict";
  const $ = id => document.getElementById(id);
  const auth = () => window.NEXORA_AUTH || {};
  const db = () => auth().client;
  const profile = () => auth().profile;
  const esc = value => String(value ?? "").replace(/[&<>"']/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
  const isAdmin = () => profile()?.role === "admin" && profile()?.account_status === "active";
  let ready = false;

  function mount() {
    const anchor = $("nxAdminTransportQueue");
    if (!anchor || $("nxDeliveryNetworkAdmin")) return;
    anchor.insertAdjacentHTML("afterend", `
      <section id="nxDeliveryNetworkAdmin" class="card">
        <div class="section-head"><div><span class="tag">NEXORA DELIVERY NETWORK</span><h4>Delivery Team & Courier Partner Management</h4></div><button type="button" class="light" id="nxDeliveryNetworkRefresh">Refresh</button></div>
        <p class="muted">নিজস্ব Team ও Courier Partner এখানে নিবন্ধন ও পরিচালনা করুন। Independent Delivery Person আগের Transport Provider Center থেকে আবেদন করবেন। সব পরিবর্তন Admin MFA ও logistics.assign দিয়ে সুরক্ষিত।</p>
        <p id="nxDeliveryNetworkMessage" class="muted" role="status" aria-live="polite"></p>
        <form id="nxDeliveryPartnerForm" class="card">
          <h5>নিজস্ব Team / Courier Partner যোগ করুন</h5>
          <div class="grid">
            <label>ধরন *<select name="partner_kind" required><option value="nexora_team">NEXORA Own Team</option><option value="courier_company">Courier / Logistics Company</option></select></label>
            <label>প্রতিষ্ঠান / Team Name *<input name="display_name" minlength="2" maxlength="160" required></label>
            <label>Legal Name<input name="legal_name" maxlength="160"></label>
            <label>যোগাযোগের ব্যক্তির নাম<input name="contact_name" maxlength="160"></label>
            <label>ফোন *<input name="contact_phone" minlength="5" maxlength="40" required></label>
            <label>Email<input name="contact_email" type="email" maxlength="254"></label>
            <label>সেবা *<select name="service_modes" multiple required><option value="retail" selected>Retail</option><option value="wholesale">Wholesale</option></select></label>
            <label>দেশ *<input name="service_countries" value="Bangladesh" required></label>
            <label>সেবা-শহর (কমা দিয়ে)<input name="service_cities" placeholder="Dhaka, Gazipur, Narayanganj"></label>
            <label>Tracking Mode *<select name="tracking_mode"><option value="manual">Manual / Tracking Number</option><option value="api">API (পরবর্তী Integration)</option></select></label>
            <label>Tracking URL (ঐচ্ছিক)<input name="external_tracking_url" type="url" placeholder="https://"></label>
          </div>
          <label>Admin Notes<textarea name="admin_notes" maxlength="1500"></textarea></label>
          <button class="primary" type="submit">Partner সংরক্ষণ করুন</button>
        </form>
        <div id="nxDeliveryPartnersList" class="muted">অনুমতি যাচাইয়ের পর Partner তালিকা দেখা যাবে…</div>
        <hr>
        <form id="nxDeliveryStaffForm" class="card">
          <h5>NEXORA Own Team-এর কর্মী যোগ করুন</h5>
          <div class="grid">
            <label>Own Team *<select name="partner_id" id="nxDeliveryStaffPartner" required><option value="">অনুমোদিত Own Team নির্বাচন করুন</option></select></label>
            <label>কর্মীর নাম *<input name="full_name" minlength="2" maxlength="160" required></label>
            <label>ফোন *<input name="contact_phone" minlength="5" maxlength="40" required></label>
            <label>Email<input name="contact_email" type="email" maxlength="254"></label>
            <label>নিয়োগের ধরন *<select name="employment_type"><option value="employee">নিজস্ব কর্মী</option><option value="contract">চুক্তিভিত্তিক</option></select></label>
            <label>দায়িত্বের শহর<input name="service_cities" placeholder="Dhaka, Gazipur"></label>
            <label>যানবাহন<input name="vehicle_type" maxlength="80" placeholder="Motorcycle / Van"></label>
            <label>অবস্থা<select name="staff_status"><option value="active">Active</option><option value="inactive">Inactive</option></select></label>
          </div>
          <label>Admin Notes<textarea name="admin_notes" maxlength="1500"></textarea></label>
          <button class="primary" type="submit">কর্মী সংরক্ষণ করুন</button>
        </form>
        <div id="nxDeliveryStaffList" class="muted">কর্মীর তালিকা লোড হচ্ছে…</div>
      </section>`);
    $("nxDeliveryNetworkRefresh")?.addEventListener("click", load);
    $("nxDeliveryPartnerForm")?.addEventListener("submit", savePartner);
    $("nxDeliveryStaffForm")?.addEventListener("submit", saveStaff);
    ready = true;
  }

  function message(text, ok=false) {
    const el=$("nxDeliveryNetworkMessage");
    if(el){el.textContent=text;el.style.color=ok?"#087b5f":"#b42318";}
  }
  const list = value => String(value||"").split(",").map(x=>x.trim()).filter(Boolean);
  async function load() {
    if(!ready || !isAdmin() || !db()) return;
    const pHost=$("nxDeliveryPartnersList"), sHost=$("nxDeliveryStaffList"), select=$("nxDeliveryStaffPartner");
    const [pRes,sRes]=await Promise.all([
      db().from("delivery_network_partners").select("id,partner_code,partner_kind,display_name,contact_phone,service_modes,service_countries,service_cities,tracking_mode,partner_status,created_at").order("created_at",{ascending:false}).limit(100),
      db().from("delivery_network_staff").select("id,staff_code,partner_id,full_name,contact_phone,employment_type,service_cities,vehicle_type,staff_status,created_at").order("created_at",{ascending:false}).limit(200)
    ]);
    if(pRes.error || sRes.error){
      const err=pRes.error||sRes.error;
      pHost.textContent="Delivery Network তালিকা পাওয়া যায়নি: "+err.message+" (logistics.view permission ও migration যাচাই করুন)";
      sHost.textContent="কর্মীর তালিকা পাওয়া যায়নি।";
      return;
    }
    const partners=pRes.data||[], staff=sRes.data||[];
    const own=partners.filter(p=>p.partner_kind==="nexora_team"&&p.partner_status==="approved");
    select.innerHTML='<option value="">অনুমোদিত Own Team নির্বাচন করুন</option>'+own.map(p=>'<option value="'+esc(p.id)+'">'+esc(p.display_name)+'</option>').join("");
    pHost.innerHTML=partners.length?partners.map(p=>`
      <article class="offer"><div class="section-head"><strong>${esc(p.display_name)}</strong><span class="tag">${esc(p.partner_status)}</span></div>
      <p class="muted">${esc(p.partner_code)} · ${p.partner_kind==="nexora_team"?"NEXORA Own Team":"Courier / Logistics Partner"}</p>
      <p class="muted">${esc((p.service_modes||[]).join(", "))} · ${esc((p.service_countries||[]).join(", "))} · ${esc(p.tracking_mode)}</p>
      <p class="muted">${esc(p.contact_phone)} · ${esc((p.service_cities||[]).join(", "))}</p>
      <div class="form-actions">${p.partner_status!=="approved"?'<button type="button" class="primary" data-partner-status="approved" data-id="'+esc(p.id)+'">Approve</button>':''}
      ${p.partner_status!=="suspended"?'<button type="button" class="danger" data-partner-status="suspended" data-id="'+esc(p.id)+'">Suspend</button>':''}</div></article>`).join(""):'<p class="muted">এখনো কোনো Team বা Partner যোগ করা হয়নি।</p>';
    sHost.innerHTML=staff.length?staff.map(s=>`<article class="offer"><strong>${esc(s.full_name)}</strong><p class="muted">${esc(s.staff_code)} · ${esc(s.contact_phone)} · ${esc(s.employment_type)} · ${esc(s.staff_status)}</p><p class="muted">${esc((s.service_cities||[]).join(", "))} · ${esc(s.vehicle_type||"")}</p></article>`).join(""):'<p class="muted">এখনো কোনো নিজস্ব কর্মী নিবন্ধিত নেই।</p>';
    pHost.querySelectorAll("[data-partner-status]").forEach(btn=>btn.addEventListener("click",()=>changePartnerStatus(btn)));
  }
  async function savePartner(event) {
    event.preventDefault(); if(!isAdmin()) return message("Admin account প্রয়োজন।");
    const form=event.currentTarget, f=new FormData(form), modes=[...form.elements.service_modes.selectedOptions].map(o=>o.value);
    const payload={
      p_partner_id:null,p_partner_kind:f.get("partner_kind"),p_display_name:String(f.get("display_name")).trim(),
      p_legal_name:String(f.get("legal_name")||"").trim()||null,p_contact_name:String(f.get("contact_name")||"").trim()||null,
      p_contact_phone:String(f.get("contact_phone")||"").trim(),p_contact_email:String(f.get("contact_email")||"").trim()||null,
      p_service_modes:modes,p_service_countries:list(f.get("service_countries")),p_service_cities:list(f.get("service_cities")),
      p_tracking_mode:f.get("tracking_mode"),p_external_tracking_url:String(f.get("external_tracking_url")||"").trim()||null,
      p_admin_notes:String(f.get("admin_notes")||"").trim()||null
    };
    const btn=form.querySelector("button[type=submit]");btn.disabled=true;
    try{const {error}=await db().rpc("upsert_delivery_network_partner",payload);if(error)throw error;form.reset();message("Partner সংরক্ষিত হয়েছে। Courier Partner এখন Pending review-তে থাকবে; NEXORA Own Team অনুমোদিত হয়েছে।",true);await load();}
    catch(err){message("Partner সংরক্ষণ হয়নি: "+err.message);}
    finally{btn.disabled=false;}
  }
  async function changePartnerStatus(btn) {
    const status=btn.dataset.partnerStatus, reason=status==="suspended"?prompt("Suspend করার কারণ লিখুন (কমপক্ষে ৫ অক্ষর):"):"Admin approval reason (ঐচ্ছিক):";
    if(status==="suspended"&&!reason)return;
    btn.disabled=true;
    try{const {error}=await db().rpc("set_delivery_network_partner_status",{p_partner_id:btn.dataset.id,p_status:status,p_reason:reason||null});if(error)throw error;message("Partner status আপডেট হয়েছে।",true);await load();}
    catch(err){message("Status পরিবর্তন হয়নি: "+err.message);btn.disabled=false;}
  }
  async function saveStaff(event) {
    event.preventDefault();if(!isAdmin())return message("Admin account প্রয়োজন।");
    const form=event.currentTarget,f=new FormData(form);
    const payload={p_staff_id:null,p_partner_id:f.get("partner_id"),p_full_name:String(f.get("full_name")).trim(),
      p_contact_phone:String(f.get("contact_phone")).trim(),p_contact_email:String(f.get("contact_email")||"").trim()||null,
      p_employment_type:f.get("employment_type"),p_service_cities:list(f.get("service_cities")),
      p_vehicle_type:String(f.get("vehicle_type")||"").trim()||null,p_staff_status:f.get("staff_status"),
      p_admin_notes:String(f.get("admin_notes")||"").trim()||null};
    const btn=form.querySelector("button[type=submit]");btn.disabled=true;
    try{const {error}=await db().rpc("upsert_delivery_network_staff",payload);if(error)throw error;form.reset();message("নিজস্ব Delivery কর্মীর তথ্য সংরক্ষিত হয়েছে।",true);await load();}
    catch(err){message("কর্মীর তথ্য সংরক্ষণ হয়নি: "+err.message);}
    finally{btn.disabled=false;}
  }
  window.addEventListener("nexora:auth-change",()=>{if(!isAdmin())return;mount();load();});
  const observer=new MutationObserver(()=>{if(isAdmin()){mount();load();}});
  const admin=$("nxAdmin");if(admin)observer.observe(admin,{attributes:true,attributeFilter:["class"]});
  if(isAdmin()){mount();load();}
})();