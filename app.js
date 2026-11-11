const seed = [
 {id:"p1",name:"Fresh Mango",category:"Fruit",trade:"Export",origin:"Rajshahi, Bangladesh",description:"Seasonal fresh mangoes. Variety and packaging details available on inquiry.",emoji:"🥭",contact:"demo@nexora.example"},
 {id:"p2",name:"Premium Rice",category:"Grain",trade:"Wholesale",origin:"Dinajpur, Bangladesh",description:"Quality rice for wholesale buyers. Request sample and specifications.",emoji:"🌾",contact:"demo@nexora.example"},
 {id:"p3",name:"Red Lentils",category:"Pulse",trade:"Export",origin:"Bangladesh",description:"Red lentils for food distributors and importers.",emoji:"🫘",contact:"demo@nexora.example"}
];
const read = (key, fallback) => { try { return JSON.parse(localStorage.getItem(key)) ?? fallback; } catch { return fallback; } };
let products = read("nexora_products", seed);
const $ = id => document.getElementById(id);
const safe = s => String(s ?? "").replace(/[&<>"']/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
function render(){
 const q=$("search").value.trim().toLowerCase(), cat=$("category").value, trade=$("type").value;
 const filtered=products.filter(p=>(p.name+" "+p.origin+" "+p.description).toLowerCase().includes(q)&&(cat==="all"||p.category===cat)&&(trade==="all"||p.trade===trade));
 $("productCount").textContent=products.length;
 $("products").innerHTML=filtered.length?filtered.map(p=>`<article class="product-card"><div class="product-visual">${p.emoji||"📦"}</div><div class="product-body"><span class="pill">${safe(p.trade)}</span><h3>${safe(p.name)}</h3><p>${safe(p.description)}</p><div class="product-foot"><small>📍 ${safe(p.origin)}</small><button class="text-btn" data-contact="${safe(p.id)}">Inquire →</button></div></div></article>`).join(""):`<div class="empty">No products match your search.</div>`;
}
["search","category","type"].forEach(id=>$(id).addEventListener("input",render));
$("addProductBtn").onclick=()=>$("productDialog").showModal();
$("profileBtn").onclick=()=>$("profileDialog").showModal();
document.querySelectorAll("[data-close]").forEach(b=>b.onclick=()=>$(b.dataset.close).close());
$("productForm").addEventListener("submit",e=>{
 e.preventDefault();const d=new FormData(e.currentTarget);
 const p={id:"p"+Date.now(),name:d.get("name"),category:d.get("category"),trade:d.get("trade"),origin:d.get("origin"),description:d.get("description")||"Contact supplier for details.",contact:d.get("contact"),emoji:({Fruit:"🍎",Grain:"🌾",Pulse:"🫘"}[d.get("category")]||"📦")};
 products.unshift(p);localStorage.setItem("nexora_products",JSON.stringify(products));e.currentTarget.reset();$("productDialog").close();render();
});
$("profileForm").addEventListener("submit",e=>{e.preventDefault();const d=new FormData(e.currentTarget);localStorage.setItem("nexora_profile",JSON.stringify(Object.fromEntries(d)));$("profileDialog").close();alert("Demo profile saved on this device.");});
$("products").addEventListener("click",e=>{const id=e.target.dataset.contact;if(!id)return;const p=products.find(x=>x.id===id);if(p)alert("Demo inquiry contact: "+p.contact+"\\n\\nIn the live version, this will create a buyer inquiry.");});
if("serviceWorker" in navigator && location.protocol!=="file:"){window.addEventListener("load",()=>navigator.serviceWorker.register("./sw.js").catch(()=>{}));}
render();
