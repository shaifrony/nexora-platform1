/* NEXORA environment routing: allow one explicitly approved Development Preview only. */
(() => {
  "use strict";
  const host = String(window.location.hostname || "").toLowerCase();
  const approvedTestHost = "nexora-platform1-git-nexora-development-shaifrony-7200.vercel.app";
  const isVercelHost = host === "vercel.app" || host.endsWith(".vercel.app");

  if (host === approvedTestHost) {
    window.NEXORA_SUPABASE_CONFIG = {
      environment: "test",
      url: "https://lhxmqoyxoywntmkmmnjb.supabase.co",
      publishableKey: "sb_publishable_uSXGnwAD5qcf2i5Vf8uFOA_XXCXSq9u"
    };
    document.documentElement.dataset.nexoraBackend = "test";
    return;
  }

  if (isVercelHost) {
    window.NEXORA_SUPABASE_CONFIG = { environment: "blocked", blocked: true };
    document.documentElement.dataset.nexoraBackend = "blocked";
    return;
  }

  window.NEXORA_SUPABASE_CONFIG = { environment: "production" };
  document.documentElement.dataset.nexoraBackend = "production";
})();
