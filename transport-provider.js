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
    button.textContent="Transport & Delivery Work Center";
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
    host.insertAdjacentHTML("beforeend",'<section class="card" id="nxProviderReceiptJobs"><h3>Buyer Receipt Verification</h3><p class="muted">শুধু আপনার অনুমোদিত Provider-এ বরাদ্দ এবং Buyer-এর OTP অপেক্ষমাণ চালান এখানে দেখানো হবে।</p><div data-provider-receipt-list>চালান লোড হচ্ছে…</div></section>');
    loadAssignedReceiptJobs();
  }

  async function loadAssignedReceiptJobs(){
    const host=$("nxProviderReceiptJobs")?.querySelector("[data-provider-receipt-list]");
    if(!host||!db())return;
    const {data,error}=await db().rpc("get_my_assigned_receipt_jobs");
    if(error){host.textContent="Receipt verification queue লোড হয়নি: "+error.message;return;}
    const jobs=data||[];
    host.innerHTML=jobs.length?jobs.map(j=>'<form class="offer" data-provider-receipt-form="'+esc(j.job_id)+'"><b>'+esc(j.job_reference)+'</b><p class="muted">Status: '+esc(j.job_status)+' · Buyer-এর কাছ থেকে পাওয়া ৩২ অক্ষরের OTP লিখুন।</p><label>Buyer Receipt OTP<input name="code" minlength="32" maxlength="32" pattern="[0-9A-Fa-f]{32}" autocomplete="one-time-code" required></label><label>Delivery note (ঐচ্ছিক)<input name="note" maxlength="1500"></label><button class="primary" type="submit">OTP যাচাই করে Delivered করুন</button><p class="muted" role="status" aria-live="polite"></p></form>').join(""):'<p class="muted">এখনো আপনার নামে OTP-যোগ্য কোনো চালান বরাদ্দ নেই।</p>';
    host.querySelectorAll("[data-provider-receipt-form]").forEach(form=>form.addEventListener("submit",async event=>{
      event.preventDefault();const button=form.querySelector("button[type=submit]"),status=form.querySelector('[role="status"]'),data=new FormData(form);
      button.disabled=true;status.textContent="OTP যাচাই হচ্ছে…";
      try{
        const {data:result,error:rpcError}=await db().rpc("verify_delivery_receipt_code",{p_job_id:form.dataset.providerReceiptForm,p_code:String(data.get("code")||"").trim(),p_location_description:null,p_note:String(data.get("note")||"").trim()||null});
        if(rpcError)throw rpcError;
        if(result?.verified){status.textContent="OTP সঠিক। Delivery Delivered হিসেবে নিশ্চিত হয়েছে।";form.querySelectorAll("input,button").forEach(x=>x.disabled=true);await loadAssignedReceiptJobs();}
        else status.textContent="OTP যাচাই হয়নি। "+(result?.reason||("অবশিষ্ট চেষ্টা: "+(result?.attempts_remaining??"—")));
      }catch(err){status.textContent="যাচাই হয়নি: "+err.message;}
      finally{button.disabled=false;}
    }));
  }

  async function loadAssignedStaffReceiptJobs(){
    const host=$("nxDeliveryStaffReceiptJobs")?.querySelector("[data-staff-receipt-list]");
    if(!host||!db()||!activeAccount())return;
    const {data,error}=await db().rpc("get_my_assigned_delivery_jobs");
    if(error){host.textContent="Delivery staff queue লোড হয়নি: "+error.message;return;}
    const jobs=data||[];
    const statusLabels={assigned:"বরাদ্দ হয়েছে",accepted:"কাজ গ্রহণ",picked_up:"পণ্য সংগ্রহ",in_transit:"পথে আছে",out_for_delivery:"পৌঁছে দেওয়ার পথে",partially_delivered:"আংশিক ডেলিভারি",delivery_failed:"ডেলিভারি ব্যর্থ",delivered:"সম্পন্ন"};
    const transitions={
      assigned:["accepted","delivery_failed"],accepted:["picked_up","delivery_failed"],
      picked_up:["in_transit","delivery_failed"],in_transit:["out_for_delivery","delivery_failed"],
      out_for_delivery:["delivery_failed"],partially_delivered:["in_transit","out_for_delivery","delivery_failed"]
    };
    if(!jobs.length){
      host.innerHTML='<p class="muted">আপনার পরিচয়যুক্ত কর্মী অ্যাকাউন্টে বর্তমানে কোনো সক্রিয় Delivery Job বরাদ্দ নেই।</p>';
      return;
    }
    host.innerHTML=jobs.map(j=>{
      const options=(transitions[j.job_status]||[]).map(v=>'<option value="'+v+'">'+esc(statusLabels[v]||v)+'</option>').join("");
      const needsOtp=["out_for_delivery","partially_delivered"].includes(j.job_status);
      return `
      <article class="card" data-staff-job="${esc(j.job_id)}">
        <div class="section-head"><div><span class="tag">DELIVERY JOB</span><h4>${esc(j.job_reference)}</h4></div><span class="tag">${esc(statusLabels[j.job_status]||j.job_status)}</span></div>
        <p class="muted">${esc(j.package_description)} · প্যাকেজ: ${esc(j.package_count)}</p>
        <div class="grid">
          <div class="offer"><b>Pickup</b><p>${esc(j.pickup_contact_name||"")}</p><p>${esc(j.pickup_contact_phone||"")}</p><p>${esc([j.pickup_address,j.pickup_city,j.pickup_country].filter(Boolean).join(", "))}</p></div>
          <div class="offer"><b>Delivery</b><p>${esc(j.recipient_contact_name||"")}</p><p>${esc(j.recipient_contact_phone||"")}</p><p>${esc([j.delivery_address,j.delivery_city,j.delivery_country].filter(Boolean).join(", "))}</p><p class="muted">সময়সীমা: ${esc(j.delivery_deadline||"নির্ধারিত নয়")}</p></div>
        </div>
        ${options?`<form class="offer" data-staff-status-form="${esc(j.job_id)}">
          <h5>Delivery Status Update</h5><label>পরবর্তী অবস্থা<select name="next_status" required>${options}</select></label>
          <label>সংক্ষিপ্ত অবস্থান (ঐচ্ছিক)<input name="location_label" maxlength="120" placeholder="যেমন: মিরপুর ১০, ঢাকা"></label>
          <label>কাজের নোট (ঐচ্ছিক)<input name="note" maxlength="1000"></label>
          <button class="primary" type="submit">Status Update</button><p class="muted" role="status" aria-live="polite"></p>
        </form>`: ""}
        ${needsOtp?`<form class="offer" data-staff-otp-form="${esc(j.job_id)}">
          <h5>Buyer Receipt Confirmation</h5><p class="muted">Buyer-এর কাছ থেকে পাওয়া ৩২ অক্ষরের OTP যাচাই ছাড়া Delivered করা যাবে না।</p>
          <label>Buyer Receipt OTP<input name="code" minlength="32" maxlength="32" pattern="[0-9A-Fa-f]{32}" autocomplete="one-time-code" required></label>
          <label>Receipt note (ঐচ্ছিক)<input name="note" maxlength="1500"></label>
          <button class="primary" type="submit">OTP যাচাই করে Delivered করুন</button><p class="muted" role="status" aria-live="polite"></p>
        </form>`: ""}
        <form class="offer" data-staff-proof-form="${esc(j.job_id)}">
          <h5>Proof of Delivery / Partial Delivery</h5>
          <div class="grid">
            <label>এবার পৌঁছে দেওয়া পরিমাণ<input name="delivered_quantity" type="number" min="0" step="0.001" value="0" required></label>
            <label>প্যাকেজ সংখ্যা<input name="delivered_package_count" type="number" min="0" max="10000" step="1" value="1" required></label>
            <label>গ্রহণকারীর নাম<input name="recipient_name" maxlength="160"></label>
          </div>
          <label><input name="recipient_acknowledged" type="checkbox" style="width:auto"> গ্রহণকারী পণ্য গ্রহণের বিষয়টি স্বীকার করেছেন</label>
          <label>ডেলিভারির ছবি (সর্বোচ্চ ৫টি)<input name="photos" type="file" accept="image/jpeg,image/png,image/webp" multiple></label>
          <label>গ্রহণকারীর স্বাক্ষরের ছবি<input name="signature" type="file" accept="image/jpeg,image/png,image/webp"></label>
          <label>প্রমাণের নোট (ঐচ্ছিক)<textarea name="proof_note" maxlength="1000"></textarea></label>
          <p class="muted">ছবি ও স্বাক্ষর private storage-এ থাকবে। পূর্ণ ডেলিভারির জন্য Buyer OTP অপরিহার্য।</p>
          <button class="primary" type="submit">প্রমাণ সংরক্ষণ করুন</button><p class="muted" role="status" aria-live="polite"></p>
        </form>
        <form class="offer" data-staff-dispute-form="${esc(j.job_id)}">
          <h5>Delivery Issue / Dispute</h5>
          <label>সমস্যার ধরন<select name="reason_code" required>
            <option value="missing_items">পণ্য কম/অনুপস্থিত</option><option value="damaged_items">পণ্য ক্ষতিগ্রস্ত</option>
            <option value="wrong_items">ভুল পণ্য</option><option value="quantity_mismatch">পরিমাণে অমিল</option>
            <option value="recipient_denies_receipt">গ্রহণকারী গ্রহণ অস্বীকার করেছেন</option><option value="late_delivery">ডেলিভারি দেরি</option>
            <option value="proof_concern">প্রমাণ নিয়ে আপত্তি</option><option value="other">অন্যান্য</option>
          </select></label>
          <label>বিস্তারিত (কমপক্ষে ১০ অক্ষর)<textarea name="description" minlength="10" maxlength="2000" required></textarea></label>
          <button class="light" type="submit">Dispute জমা দিন</button><p class="muted" role="status" aria-live="polite"></p>
        </form>
        <div data-staff-job-history="${esc(j.job_id)}"><p class="muted">Proof ও Dispute history লোড হচ্ছে…</p></div>
      </article>`;
    }).join("");

    const uploadImage=async(jobId,file,index,prefix)=>{
      if(!file)return null;
      if(!["image/jpeg","image/png","image/webp"].includes(file.type)||file.size>10*1024*1024)
        throw new Error("শুধু JPG, PNG বা WebP ছবি (সর্বোচ্চ ১০ MB) আপলোড করুন।");
      const ext=file.type==="image/png"?"png":file.type==="image/webp"?"webp":"jpg";
      const token=(window.crypto?.randomUUID?.()||Date.now()+"-"+index).replace(/[^a-zA-Z0-9-]/g,"");
      const objectPath=jobId+"/"+prefix+"-"+token+"."+ext;
      const {error:uploadError}=await db().storage.from("nexora-delivery-evidence").upload(objectPath,file,{upsert:false,contentType:file.type});
      if(uploadError)throw uploadError;
      return objectPath;
    };

    host.querySelectorAll("[data-staff-status-form]").forEach(form=>form.addEventListener("submit",async event=>{
      event.preventDefault();const button=form.querySelector("button[type=submit]"),status=form.querySelector('[role="status"]'),fd=new FormData(form);
      button.disabled=true;status.textContent="Status সংরক্ষণ হচ্ছে…";
      try{
        const {error:rpcError}=await db().rpc("update_my_delivery_job_status",{
          p_job_id:form.dataset.staffStatusForm,p_next_status:String(fd.get("next_status")),
          p_location_label:String(fd.get("location_label")||"").trim()||null,p_note:String(fd.get("note")||"").trim()||null
        });
        if(rpcError)throw rpcError;status.textContent="Status Update সংরক্ষিত হয়েছে।";await loadAssignedStaffReceiptJobs();
      }catch(err){status.textContent="Update হয়নি: "+err.message;button.disabled=false;}
    }));

    host.querySelectorAll("[data-staff-proof-form]").forEach(form=>form.addEventListener("submit",async event=>{
      event.preventDefault();const button=form.querySelector("button[type=submit]"),status=form.querySelector('[role="status"]'),fd=new FormData(form);
      const jobId=form.dataset.staffProofForm,photos=Array.from(fd.getAll("photos")).filter(x=>x instanceof File&&x.size>0),signature=fd.get("signature");
      if(photos.length>5){status.textContent="সর্বোচ্চ ৫টি ছবি দেওয়া যাবে।";return;}
      button.disabled=true;status.textContent="ছবি/স্বাক্ষর নিরাপদে আপলোড হচ্ছে…";
      try{
        const photoPaths=[];for(let i=0;i<photos.length;i++)photoPaths.push(await uploadImage(jobId,photos[i],i,"proof"));
        const signaturePath=signature instanceof File&&signature.size>0?await uploadImage(jobId,signature,99,"signature"):null;
        const {data:result,error:rpcError}=await db().rpc("record_delivery_proof",{
          p_job_id:jobId,p_delivered_quantity:Number(fd.get("delivered_quantity")||0),
          p_delivered_package_count:Number(fd.get("delivered_package_count")||0),
          p_recipient_name:String(fd.get("recipient_name")||"").trim()||null,
          p_recipient_acknowledged:fd.get("recipient_acknowledged")==="on",
          p_photo_paths:photoPaths,p_signature_path:signaturePath,
          p_note:String(fd.get("proof_note")||"").trim()||null
        });
        if(rpcError)throw rpcError;
        status.textContent="প্রমাণ সংরক্ষিত হয়েছে। বর্তমান অবস্থা: "+(result?.status||"updated");
        form.reset();await loadAssignedStaffReceiptJobs();
      }catch(err){status.textContent="প্রমাণ সংরক্ষণ হয়নি: "+err.message+" (আপলোড হওয়া কিন্তু সংযুক্ত না হওয়া private ফাইল থাকতে পারে)";button.disabled=false;}
    }));

    host.querySelectorAll("[data-staff-otp-form]").forEach(form=>form.addEventListener("submit",async event=>{
      event.preventDefault();const button=form.querySelector("button[type=submit]"),status=form.querySelector('[role="status"]'),fd=new FormData(form);
      button.disabled=true;status.textContent="OTP যাচাই হচ্ছে…";
      try{
        const {data:result,error:rpcError}=await db().rpc("verify_delivery_receipt_code",{
          p_job_id:form.dataset.staffOtpForm,p_code:String(fd.get("code")||"").trim(),
          p_location_description:null,p_note:String(fd.get("note")||"").trim()||null
        });
        if(rpcError)throw rpcError;
        if(result?.verified){status.textContent="OTP সঠিক। Receipt নিশ্চিত হয়েছে।";await loadAssignedStaffReceiptJobs();}
        else{status.textContent="OTP যাচাই হয়নি। "+(result?.reason||("অবশিষ্ট চেষ্টা: "+(result?.attempts_remaining??"—")));button.disabled=false;}
      }catch(err){status.textContent="যাচাই হয়নি: "+err.message;button.disabled=false;}
    }));

    host.querySelectorAll("[data-staff-dispute-form]").forEach(form=>form.addEventListener("submit",async event=>{
      event.preventDefault();const button=form.querySelector("button[type=submit]"),status=form.querySelector('[role="status"]'),fd=new FormData(form);
      button.disabled=true;status.textContent="Dispute জমা হচ্ছে…";
      try{
        const {error:rpcError}=await db().rpc("raise_delivery_dispute",{
          p_job_id:form.dataset.staffDisputeForm,p_reason_code:String(fd.get("reason_code")),
          p_description:String(fd.get("description")||"").trim()
        });
        if(rpcError)throw rpcError;status.textContent="Dispute জমা হয়েছে। NEXORA Admin পর্যালোচনা করবে।";form.reset();await loadAssignedStaffReceiptJobs();
      }catch(err){status.textContent="Dispute জমা হয়নি: "+err.message;button.disabled=false;}
    }));

    for(const job of jobs){
      const history=host.querySelector('[data-staff-job-history="'+job.job_id+'"]');
      if(!history)continue;
      const [proofs,disputes]=await Promise.all([
        db().rpc("get_my_delivery_proof_records",{p_job_id:job.job_id}),
        db().rpc("get_my_delivery_disputes",{p_job_id:job.job_id})
      ]);
      const proofRows=proofs.error?[]:(proofs.data||[]);
      const disputeRows=disputes.error?[]:(disputes.data||[]);
      const proofHtml=proofRows.map(p=>'<div class="offer"><b>Proof · '+esc(new Date(p.created_at).toLocaleString())+'</b><p>পরিমাণ: '+esc(p.delivered_quantity)+' · প্যাকেজ: '+esc(p.delivered_package_count)+'</p><p>গ্রহণকারী: '+esc(p.recipient_name||"উল্লেখ নেই")+' · স্বীকার: '+(p.recipient_acknowledged?"হ্যাঁ":"না")+'</p><p>'+esc(p.note||"")+'</p><div data-proof-images="'+esc(p.proof_id)+'"></div></div>').join("");
      const disputeHtml=disputeRows.map(d=>'<div class="offer"><b>Dispute · '+esc(d.dispute_status)+'</b><p>'+esc(d.reason_code)+' · '+esc(d.description)+'</p><p>'+esc(d.resolution||"পর্যালোচনা/সমাধানের অপেক্ষায়")+'</p></div>').join("");
      history.innerHTML='<h5>Proof & Dispute History</h5>'+(proofHtml||'<p class="muted">এখনো কোনো Proof সংরক্ষিত হয়নি।</p>')+(disputeHtml||'<p class="muted">কোনো Dispute নেই।</p>');
      for(const p of proofRows){
        const imageHost=history.querySelector('[data-proof-images="'+p.proof_id+'"]');
        const paths=[...(p.photo_paths||[]),...(p.signature_path?[p.signature_path]:[])];
        for(const objectPath of paths){
          const {data:signed,error:signedError}=await db().storage.from("nexora-delivery-evidence").createSignedUrl(objectPath,300);
          if(!signedError&&signed?.signedUrl)imageHost?.insertAdjacentHTML("beforeend",'<img src="'+esc(signed.signedUrl)+'" alt="Delivery proof" style="width:100%;max-width:180px;height:130px;object-fit:contain;border-radius:8px;margin:5px">');
        }
      }
    }
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
    await loadAssignedStaffReceiptJobs();
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
    if(activeAccount()) loadAssignedStaffReceiptJobs();
    if(activeAccount() && loadedUserId!==user().id) loadProviders();
    else if(!activeAccount()){providers=[];loadedUserId=null;}
  });
  document.addEventListener("click",event=>{
    if(event.target.closest("#nxTransportProviderNav")) {
      renderShell();loadProviders();loadAssignedStaffReceiptJobs();
    }
  });
  addWorkspaceLink();
  renderShell();
  if(activeAccount()){loadProviders();loadAssignedStaffReceiptJobs();}
})();
