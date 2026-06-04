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
    const supabaseUrl       = Deno.env.get("SUPABASE_URL") ?? "https://wuthbgxzmvjeosugzfbs.supabase.co";
    const serviceRoleKey    = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const messagingToken    = Deno.env.get("LINE_MESSAGING_ACCESS_TOKEN");

    if (!serviceRoleKey || !messagingToken) {
      return new Response(
        JSON.stringify({ error: "必要な環境変数が設定されていません" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // 明日の日付を JST (UTC+9) で計算
    const nowUtc = new Date();
    const jstOffset = 9 * 60 * 60 * 1000;
    const nowJst = new Date(nowUtc.getTime() + jstOffset);
    const tomorrow = new Date(nowJst.getTime() + 24 * 60 * 60 * 1000);
    const tomorrowStr = tomorrow.toISOString().slice(0, 10); // YYYY-MM-DD

    // 明日の予約でLINE連携済みのものを取得
    const dbRes = await fetch(
      `${supabaseUrl}/rest/v1/bookings?date=eq.${tomorrowStr}&line_user_id=not.is.null&select=id,name,menu,date,time,line_user_id`,
      {
        headers: {
          "apikey": serviceRoleKey,
          "Authorization": `Bearer ${serviceRoleKey}`,
          "Content-Type": "application/json",
        },
      }
    );

    if (!dbRes.ok) {
      const err = await dbRes.text();
      return new Response(
        JSON.stringify({ error: "DB取得失敗", detail: err }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const bookings = await dbRes.json();

    const results: { id: string; name: string; success: boolean; error?: string }[] = [];

    for (const booking of bookings) {
      const message = `${booking.name} さま\nご予約の【1日前】となりましたので、念のためお知らせ申し上げます。\nご予約内容は下記の通りとなります。\n\n◇ 予約日時\n　${booking.date} ${booking.time}\n　${booking.menu}\n※ キャンセルの場合はサイトよりお願いいたします。\n\n一緒に痛みのもどらない身体を作っていきましょう！\n当日お会いできるのを楽しみにしております☺\n\n【注意事項&お願い】\n・動きやすい服装&5本指ソックスの着用\n・来院はご予約の5分前もしくは時間ちょうど\n・遅刻された場合は、遅刻分を差し引いた施術時間となります\n・当日キャンセルは1回分の消化となります`;

      const lineRes = await fetch("https://api.line.me/v2/bot/message/push", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${messagingToken}`,
        },
        body: JSON.stringify({
          to: booking.line_user_id,
          messages: [{ type: "text", text: message }],
        }),
      });

      if (lineRes.ok) {
        results.push({ id: booking.id, name: booking.name, success: true });
      } else {
        const errData = await lineRes.json();
        results.push({ id: booking.id, name: booking.name, success: false, error: JSON.stringify(errData) });
      }
    }

    return new Response(
      JSON.stringify({
        date: tomorrowStr,
        total: bookings.length,
        results,
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
