import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';

const LINE_CHANNEL_ACCESS_TOKEN =
  'WeY8NGZzIV/NM65obLnwdIplo6t9hyfaRIsH4HKWOF0eZccbxyl78W6uV2d46ZIIWYLiGpjrBffmXn07lUH6urxH7uKLaONXvxcUtIYBu9JuJWPEAlFgFddptVW+ygXwokERqvksnFdupkCe8daW6wdB04t89/1O/w1cDnyilFU=';

const LINE_USER_ID = '2004832726';

// 日付フォーマット（YYYY-MM-DD → YYYY年M月D日）
function formatDate(s: string): string {
  if (!s) return '';
  const [y, m, d] = s.split('-');
  return `${y}年${parseInt(m)}月${parseInt(d)}日`;
}

serve(async (req: Request) => {
  // CORS プリフライト対応
  if (req.method === 'OPTIONS') {
    return new Response('ok', {
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization',
      },
    });
  }

  try {
    const body = await req.json();
    const { name, menu, date, time, phone, memo } = body;

    // LINEメッセージ本文を組み立て
    const lines: string[] = [
      '【新規予約】',
      `お名前：${name ?? ''} 様`,
      `メニュー：${menu ?? ''}`,
      `日時：${formatDate(date ?? '')} ${time ?? ''}`,
      `電話番号：${phone ?? ''}`,
    ];
    if (memo) lines.push(`メモ：${memo}`);
    const messageText = lines.join('\n');

    // LINE Messaging API push message
    const lineRes = await fetch('https://api.line.me/v2/bot/message/push', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${LINE_CHANNEL_ACCESS_TOKEN}`,
      },
      body: JSON.stringify({
        to: LINE_USER_ID,
        messages: [{ type: 'text', text: messageText }],
      }),
    });

    if (!lineRes.ok) {
      const errText = await lineRes.text();
      console.error('LINE API error:', lineRes.status, errText);
      return new Response(
        JSON.stringify({ ok: false, error: errText }),
        {
          status: 200, // 予約側でエラー扱いしないよう 200 を返す
          headers: {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
          },
        },
      );
    }

    return new Response(
      JSON.stringify({ ok: true }),
      {
        status: 200,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*',
        },
      },
    );
  } catch (e) {
    console.error('Edge Function error:', e);
    return new Response(
      JSON.stringify({ ok: false, error: String(e) }),
      {
        status: 200, // 予約側に影響させない
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*',
        },
      },
    );
  }
});
