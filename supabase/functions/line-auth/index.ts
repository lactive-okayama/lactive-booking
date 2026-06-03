import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { code, redirect_uri } = await req.json();

    const channelId     = Deno.env.get("LINE_LOGIN_CHANNEL_ID");
    const channelSecret = Deno.env.get("LINE_LOGIN_CHANNEL_SECRET");

    if (!channelId || !channelSecret) {
      return new Response(
        JSON.stringify({ error: "LINE認証情報が設定されていません" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ① 認可コード → アクセストークン交換
    const tokenRes = await fetch("https://api.line.me/oauth2/v2.1/token", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type:    "authorization_code",
        code,
        redirect_uri,
        client_id:     channelId,
        client_secret: channelSecret,
      }),
    });

    const tokenData = await tokenRes.json();
    if (!tokenRes.ok) {
      return new Response(
        JSON.stringify({ error: "トークン取得失敗", detail: tokenData }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ② プロフィール取得
    const profileRes = await fetch("https://api.line.me/v2/profile", {
      headers: { "Authorization": `Bearer ${tokenData.access_token}` },
    });

    if (!profileRes.ok) {
      return new Response(
        JSON.stringify({ error: "プロフィール取得失敗" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const profile = await profileRes.json();

    return new Response(
      JSON.stringify({
        line_user_id: profile.userId,
        display_name: profile.displayName,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (err) {
    return new Response(
      JSON.stringify({ error: err.message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
