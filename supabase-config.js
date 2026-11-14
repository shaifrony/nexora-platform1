/* NEXORA environment routing: explicit host allowlist; unknown hosts fail closed. */
(() => {
  "use strict";
  const host = String(window.location.hostname || "").toLowerCase();
  const approvedTestHost = "nexora-platform1-git-nexora-development-shaifrony-7200.vercel.app";
  const approvedProductionHost = "nexora-platform1-mu.vercel.app";

  if (host === approvedTestHost) {
    window.NEXORA_SUPABASE_CONFIG = {
      environment: "test",
      url: "https://lhxmqoyxoywntmkmmnjb.supabase.co",
      publishableKey: "sb_publishable_uSXGnwAD5qcf2i5Vf8uFOA_XXCXSq9u"
    };
    document.documentElement.dataset.nexoraBackend = "test";
    return;
  }

  if (host === approvedProductionHost) {
    window.NEXORA_SUPABASE_CONFIG = {
      environment: "production",
      url: "https://qsjdeqljpnjumceewsjq.supabase.co",
      publishableKey: "sb_publishable_ZHxwvrwjAn2_UCCYsNLu8A_9twoGAKs"
    };
    document.documentElement.dataset.nexoraBackend = "production";
    return;
  }

  window.NEXORA_SUPABASE_CONFIG = { environment: "blocked", blocked: true };
  document.documentElement.dataset.nexoraBackend = "blocked";
})();
