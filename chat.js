/* NEXORA Private Chat — Supabase RLS protected */
(() => {
  "use strict";
  const $ = id => document.getElementById(id);
  const auth = () => window.NEXORA_AUTH;
  const db = () => auth()?.client;
  const user = () => auth()?.user;
  const esc = v => String(v ?? "").replace(/[&<>"']/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
  const state = { conversationId: null, channel: null, callChannel: null, conversations: [], participants: [], directory: [], messages: [], pc: null, localStream: null, activeCall: null, incomingCall: null, pendingIce: [] };
  const note = (msg, ok=false) => { const n=$("chatNotice"); if(n){n.textContent=msg;n.style.color=ok?"#087b5f":"#b42318";} };
  const isSignedIn = () => Boolean(user()?.id);

  function setChatVisible(id) {
    if (!id) return;
    const previous = window.showSection;
    if (typeof previous === "function" && !previous.__chatWrapped) {
      const wrapped = function(sectionId) {
        previous(sectionId);
        if (sectionId === "privateChat") loadChatHome();
      };
      wrapped.__chatWrapped = true;
      window.showSection = wrapped;
    }
  }

  async function loadDirectory() {
    const host=$("chatDirectory");
    if(!host || !isSignedIn()) return;
    host.textContent="ব্যবহারকারী তালিকা লোড হচ্ছে…";
    const {data,error}=await db().from("public_profiles").select("id,full_name").neq("id",user().id).order("full_name").limit(100);
    if(error){host.textContent="তালিকা লোড হয়নি: "+error.message;return;}
    state.directory=data||[];
    host.innerHTML=state.directory.length?state.directory.map(p=>`
      <button class="light chat-person" type="button" data-user="${esc(p.id)}">${esc(p.full_name||"NEXORA User")}</button>`).join(""):"এখনো অন্য কোনো ব্যবহারকারী নেই।";
    host.querySelectorAll("[data-user]").forEach(b=>b.addEventListener("click",()=>startConversation(b.dataset.user)));
  }

  async function loadChatHome() {
    if(!isSignedIn()){ $("chatLoginHint").classList.remove("hidden"); $("chatWorkspace").classList.add("hidden"); return; }
    $("chatLoginHint").classList.add("hidden"); $("chatWorkspace").classList.remove("hidden");
    await Promise.all([loadDirectory(),loadConversationList()]);
  }

  async function loadConversationList() {
    const host=$("chatConversationList");
    if(!host || !isSignedIn()) return;
    host.textContent="চ্যাট লোড হচ্ছে…";
    const {data,error}=await db().from("conversations")
      .select("id,title,conversation_type,status,created_by,created_at")
      .order("updated_at",{ascending:false}).limit(100);
    if(error){host.textContent="চ্যাট লোড হয়নি: "+error.message;return;}
    state.conversations=data||[];
    if(!data?.length){host.textContent="এখনো কোনো চ্যাট নেই। নতুন ব্যবহারকারী নির্বাচন করে যোগাযোগের অনুরোধ পাঠান।";return;}
    const parts=await db().from("conversation_participants").select("conversation_id,user_id,invitation_status").in("conversation_id",data.map(x=>x.id));
    const partMap=new Map();
    (parts.data||[]).forEach(p=>{if(!partMap.has(p.conversation_id))partMap.set(p.conversation_id,[]);partMap.get(p.conversation_id).push(p);});
    host.innerHTML=data.map(c=>{
      const mine=(partMap.get(c.id)||[]).find(p=>p.user_id===user().id);
      const label=mine?.invitation_status==="pending"?" • "+(c.title||"যোগাযোগের অনুরোধ"):(c.title||"Private Conversation");
      return `<button class="light chat-thread" type="button" data-conversation="${esc(c.id)}">${esc(label)}</button>`;
    }).join("");
    host.querySelectorAll("[data-conversation]").forEach(b=>b.addEventListener("click",()=>openConversation(b.dataset.conversation)));
  }

  async function startConversation(targetId) {
    if(!isSignedIn() || targetId===user().id) return;
    const existing=state.conversations.find(c=>c.conversation_type==="direct" && c.created_by===user().id && c.status==="active");
    if(existing){
      const {data}=await db().from("conversation_participants").select("user_id").eq("conversation_id",existing.id).eq("user_id",targetId).maybeSingle();
      if(data){await openConversation(existing.id);return;}
    }
    try{
      const {data:conversation,error}=await db().from("conversations").insert({
        conversation_type:"direct",created_by:user().id,title:"NEXORA Direct Chat"
      }).select("id").single();
      if(error) throw error;
      const {error:selfError}=await db().from("conversation_participants").insert({
        conversation_id:conversation.id,user_id:user().id,invited_by:user().id,invitation_status:"accepted",joined_at:new Date().toISOString()
      });
      if(selfError) throw selfError;
      const {error:inviteError}=await db().from("conversation_participants").insert({
        conversation_id:conversation.id,user_id:targetId,invited_by:user().id,invitation_status:"pending"
      });
      if(inviteError) throw inviteError;
      note("যোগাযোগের অনুরোধ পাঠানো হয়েছে। অপর পক্ষ গ্রহণ করলে চ্যাট শুরু হবে।",true);
      await loadConversationList();
      await openConversation(conversation.id);
    }catch(e){note("অনুরোধ পাঠানো যায়নি: "+e.message);}
  }

  async function openConversation(id) {
    state.conversationId=id;
    if(state.channel){await db().removeChannel(state.channel);state.channel=null;}
    const {data:parts,error:partError}=await db().from("conversation_participants")
      .select("user_id,invitation_status").eq("conversation_id",id);
    if(partError){note("Conversation access error: "+partError.message);return;}
    state.participants=parts||[];
    const mine=state.participants.find(p=>p.user_id===user().id);
    const head=$("chatCurrentTitle");
    const host=$("chatMessages");
    if(mine?.invitation_status==="pending"){
      head.textContent="যোগাযোগের অনুরোধ";
      host.innerHTML='<div class="offer">এই ব্যবহারকারী আপনার সঙ্গে যোগাযোগ করতে চান। গ্রহণ করলে চ্যাট শুরু হবে।<div class="form-actions"><button class="primary" id="acceptChatInvite">Accept</button><button class="danger" id="declineChatInvite">Decline</button></div></div>';
      $("chatComposer").classList.add("hidden");
      $("chatCallPanel")?.classList.add("hidden");
      $("acceptChatInvite").onclick=()=>respondInvite(id,"accepted");
      $("declineChatInvite").onclick=()=>respondInvite(id,"declined");
      return;
    }
    if(mine?.invitation_status!=="accepted"){note("এই চ্যাটে আপনার প্রবেশাধিকার নেই।");return;}
    const others=state.participants.filter(p=>p.user_id!==user().id);
    head.textContent="Private Chat • "+others.length+" participant(s)";
    $("chatComposer").classList.remove("hidden");
    $("chatCallPanel")?.classList.remove("hidden");
    await loadMessages(id);
    state.channel=db().channel("nexora-chat-"+id)
      .on("postgres_changes",{event:"INSERT",schema:"public",table:"messages",filter:"conversation_id=eq."+id},payload=>{
        if(payload.new.sender_id!==user().id) appendMessage(payload.new);
      })
      .on("postgres_changes",{event:"INSERT",schema:"public",table:"message_attachments",filter:"conversation_id=eq."+id},payload=>appendAttachmentLink(payload.new))
      .subscribe();
  }

  async function respondInvite(id,decision){
    const {error}=await db().from("conversation_participants").update({
      invitation_status:decision,joined_at:decision==="accepted"?new Date().toISOString():null
    }).eq("conversation_id",id).eq("user_id",user().id);
    if(error){note("সিদ্ধান্ত সংরক্ষণ হয়নি: "+error.message);return;}
    note(decision==="accepted"?"যোগাযোগের অনুরোধ গ্রহণ করেছেন।":"অনুরোধ প্রত্যাখ্যান করেছেন।",true);
    await loadConversationList();
    if(decision==="accepted") await openConversation(id);
    else {$("chatMessages").textContent="অনুরোধ প্রত্যাখ্যান করা হয়েছে।";$("chatComposer").classList.add("hidden");}
  }

  async function loadMessages(id){
    const host=$("chatMessages");
    host.textContent="বার্তা লোড হচ্ছে…";
    const {data,error}=await db().from("messages")
      .select("id,conversation_id,sender_id,body,message_type,created_at,edited_at,deleted_at")
      .eq("conversation_id",id).order("created_at",{ascending:true}).limit(200);
    if(error){host.textContent="বার্তা লোড হয়নি: "+error.message;return;}
    state.messages=data||[];
    host.innerHTML="";
    for(const m of state.messages) appendMessage(m);
    host.scrollTop=host.scrollHeight;
  }

  async function appendMessage(m){
    const host=$("chatMessages");if(!host||host.querySelector('[data-message="'+m.id+'"]'))return;
    const own=m.sender_id===user()?.id;
    const item=document.createElement("div");
    item.className="offer";item.dataset.message=m.id;
    const time=new Date(m.created_at).toLocaleString();
    item.innerHTML=`<strong>${own?"You":"NEXORA User"}</strong><p>${esc(m.deleted_at?"এই বার্তাটি মুছে ফেলা হয়েছে।":m.body)}</p><span class="muted">${esc(time)}</span>`;
    host.appendChild(item);
    if(m.message_type==="image"||m.message_type==="file"){
      const {data:attachment}=await db().from("message_attachments").select("id,message_id,storage_path,file_name").eq("message_id",m.id).maybeSingle();
      if(attachment) await appendAttachmentLink(attachment);
    }
    host.scrollTop=host.scrollHeight;
  }

  async function appendAttachmentLink(attachment){
    const item=$("chatMessages")?.querySelector('[data-message="'+attachment.message_id+'"]');
    if(!item || item.querySelector("[data-attachment-link]"))return;
    const {data:signed,error}=await db().storage.from("nexora-chat-files").createSignedUrl(attachment.storage_path,3600);
    if(error||!signed?.signedUrl)return;
    const link=document.createElement("a");link.href=signed.signedUrl;link.target="_blank";link.rel="noopener noreferrer";
    link.textContent="Open / Download: "+attachment.file_name;link.dataset.attachmentLink="true";
    link.className="secondary";link.style.display="inline-block";link.style.padding="8px 10px";link.style.borderRadius="7px";
    item.appendChild(link);
  }

  async function sendMessage(e){
    e.preventDefault();
    const form=e.currentTarget;
    if(!state.conversationId)return;
    const body=String(new FormData(form).get("body")||"").trim();
    if(!body)return;
    const btn=form.querySelector("button[type=submit]");btn.disabled=true;
    const {data,error}=await db().from("messages").insert({
      conversation_id:state.conversationId,sender_id:user().id,body,message_type:"text"
    }).select("id,conversation_id,sender_id,body,message_type,created_at").single();
    btn.disabled=false;
    if(error){note("বার্তা পাঠানো যায়নি: "+error.message);return;}
    appendMessage(data);form.reset();
  }

  async function uploadChatFile(e){
    const file=e.target.files?.[0];if(!file||!state.conversationId)return;
    if(file.size>20*1024*1024){note("ফাইলের সর্বোচ্চ সীমা ২০ MB।");e.target.value="";return;}
    const allowed=["image/jpeg","image/png","image/webp","application/pdf","text/plain","application/vnd.openxmlformats-officedocument.wordprocessingml.document","application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"];
    if(!allowed.includes(file.type)){note("এই ফাইলের ধরন অনুমোদিত নয়।");e.target.value="";return;}
    const path=state.conversationId+"/"+crypto.randomUUID()+"/"+file.name.replace(/[^a-zA-Z0-9._-]/g,"_");
    try{
      const {error:uploadError}=await db().storage.from("nexora-chat-files").upload(path,file,{contentType:file.type,upsert:false});
      if(uploadError)throw uploadError;
      const {data:msg,error:msgError}=await db().from("messages").insert({
        conversation_id:state.conversationId,sender_id:user().id,body:file.name,message_type:file.type.startsWith("image/")?"image":"file"
      }).select("id,conversation_id,sender_id,body,message_type,created_at").single();
      if(msgError)throw msgError;
      const {error:metaError}=await db().from("message_attachments").insert({
        message_id:msg.id,conversation_id:state.conversationId,uploaded_by:user().id,
        storage_path:path,file_name:file.name,mime_type:file.type,size_bytes:file.size
      });
      if(metaError)throw metaError;
      appendMessage(msg);note("ফাইল পাঠানো হয়েছে।",true);
    }catch(err){note("ফাইল পাঠানো যায়নি: "+err.message);}
    finally{e.target.value="";}
  }


  function setCallStatus(message){const n=$("callStatus");if(n)n.textContent=message;}
  async function sendCallSignal(signalType,payload={}){
    const c=state.activeCall;if(!c)return;
    const {error}=await db().from("call_signals").insert({
      call_id:c.id,conversation_id:c.conversationId,sender_id:user().id,
      recipient_id:c.remoteUserId,signal_type:signalType,payload
    });
    if(error)note("Call signaling error: "+error.message);
  }
  async function setupCallNotifications(){
    if(!isSignedIn()||state.callChannel)return;
    state.callChannel=db().channel("nexora-incoming-calls-"+user().id)
      .on("postgres_changes",{event:"INSERT",schema:"public",table:"call_signals",filter:"recipient_id=eq."+user().id},payload=>handleCallSignal(payload.new))
      .subscribe();
  }
  async function handleCallSignal(signal){
    if(signal.signal_type==="offer"){
      if(state.activeCall){return;}
      state.incomingCall=signal;
      if(typeof window.showSection==="function")window.showSection("privateChat");
      await openConversation(signal.conversation_id);
      $("incomingCall").classList.remove("hidden");
      $("incomingCallText").textContent="Incoming "+(signal.payload.call_type||"audio")+" call";
      return;
    }
    if(!state.activeCall||signal.call_id!==state.activeCall.id)return;
    try{
      if(signal.signal_type==="answer"){
        await state.pc.setRemoteDescription(new RTCSessionDescription({type:"answer",sdp:signal.payload.sdp}));
        await flushIce();
        setCallStatus("Call connected.");
      }else if(signal.signal_type==="ice-candidate"){
        const candidate=new RTCIceCandidate(signal.payload.candidate);
        if(state.pc.remoteDescription)await state.pc.addIceCandidate(candidate);
        else state.pendingIce.push(candidate);
      }else if(signal.signal_type==="hangup"||signal.signal_type==="busy"){
        closeCall(signal.signal_type==="busy"?"The other participant is unavailable.":"The other participant ended the call.");
      }
    }catch(err){note("Call connection error: "+err.message);}
  }
  async function flushIce(){
    if(!state.pc?.remoteDescription)return;
    for(const candidate of state.pendingIce.splice(0)){try{await state.pc.addIceCandidate(candidate);}catch(e){}}
  }
  async function createPeerConnection(){
    const pc=new RTCPeerConnection({iceServers:[{urls:"stun:stun.l.google.com:19302"}]});
    state.pc=pc;
    state.localStream.getTracks().forEach(track=>pc.addTrack(track,state.localStream));
    const remote=new MediaStream();
    $("remoteCallVideo").srcObject=remote;
    $("localCallVideo").srcObject=state.localStream;
    pc.ontrack=e=>e.streams[0]?.getTracks().forEach(t=>remote.addTrack(t));
    pc.onicecandidate=e=>{if(e.candidate)sendCallSignal("ice-candidate",{candidate:e.candidate.toJSON()});};
    pc.onconnectionstatechange=()=>{
      if(pc.connectionState==="connected")setCallStatus("Connected.");
      if(pc.connectionState==="failed")setCallStatus("Connection failed. This network may require a TURN relay.");
      if(pc.connectionState==="disconnected")setCallStatus("Connection interrupted…");
    };
    $("endCall").classList.remove("hidden");
  }
  async function startCall(type){
    if(!state.conversationId)return;
    const others=state.participants.filter(p=>p.user_id!==user().id&&p.invitation_status==="accepted");
    if(others.length!==1){note("এখন এক-টু-এক Audio/Video Call সমর্থিত; Group Call পরে যোগ হবে।");return;}
    if(!navigator.mediaDevices?.getUserMedia||!window.RTCPeerConnection){note("এই Browser-এ WebRTC বা Microphone/Camera API পাওয়া যাচ্ছে না। HTTPS ব্যবহার করুন।");return;}
    try{
      state.localStream=await navigator.mediaDevices.getUserMedia({audio:true,video:type==="video"});
      const {data:session,error}=await db().from("call_sessions").insert({
        conversation_id:state.conversationId,initiated_by:user().id,call_type:type,call_status:"ringing"
      }).select("id").single();
      if(error)throw error;
      state.activeCall={id:session.id,conversationId:state.conversationId,remoteUserId:others[0].user_id,type};
      await createPeerConnection();
      const offer=await state.pc.createOffer();
      await state.pc.setLocalDescription(offer);
      await sendCallSignal("offer",{sdp:offer.sdp,call_type:type});
      setCallStatus(type==="video"?"Video call ringing…":"Audio call ringing…");
    }catch(err){closeCall("Call could not start: "+err.message);}
  }
  async function acceptIncomingCall(){
    const signal=state.incomingCall;if(!signal)return;
    try{
      const {data:session,error}=await db().from("call_sessions").select("id,call_type,conversation_id").eq("id",signal.call_id).single();
      if(error)throw error;
      if(!navigator.mediaDevices?.getUserMedia)throw new Error("Microphone/Camera permission API unavailable.");
      state.localStream=await navigator.mediaDevices.getUserMedia({audio:true,video:session.call_type==="video"});
      state.activeCall={id:session.id,conversationId:session.conversation_id,remoteUserId:signal.sender_id,type:session.call_type};
      await createPeerConnection();
      await state.pc.setRemoteDescription(new RTCSessionDescription({type:"offer",sdp:signal.payload.sdp}));
      await flushIce();
      const answer=await state.pc.createAnswer();
      await state.pc.setLocalDescription(answer);
      const {error:updateError}=await db().from("call_sessions").update({call_status:"accepted",started_at:new Date().toISOString()}).eq("id",session.id);
      if(updateError)throw updateError;
      await sendCallSignal("answer",{sdp:answer.sdp});
      state.incomingCall=null;$("incomingCall").classList.add("hidden");
      setCallStatus("Connecting…");
    }catch(err){note("Call গ্রহণ করা যায়নি: "+err.message);closeCall("Call setup failed.");}
  }
  async function declineIncomingCall(){
    const signal=state.incomingCall;if(!signal)return;
    await db().from("call_sessions").update({call_status:"declined",ended_at:new Date().toISOString()}).eq("id",signal.call_id);
    state.activeCall={id:signal.call_id,conversationId:signal.conversation_id,remoteUserId:signal.sender_id};
    await sendCallSignal("busy",{});
    state.activeCall=null;state.incomingCall=null;$("incomingCall").classList.add("hidden");
    setCallStatus("Call declined.");
  }
  async function endCall(){
    if(state.activeCall){
      await sendCallSignal("hangup",{});
      await db().from("call_sessions").update({call_status:"ended",ended_at:new Date().toISOString()}).eq("id",state.activeCall.id);
    }
    closeCall("Call ended.");
  }
  function closeCall(message){
    if(state.pc){state.pc.onicecandidate=null;state.pc.close();state.pc=null;}
    if(state.localStream){state.localStream.getTracks().forEach(t=>t.stop());state.localStream=null;}
    if($("localCallVideo"))$("localCallVideo").srcObject=null;
    if($("remoteCallVideo"))$("remoteCallVideo").srcObject=null;
    if($("endCall"))$("endCall").classList.add("hidden");
    if($("incomingCall"))$("incomingCall").classList.add("hidden");
    state.activeCall=null;state.incomingCall=null;state.pendingIce=[];
    setCallStatus(message);
  }

  $("startAudioCall")?.addEventListener("click",()=>startCall("audio"));
  $("startVideoCall")?.addEventListener("click",()=>startCall("video"));
  $("acceptIncomingCall")?.addEventListener("click",acceptIncomingCall);
  $("declineIncomingCall")?.addEventListener("click",declineIncomingCall);
  $("endCall")?.addEventListener("click",endCall);
  $("chatComposer")?.addEventListener("submit",sendMessage);
  $("chatFile")?.addEventListener("change",uploadChatFile);
  window.addEventListener("nexora:auth-change",()=>{state.conversationId=null;if(state.channel){db().removeChannel(state.channel);state.channel=null;}if(state.callChannel){db().removeChannel(state.callChannel);state.callChannel=null;}closeCall("Authentication state changed.");if(isSignedIn())setupCallNotifications();if($("privateChat")&&!$("privateChat").classList.contains("hidden"))loadChatHome();});
  setChatVisible(true);
  if(isSignedIn())setupCallNotifications();
})();