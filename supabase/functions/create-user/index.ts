import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  try {
    const authorization = request.headers.get("Authorization");
    if (!authorization?.startsWith("Bearer ")) {
      return json({ error: "Authorization is required" }, 401);
    }
    const accessToken = authorization.substring("Bearer ".length).trim();
    if (!accessToken) return json({ error: "Invalid session" }, 401);

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const secretKey = getDefaultProjectKey(
      "SUPABASE_SECRET_KEYS",
      "SUPABASE_SERVICE_ROLE_KEY",
    );
    if (!supabaseUrl || !secretKey) {
      return json(
        {
          error:
            "The create-user function cannot access a hosted Supabase secret key. Redeploy the function so SUPABASE_SECRET_KEYS/SUPABASE_SERVICE_ROLE_KEY is available.",
        },
        500,
      );
    }

    // The server client is the only privileged client in this function. The
    // caller's access token is passed explicitly to getUser() for verification;
    // the secret key itself is never returned to the Flutter application.
    // Setting the Authorization header explicitly to the service role key
    // ensures PostgREST treats this client as service_role and bypasses RLS.
    const adminClient = createClient(supabaseUrl, secretKey, {
      auth: { autoRefreshToken: false, persistSession: false },
      global: {
        headers: {
          Authorization: `Bearer ${secretKey}`,
        },
      },
    });

    const {
      data: { user: caller },
      error: callerError,
    } = await adminClient.auth.getUser(accessToken);
    if (callerError || !caller) {
      return json({ error: "Invalid or expired Admin session" }, 401);
    }

    const { data: callerProfile, error: callerProfileError } = await adminClient
      .from("profiles")
      .select("role, is_active")
      .eq("id", caller.id)
      .maybeSingle();
    if (callerProfileError) {
      return json(
        { error: `Could not verify Admin profile: ${callerProfileError.message}` },
        500,
      );
    }
    if (!callerProfile) {
      return json(
        {
          error:
            "The signed-in account does not have a RetailFlow profile. Run admin_remote_repair.sql on the hosted database.",
        },
        403,
      );
    }
    if (!callerProfile.is_active) {
      return json({ error: "The signed-in Admin profile is inactive" }, 403);
    }
    if (callerProfile.role !== "admin") {
      return json(
        {
          error:
            `The signed-in account has role "${callerProfile.role}", but only admins can create users.`,
        },
        403,
      );
    }

    let body: Record<string, unknown>;
    try {
      body = await request.json();
    } catch (_) {
      return json({ error: "Request body must be valid JSON" }, 400);
    }

    const email = String(body.email ?? "").trim().toLowerCase();
    const password = String(body.password ?? "");
    const name = String(body.name ?? "").trim();
    const role = String(body.role ?? "employee").trim().toLowerCase();
    let branchId = body.branch_id ? String(body.branch_id).trim() : null;
    if (role === "admin") branchId = null;

    if (!name) return json({ error: "Full name is required" }, 400);
    if (!looksLikeEmail(email)) {
      return json({ error: "A valid email address is required" }, 400);
    }
    if (password.length < 8) {
      return json({ error: "Password must be at least 8 characters" }, 400);
    }
    if (!["employee", "manager", "admin"].includes(role)) {
      return json({ error: "Invalid user role" }, 400);
    }

    if (role !== "admin") {
      if (!branchId) {
        return json({ error: "A branch is required for this role" }, 400);
      }

      const { data: branch, error: branchError } = await adminClient
        .from("branches")
        .select("id")
        .eq("id", branchId)
        .eq("is_active", true)
        .maybeSingle();
      if (branchError) return json({ error: branchError.message }, 500);
      if (!branch) {
        return json({ error: "Selected branch is inactive or missing" }, 400);
      }
    }

    const { data: existingProfile, error: existingProfileError } =
      await adminClient
        .from("profiles")
        .select("id")
        .eq("email", email)
        .limit(1);
    if (existingProfileError) {
      return json({ error: existingProfileError.message }, 500);
    }
    if ((existingProfile?.length ?? 0) > 0) {
      return json({ error: "An account with this email already exists" }, 409);
    }

    const { data, error } = await adminClient.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: {
        name,
        role,
        branch_id: branchId,
        created_by_admin: true,
      },
    });
    if (error) {
      const status = /already|registered|exists/i.test(error.message) ? 409 : 400;
      return json({ error: error.message }, status);
    }
    if (!data.user) {
      return json({ error: "Supabase did not return the created user" }, 500);
    }

    // The Auth trigger creates an employee-first profile. Upsert immediately
    // applies the Admin-selected role/branch and also repairs missing triggers.
    const { error: profileUpsertError } = await adminClient
      .from("profiles")
      .upsert(
        {
          id: data.user.id,
          name,
          email,
          role,
          branch_id: branchId,
          is_active: true,
        },
        { onConflict: "id" },
      );
    if (profileUpsertError) {
      await adminClient.auth.admin.deleteUser(data.user.id);
      return json({ error: profileUpsertError.message }, 500);
    }

    let branchManagerAssigned = false;
    if (role === "manager" && branchId) {
      // Keep the singular primary-manager link and the profile's branch scope
      // aligned. Capture any previous primary manager before replacing it.
      const { data: selectedBranch, error: selectedBranchError } = await adminClient
        .from("branches")
        .select("manager_id")
        .eq("id", branchId)
        .maybeSingle();
      if (selectedBranchError || !selectedBranch) {
        await adminClient.auth.admin.deleteUser(data.user.id);
        return json(
          { error: selectedBranchError?.message ?? "Selected branch no longer exists" },
          500,
        );
      }
      const previousManagerId = selectedBranch.manager_id as string | null;

      const { data: branchRows, error: branchUpdateError } = await adminClient
        .from("branches")
        .update({ manager_id: data.user.id })
        .eq("id", branchId)
        .select("id");
      if (branchUpdateError || (branchRows?.length ?? 0) === 0) {
        await adminClient.auth.admin.deleteUser(data.user.id);
        return json(
          { error: branchUpdateError?.message ?? "Could not assign manager branch" },
          500,
        );
      }

      if (previousManagerId && previousManagerId !== data.user.id) {
        const { data: otherPrimaryBranches } = await adminClient
          .from("branches")
          .select("id")
          .eq("manager_id", previousManagerId)
          .limit(1);
        if ((otherPrimaryBranches?.length ?? 0) === 0) {
          // Best-effort cleanup: the new manager assignment is already valid.
          await adminClient
            .from("profiles")
            .update({ branch_id: null })
            .eq("id", previousManagerId)
            .eq("branch_id", branchId);
        }
      }
      branchManagerAssigned = true;
    }

    return json({
      id: data.user.id,
      email,
      role,
      branch_id: branchId,
      branch_manager_assigned: branchManagerAssigned,
    });
  } catch (error) {
    return json(
      { error: error instanceof Error ? error.message : "Unexpected error" },
      500,
    );
  }
});

function getDefaultProjectKey(jsonName: string, legacyName: string) {
  const jsonValue = Deno.env.get(jsonName);
  if (jsonValue) {
    try {
      const parsed = JSON.parse(jsonValue);
      const value = parsed?.default;
      if (typeof value === "string" && value.length > 0) return value;
    } catch (_) {
      // Fall back to the legacy hosted secret below.
    }
  }
  return Deno.env.get(legacyName) ?? null;
}

function looksLikeEmail(email: string) {
  const at = email.indexOf("@");
  const dot = email.lastIndexOf(".");
  return at > 0 && dot > at + 1 && dot < email.length - 1;
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
