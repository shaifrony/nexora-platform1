
const seed = [
  {
    id: "p1",
    name: "Fresh Mango",
    category: "Food & Agriculture",
    origin: "Rajshahi, Bangladesh",
    details: "Seasonal fresh mangoes.",
    price: "",
    emoji: "🥭"
  },
  {
    id: "p2",
    name: "Premium Rice",
    category: "Food & Agriculture",
    origin: "Dinajpur, Bangladesh",
    details: "Quality rice for wholesale buyers.",
    price: "",
    emoji: "🌾"
  },
  {
    id: "p3",
    name: "Red Lentils",
    category: "Food & Agriculture",
    origin: "Bangladesh",
    details: "Red lentils for food distributors.",
    price: "",
    emoji: "🫘"
  }
];

const $ = id => document.getElementById(id);

const safe = value =>
  String(value ?? "").replace(/[&<>"']/g, c => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#39;"
  }[c]));

function readProducts() {
  try {
    return JSON.parse(localStorage.getItem("nexora_products")) || seed;
  } catch {
    return seed;
  }
}

let products = readProducts();

function render() {
  const q = $("q").value.trim().toLowerCase();
  const cat = $("cat").value;

  const filtered = products.filter(p =>
    (p.name + " " + p.origin + " " + p.details)
      .toLowerCase().includes(q) &&
    (!cat || p.category === cat)
  );

  $("list").innerHTML = filtered.length
    ? filtered.map(p => `
      <article class="product-card">
        <div class="product-visual">${p.emoji || "📦"}</div>
        <div class="product-body">
          <h3>${safe(p.name)}</h3>
          <p>${safe(p.category)}</p>
          <p>${safe(p.details)}</p>
          <p>📍 ${safe(p.origin)}</p>
          ${p.price ? `<p>Price: ${safe(p.price)}</p>` : ""}
          <button type="button" data-contact="${safe(p.id)}">
            Inquiry
          </button>
        </div>
      </article>
    `).join("")
    : "<p>No products found.</p>";
}

$("q").addEventListener("input", render);
$("cat").addEventListener("change", render);

// Account button
$("accountBtn").addEventListener("click", () => {
  const oldProfile = JSON.parse(
    localStorage.getItem("nexora_profile") || "{}"
  );

  const name = prompt("আপনার নাম লিখুন:", oldProfile.name || "");
  if (name === null) return;

  const email = prompt("আপনার ইমেইল লিখুন:", oldProfile.email || "");
  if (email === null) return;

  localStorage.setItem("nexora_profile", JSON.stringify({
    name,
    email
  }));

  alert("আপনার ডেমো প্রোফাইল এই ডিভাইসে সংরক্ষিত হয়েছে।");
});

// Add product
$("addForm").addEventListener("submit", e => {
  e.preventDefault();

  const data = new FormData(e.currentTarget);

  const product = {
    id: "p" + Date.now(),
    name: data.get("name"),
    category: data.get("category"),
    origin: data.get("country"),
    details: data.get("details") || "Contact supplier for details.",
    price: data.get("price"),
    emoji: "📦"
  };

  products.unshift(product);

  localStorage.setItem(
    "nexora_products",
    JSON.stringify(products)
  );

  e.currentTarget.reset();
  render();

  alert("পণ্য সফলভাবে যোগ হয়েছে।");
});

// Product inquiry
$("list").addEventListener("click", e => {
  const id = e.target.dataset.contact;
  if (!id) return;

  const product = products.find(p => p.id === id);

  if (product) {
    alert("পণ্য: " + product.name +
      "\nযোগাযোগের ব্যবস্থা পরবর্তী ধাপে যুক্ত করা হবে।");
  }
});

render();
