// 管理者パスワード検証用 Edge Function
// パスワードは Supabase の Edge Function 環境変数 `ADMIN_PASSWORD` に保存して読み出す
// （ダッシュボード → Project Settings → Edge Functions → Add new secret で設定）

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
};

serve(async (req: Request) => {
  // CORS プリフライト対応
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const { password } = await req.json();
    const expected = Deno.env.get('ADMIN_PASSWORD') ?? '';

    if (!expected) {
      console.error('ADMIN_PASSWORD secret が設定されていません');
      return new Response(
        JSON.stringify({ isValid: false, error: 'server-misconfigured' }),
        { status: 500, headers: { 'Content-Type': 'application/json', ...corsHeaders } },
      );
    }

    const isValid = typeof password === 'string' && password === expected;

    return new Response(
      JSON.stringify({ isValid }),
      { status: 200, headers: { 'Content-Type': 'application/json', ...corsHeaders } },
    );
  } catch (e) {
    console.error('verify-admin error:', e);
    return new Response(
      JSON.stringify({ isValid: false, error: String(e) }),
      { status: 200, headers: { 'Content-Type': 'application/json', ...corsHeaders } },
    );
  }
});
