// NEXORA Director-only officer provisioning endpoint.
// Deploy only after the companion SQL migration has been tested on an isolated database.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const authorization = req.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) return json({ error: "Authentication required" }, 401);

  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !anonKey || !serviceKey) return json({ error: "Server configuration incomplete" }, 500);

  const token = authorization.slice("Bearer ".length);
  const callerClient = createClient(url, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const adminClient = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  try {
    const { data: claimsData, error: claimsError } = await callerClient.auth.getClaims(token);
    if (claimsError || !claimsData?.claims?.sub || claimsData.claims.aal !== "aal2") {
      return json({ error: "Director MFA verification is required" }, 403);
    }

    const { data: caller, error: callerError } = await callerClient.auth.getUser(token);
    if (callerError || !caller.user) return json({ error: "Invalid session" }, 401);

    const { data: staff, error: staffError } = await adminClient
      .from("admin_staff")
      .select("admin_level,is_active")
      .eq("user_id", caller.user.id)
      .maybeSingle();
    if (staffError) throw staffError;
    if (!staff || staff.admin_level !== "super_admin" || staff.is_active !== true) {
      return json({ error: "Only the active Director can manage officer accounts" }, 403);
    }

    const body = await req.json();
    const action = String(body.action ?? "");
    const email = String(body.email ?? "").trim().toLowerCase();
    const fullName = String(body.full_name ?? "").trim();
    const department = body.department_key ? String(body.department_key) : null;
    const position = body.position_key ? String(body.position_key) : null;
    const permissions = Array.isArray(body.permissions) ? body.permissions : [];
    const reason = body.reason ? String(body.reason).trim() : null;

    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return json({ error: "Valid officer email required" }, 400);
    if (!["create", "update", "deactivate"].includes(action)) return json({ error: "Unsupported action" }, 400);
    if (action === "create" && fullName.length < 2) return json({ error: "Officer full name is required" }, 400);
    if (permissions.some((p: unknown) => typeof p !== "string")) return json({ error: "Invalid permission list" }, 400);

    let invitedUserId: string | null = null;
    if (action === "create") {
      const redirectTo = Deno.env.get("NEXORA_SITE_URL");
      const { data: invitation, error: inviteError } = await adminClient.auth.admin.inviteUserByEmail(
        email,
        {
          data: { full_name: fullName, account_purpose: "nexora_internal_officer" },
          ...(redirectTo ? { redirectTo } : {}),
        },
      );
      if (inviteError) return json({ error: inviteError.message }, 409);
      invitedUserId = invitation.user?.id ?? null;
      if (!invitedUserId) return json({ error: "Auth invitation did not return a user" }, 502);
    }

    const { data, error } = await callerClient.rpc("manage_nexora_officer", {
      p_email: email,
      p_action: action,
      p_department_key: department,
      p_position_key: position,
      p_permissions: permissions,
      p_reason: reason,
    });

    if (error) {
      if (invitedUserId) {
        const { error: cleanupError } = await adminClient.auth.admin.deleteUser(invitedUserId);
        if (cleanupError) {
          return json({
            error: "Invitation was sent but officer assignment failed. Director must review the pending Auth user.",
            detail: error.message,
          }, 500);
        }
      }
      return json({ error: error.message }, 400);
    }

    return json(data ?? { success: true });
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : "Unexpected server error" }, 500);
  }
});
