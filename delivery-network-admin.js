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
            <div><label>সেবা *</label><label><input type="checkbox" name="service_modes" value="retail" checked style="width:auto"> Retail</label><label><input type="checkbox" name="service_modes" value="wholesale" style="width:auto"> Wholesale</label></div>
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
        <hr>
        <h5>নতুন Delivery Request তৈরি</h5>
        <form id="nxNetworkJobForm" class="card">
          <div class="grid">
            <label>Delivery Type *<select name="delivery_mode"><option value="retail">Retail</option><option value="wholesale">Wholesale</option></select></label>
            <label>Package Description *<input name="package_description" minlength="3" maxlength="1000" required></label>
            <label>Package Count *<input name="package_count" type="number" min="1" max="10000" value="1" required></label>
            <label>Order / Shipment Reference<input name="external_reference" maxlength="120"></label>
          </div>
          <h5>Pickup</h5><div class="grid">
            <label>Contact Name<input name="pickup_contact_name" maxlength="150"></label>
            <label>Phone<input name="pickup_contact_phone" maxlength="40"></label>
            <label>Address *<input name="pickup_address" minlength="5" maxlength="1000" required></label>
            <label>City *<input name="pickup_city" maxlength="120" required></label>
            <label>Country *<input name="pickup_country" value="Bangladesh" maxlength="120" required></label>
          </div>
          <h5>Buyer Delivery</h5><div class="grid">
            <label>Receiver Name<input name="recipient_contact_name" maxlength="150"></label>
            <label>Receiver Phone<input name="recipient_contact_phone" maxlength="40"></label>
            <label>Address *<input name="delivery_address" minlength="5" maxlength="1000" required></label>
            <label>City *<input name="delivery_city" maxlength="120" required></label>
            <label>Country *<input name="delivery_country" value="Bangladesh" maxlength="120" required></label>
          </div>
          <button class="primary" type="submit">Unassigned Delivery Request তৈরি করুন</button>
        </form>
        <h5>Delivery Request & Assignment Queue</h5>
        <div id="nxNetworkJobsList" class="muted">Delivery Job লোড হচ্ছে…</div>
      </section>`);
    $("nxDeliveryNetworkRefresh")?.addEventListener("click", load);
    $("nxDeliveryPartnerForm")?.addEventListener("submit", savePartner);
    $("nxDeliveryStaffForm")?.addEventListener("submit", saveStaff);
    $("nxNetworkJobForm")?.addEventListener("submit", createJob);
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
    await loadJobs();
    pHost.querySelectorAll("[data-partner-status]").forEach(btn=>btn.addEventListener("click",()=>changePartnerStatus(btn)));
  }
  async function savePartner(event) {
    event.preventDefault(); if(!isAdmin()) return message("Admin account প্রয়োজন।");
    const form=event.currentTarget, f=new FormData(form), modes=[...form.querySelectorAll('[name="service_modes"]:checked')].map(o=>o.value);
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
    const status=btn.dataset.partnerStatus, reason=status==="suspended"?prompt("Suspend করার কারণ লিখুন (কমপক্ষে ৫ অক্ষর):"):null;
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

  async function createJob(event) {
    event.preventDefault(); if(!isAdmin()) return message("Admin account প্রয়োজন।");
    const form=event.currentTarget,f=new FormData(form);
    const p={
      p_external_reference:String(f.get("external_reference")||"").trim()||null,
      p_package_description:String(f.get("package_description")||"").trim(),p_package_count:Number(f.get("package_count")),
      p_pickup_contact_name:String(f.get("pickup_contact_name")||"").trim()||null,
      p_pickup_contact_phone:String(f.get("pickup_contact_phone")||"").trim()||null,
      p_pickup_address:String(f.get("pickup_address")||"").trim(),p_pickup_city:String(f.get("pickup_city")||"").trim(),
      p_pickup_country:String(f.get("pickup_country")||"").trim(),
      p_recipient_contact_name:String(f.get("recipient_contact_name")||"").trim()||null,
      p_recipient_contact_phone:String(f.get("recipient_contact_phone")||"").trim()||null,
      p_delivery_address:String(f.get("delivery_address")||"").trim(),p_delivery_city:String(f.get("delivery_city")||"").trim(),
      p_delivery_country:String(f.get("delivery_country")||"").trim(),
      p_requested_pickup_at:null,p_delivery_deadline:null,p_special_instructions:null,
      p_delivery_mode:f.get("delivery_mode"),p_commerce_order_id:null
    };
    const btn=form.querySelector("button[type=submit]");btn.disabled=true;
    try{const {error}=await db().rpc("create_delivery_network_job",p);if(error)throw error;form.reset();message("Unassigned Delivery Request তৈরি হয়েছে। এখন Provider assign করুন।",true);await loadJobs();}
    catch(err){message("Delivery Request তৈরি হয়নি: "+err.message);}
    finally{btn.disabled=false;}
  }
  async function loadJobs() {
    const host=$("nxNetworkJobsList");if(!host||!db()||!isAdmin())return;
    const [jobs,providers,vehicles,partners,staff]=await Promise.all([
      db().from("delivery_jobs").select("id,job_reference,external_reference,package_description,package_count,pickup_address,pickup_city,pickup_country,delivery_address,delivery_city,delivery_country,job_status,delivery_mode,assignment_source,created_at").order("created_at",{ascending:false}).limit(100),
      db().from("transport_providers").select("id,display_name,city,application_status").eq("application_status","approved").limit(200),
      db().from("transport_vehicles").select("id,provider_id,vehicle_type,registration_number,approval_status,is_available").eq("approval_status","approved").eq("is_available",true).limit(300),
      db().from("delivery_network_partners").select("id,partner_code,display_name,partner_kind,partner_status").eq("partner_status","approved").limit(200),
      db().from("delivery_network_staff").select("id,partner_id,full_name,staff_status").eq("staff_status","active").limit(300)
    ]);
    const err=[jobs,providers,vehicles,partners,staff].find(r=>r.error);
    if(err){host.textContent="Assignment Queue লোড হয়নি: "+err.error.message;return;}
    const approvedProviders=providers.data||[],availableVehicles=vehicles.data||[],approvedPartners=partners.data||[],activeStaff=staff.data||[];
    const options=(rows,label)=>rows.map(x=>'<option value="'+esc(x.id)+'">'+esc(label(x))+'</option>').join("");
    host.innerHTML=(jobs.data||[]).length?(jobs.data||[]).map(j=>{
      const pOpts=options(approvedProviders,p=>p.display_name+" · "+p.city);
      const cOpts=options(approvedPartners.filter(p=>p.partner_kind==="courier_company"),p=>p.display_name);
      const tOpts=options(approvedPartners.filter(p=>p.partner_kind==="nexora_team"),p=>p.display_name);
      const sOpts=options(activeStaff,s=>s.full_name);
      const vOpts=options(availableVehicles,v=>v.vehicle_type+" · "+v.registration_number);
      return '<article class="offer" data-network-job="'+esc(j.id)+'"><div class="section-head"><strong>'+esc(j.job_reference)+'</strong><span class="tag">'+esc(j.job_status)+'</span></div><p>'+esc(j.package_description)+' · '+esc(j.package_count)+' package(s) · '+esc(j.delivery_mode)+'</p><p class="muted">Pickup: '+esc(j.pickup_city)+', '+esc(j.pickup_country)+' → Delivery: '+esc(j.delivery_city)+', '+esc(j.delivery_country)+'</p><p class="muted">'+esc(j.pickup_address)+' → '+esc(j.delivery_address)+'</p>'+
      (["requested","assigned"].includes(j.job_status)?'<div class="grid"><label>Assignment Source<select data-field="source"><option value="independent_provider">Independent Provider</option><option value="nexora_team">NEXORA Own Team</option><option value="courier_partner">Courier Partner</option></select></label><label>Independent Provider<select data-field="provider"><option value="">Select Provider</option>'+pOpts+'</select></label><label>Vehicle (optional)<select data-field="vehicle"><option value="">No vehicle / not required</option>'+vOpts+'</select></label><label>NEXORA Team<select data-field="team"><option value="">Select Team</option>'+tOpts+'</select></label><label>Team Staff (optional)<select data-field="staff"><option value="">Select Staff</option>'+sOpts+'</select></label><label>Courier Partner<select data-field="courier"><option value="">Select Courier</option>'+cOpts+'</select></label></div><label>Assignment reason<input data-field="reason" maxlength="1000" placeholder="নতুন assignment / পরিবর্তনের কারণ"></label><button type="button" class="primary" data-assign-job="'+esc(j.id)+'">Assign / Reassign</button>':'<p class="muted">বর্তমান Assignment: '+esc(j.assignment_source||"—")+'</p>')+'</article>';
    }).join(""):'<p class="muted">কোনো Delivery Request নেই।</p>';
    host.querySelectorAll("[data-assign-job]").forEach(btn=>btn.addEventListener("click",()=>assignJob(btn,approvedProviders,availableVehicles,approvedPartners,activeStaff)));
  }
  async function assignJob(btn,providers,vehicles,partners,staff) {
    const card=btn.closest("[data-network-job]"),get=n=>card.querySelector('[data-field="'+n+'"]')?.value||null;
    const source=get("source"),p={p_job_id:btn.dataset.assignJob,p_assignment_source:source,
      p_provider_id:source==="independent_provider"?get("provider"):null,
      p_partner_id:source==="independent_provider"?null:(source==="nexora_team"?get("team"):get("courier")),
      p_staff_id:source==="nexora_team"?get("staff"):null,
      p_vehicle_id:source==="independent_provider"?get("vehicle"):null,
      p_reason:get("reason")};
    if(source==="independent_provider"&&!p.p_provider_id)return message("Independent Provider নির্বাচন করুন।");
    if(source==="nexora_team"&&!p.p_partner_id)return message("NEXORA Own Team নির্বাচন করুন।");
    if(source==="courier_partner"&&!p.p_partner_id)return message("Courier Partner নির্বাচন করুন।");
    if(p.p_staff_id==="")p.p_staff_id=null;if(p.p_vehicle_id==="")p.p_vehicle_id=null;
    btn.disabled=true;
    try{const {error}=await db().rpc("assign_delivery_job_network",p);if(error)throw error;message("Delivery Provider assign হয়েছে।",true);await loadJobs();}
    catch(err){message("Assignment হয়নি: "+err.message);btn.disabled=false;}
  }

  window.addEventListener("nexora:auth-change",()=>{if(!isAdmin())return;mount();load();});
  const observer=new MutationObserver(()=>{if(isAdmin()){mount();load();}});
  const admin=$("nxAdmin");if(admin)observer.observe(admin,{attributes:true,attributeFilter:["class"]});
  if(isAdmin()){mount();load();}
})();