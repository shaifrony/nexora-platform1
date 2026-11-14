/* NEXORA Transport Provider Center — staged frontend */
(() => {
  "use strict";
  const $ = id => document.getElementById(id);
  const auth = () => window.NEXORA_AUTH || {};
  const db = () => auth().client;
  const user = () => auth().user;
  const profile = () => auth().profile;
  const esc = value => String(value ?? "").replace(/[&<>"']/g, c => ({
    "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"
  })[c]);
  const activeAccount = () => Boolean(user()?.id &&
    ["buyer","seller","porter"].includes(profile()?.role) &&
    profile()?.account_status === "active");
  const say = (message, ok=false) => {
    const node=$("nxTransportMessage");
    if(node){node.textContent=message;node.style.color=ok?"#087b5f":"#b42318";}
  };
  let loadedUserId=null;
  let providers=[];

  function addWorkspaceLink() {
    const nav=$("nxAccountWorkspaceNav");
    if(!nav || !activeAccount()) return;
    if($("nxTransportProviderNav")) return;
    const button=document.createElement("button");
    button.id="nxTransportProviderNav";
    button.type="button";
    button.className="secondary";
    button.textContent="Transport Provider Center";
    button.addEventListener("click",()=>window.showSection?.("transportProviderCenter"));
    nav.appendChild(button);
  }

  function renderShell() {
    const section=$("transportProviderCenter");
    if(!section) return;
    if(!activeAccount()){
      section.classList.add("hidden");
      return;
    }
    // Keep the workspace hidden until the user explicitly opens it from the account navigation.
  }

  function providerFormMarkup() {
    return `
      <div class="card">
        <h3>Transport Provider আবেদন</h3>
        <p class="muted">আপনি ব্যক্তি বা প্রতিষ্ঠান হিসেবে নিজের/বৈধভাবে পরিচালনার অধিকার থাকা পরিবহন সেবা নিবন্ধন করতে পারবেন। আবেদন Admin পর্যালোচনা করবে।</p>
        <form id="nxTransportProviderForm">
          <div class="grid">
            <div><label>Provider Type *</label><select name="provider_type" required><option value="individual">ব্যক্তি</option><option value="business">প্রতিষ্ঠান</option></select></div>
            <div><label>Provider / Business Display Name *</label><input name="display_name" minlength="2" maxlength="160" required></div>
            <div><label>Legal Name (ঐচ্ছিক)</label><input name="legal_name" maxlength="160"></div>
            <div><label>যোগাযোগের ফোন *</label><input name="contact_phone" minlength="5" maxlength="40" required></div>
            <div><label>দেশ *</label><input name="country" value="Bangladesh" maxlength="120" required></div>
            <div><label>শহর *</label><input name="city" maxlength="120" required></div>
          </div>
          <label>পরিচালনাস্থলের সম্পূর্ণ ঠিকানা *</label><textarea name="operating_address" minlength="5" maxlength="1000" required></textarea>
          <label>Business Registration Number (ঐচ্ছিক)</label><input name="business_registration_number" maxlength="120">
          <div class="form-actions"><button class="primary" type="submit">Provider আবেদন জমা দিন</button></div>
        </form>
      </div>`;
  }

  function renderProviders() {
    const host=$("nxTransportProviderList");
    if(!host) return;
    if(!providers.length){
      host.innerHTML='<div class="offer">আপনার কোনো Transport Provider আবেদন পাওয়া যায়নি। উপরের ফর্ম পূরণ করে আবেদন শুরু করুন।</div>';
      return;
    }
    const statusLabel={pending:"পর্যালোচনাধীন",approved:"অনুমোদিত",rejected:"প্রত্যাখ্যাত",suspended:"স্থগিত"};
    host.innerHTML=providers.map(p=>`
      <article class="card" data-provider-card="${esc(p.id)}">
        <div class="section-head"><div><span class="tag">TRANSPORT PROVIDER</span><h3>${esc(p.display_name)}</h3></div><span class="tag">${esc(statusLabel[p.application_status]||p.application_status)}</span></div>
        <p class="muted">${esc(p.provider_type)} · ${esc(p.city)}, ${esc(p.country)}</p>
        <p class="muted">Provider ID: ${esc(p.id)}</p>
        <div class="nx-transport-vehicles" id="nxTransportVehicles-${esc(p.id)}">গাড়ির তালিকা লোড হচ্ছে…</div>
        <form class="nxTransportVehicleForm" data-provider-id="${esc(p.id)}">
          <hr><h4>এই Provider-এর গাড়ি যোগ করুন</h4>
          <div class="grid">
            <div><label>গাড়ির ধরন *</label><input name="vehicle_type" maxlength="80" required placeholder="যেমন: Truck, Covered Van, Pickup"></div>
            <div><label>Make / Model (ঐচ্ছিক)</label><input name="make_model" maxlength="120"></div>
            <div><label>Registration Number *</label><input name="registration_number" maxlength="40" required></div>
            <div><label>Registration Country *</label><input name="registration_country" maxlength="120" value="Bangladesh" required></div>
            <div><label>Capacity *</label><input name="capacity_value" type="number" min="0.01" step="0.01" required placeholder="যেমন: 5"></div>
            <div><label>Capacity Unit *</label><select name="capacity_unit" required><option value="ton">টন</option><option value="kg">কেজি</option><option value="cubic_meter">ঘনমিটার</option><option value="pallet">প্যালেট</option><option value="vehicle">গাড়ি</option></select></div>
          </div>
          <label class="nx-transport-check"><input name="is_available" type="checkbox" checked style="width:auto"> বর্তমানে গাড়িটি কাজের জন্য উপলভ্য</label>
          <p class="muted">গাড়ির ছবি ও আইনগত কাগজপত্র আপলোডের ব্যবস্থা পরবর্তী ধাপে যুক্ত হবে। ব্যক্তিগত Registration Number ও নথি Public Marketplace-এ দেখানো হবে না।</p>
          <div class="form-actions"><button class="primary" type="submit" ${["suspended","rejected"].includes(p.application_status)?"disabled":""}>গাড়ি নিবন্ধন করুন</button></div>
        </form>
      </article>`).join("");
    providers.forEach(p=>loadVehicles(p.id));
  }

  async function loadVehicles(providerId) {
    const host=$("nxTransportVehicles-"+providerId);
    if(!host || !db()) return;
    const {data,error}=await db().from("transport_vehicles")
      .select("id,vehicle_type,make_model,registration_number,capacity_value,capacity_unit,is_available,approval_status,created_at")
      .eq("provider_id",providerId).order("created_at",{ascending:false});
    if(error){host.textContent="গাড়ির তালিকা পাওয়া যায়নি: "+error.message;return;}
    const labels={pending:"পর্যালোচনাধীন",approved:"অনুমোদিত",rejected:"প্রত্যাখ্যাত",suspended:"স্থগিত"};
    host.innerHTML=data?.length?'<h4>নিবন্ধিত গাড়ি ('+data.length+')</h4>'+data.map(v=>`
      <div class="offer"><strong>${esc(v.vehicle_type)} ${v.make_model?"· "+esc(v.make_model):""}</strong>
      <p class="muted">গাড়ি ID: ${esc(v.id)}</p>
      <p class="muted">Registration: ${esc(v.registration_number)} · Capacity: ${esc(v.capacity_value)} ${esc(v.capacity_unit)}</p>
      <p class="muted">অবস্থা: ${esc(labels[v.approval_status]||v.approval_status)} · ${v.is_available?"কাজের জন্য উপলভ্য":"এখন অনুপলভ্য"}</p></div>`).join(""):'<p class="muted">এখনো কোনো গাড়ি নিবন্ধন করা হয়নি।</p>';
  }

  async function loadProviders() {
    const host=$("nxTransportProviderList");
    if(!host) return;
    if(!activeAccount()){host.textContent="সক্রিয় Buyer, Seller অথবা অনুমোদিত Porter অ্যাকাউন্টে লগইন করুন।";return;}
    if(!db()){host.textContent="Database connection পাওয়া যায়নি।";return;}
    host.textContent="আপনার Provider আবেদন লোড হচ্ছে…";
    const uid=user().id;
    const {data,error}=await db().from("transport_providers")
      .select("id,provider_type,display_name,country,city,application_status,created_at")
      .eq("owner_user_id",uid).order("created_at",{ascending:false});
    if(error){
      host.textContent=/transport_providers|schema cache|relation/i.test(error.message)
        ?"Transport Provider সুবিধার Database migration এখনো Development/Hosted Database-এ প্রয়োগ করা হয়নি। তাই এই ফর্ম আপাতত প্রস্তুত, কিন্তু আবেদন সংরক্ষণ চালু হয়নি।"
        :"Provider আবেদন লোড হয়নি: "+error.message;
      return;
    }
    providers=data||[];
    loadedUserId=uid;
    renderProviders();
  }

  if($("nxTransportProviderFormHost")) $("nxTransportProviderFormHost").innerHTML=providerFormMarkup();

  $("nxTransportProviderForm")?.addEventListener("submit",async event=>{
    event.preventDefault();
    if(!activeAccount()) return say("সক্রিয় Buyer, Seller অথবা অনুমোদিত Porter অ্যাকাউন্ট প্রয়োজন।");
    const form=event.currentTarget, f=new FormData(form);
    const payload={
      owner_user_id:user().id,
      provider_type:String(f.get("provider_type")||"individual"),
      display_name:String(f.get("display_name")||"").trim(),
      legal_name:String(f.get("legal_name")||"").trim()||null,
      contact_phone:String(f.get("contact_phone")||"").trim(),
      country:String(f.get("country")||"").trim(),
      city:String(f.get("city")||"").trim(),
      operating_address:String(f.get("operating_address")||"").trim(),
      business_registration_number:String(f.get("business_registration_number")||"").trim()||null
    };
    const button=form.querySelector('button[type="submit"]');button.disabled=true;say("");
    try{
      const {error}=await db().from("transport_providers").insert(payload);
      if(error) throw error;
      form.reset();
      say("Provider আবেদন জমা হয়েছে। Admin পর্যালোচনা না করা পর্যন্ত Delivery assignment পাওয়া যাবে না।",true);
      await loadProviders();
    }catch(err){say("আবেদন সংরক্ষণ হয়নি: "+(err.message||String(err)));}
    finally{button.disabled=false;}
  });

  $("transportProviderCenter")?.addEventListener("submit",async event=>{
    const form=event.target.closest(".nxTransportVehicleForm");
    if(!form) return;
    event.preventDefault();
    if(!activeAccount()) return say("সক্রিয় Buyer বা Seller অ্যাকাউন্ট প্রয়োজন।");
    const f=new FormData(form), providerId=form.dataset.providerId;
    const payload={
      provider_id:providerId,
      vehicle_type:String(f.get("vehicle_type")||"").trim(),
      make_model:String(f.get("make_model")||"").trim()||null,
      registration_number:String(f.get("registration_number")||"").trim(),
      registration_country:String(f.get("registration_country")||"").trim(),
      capacity_value:Number(f.get("capacity_value")),
      capacity_unit:String(f.get("capacity_unit")||"").trim(),
      is_available:f.get("is_available")==="on"
    };
    const button=form.querySelector('button[type="submit"]');button.disabled=true;say("");
    try{
      const {error}=await db().from("transport_vehicles").insert(payload);
      if(error) throw error;
      form.reset();
      const availability=form.querySelector('[name="is_available"]');if(availability) availability.checked=true;
      const country=form.querySelector('[name="registration_country"]');if(country) country.value="Bangladesh";
      say("গাড়িটি নিবন্ধিত হয়েছে এবং আলাদাভাবে Admin review-এর অপেক্ষায় আছে।",true);
      await loadVehicles(providerId);
    }catch(err){say("গাড়ি নিবন্ধন হয়নি: "+(err.message||String(err)));}
    finally{button.disabled=false;}
  });

  window.addEventListener("nexora:auth-change",()=>{
    addWorkspaceLink();renderShell();
    if(activeAccount() && loadedUserId!==user().id) loadProviders();
    else if(!activeAccount()){providers=[];loadedUserId=null;}
  });
  document.addEventListener("click",event=>{
    if(event.target.closest("#nxTransportProviderNav")) {
      renderShell();loadProviders();
    }
  });
  addWorkspaceLink();
  renderShell();
  if(activeAccount()) loadProviders();
})();
