-- ============================================================
-- pg_cron ジョブ確認・設定用 SQL
-- Supabase ダッシュボード → SQL Editor で実行してください
-- ============================================================

-- 1) 現在のジョブ一覧を確認
SELECT jobid, schedule, command, active, jobname
FROM cron.job
ORDER BY jobid;

-- ============================================================
-- 2) （未設定の場合）毎日深夜0時(JST)に visit_count を再集計するジョブを作成
--    JST 0:00 = UTC 15:00 → cron は UTC 基準なので '0 15 * * *'
-- ============================================================
-- pg_cron 拡張を有効化（一度だけ）
-- CREATE EXTENSION IF NOT EXISTS pg_cron;

-- ジョブ登録例（既存ジョブは先に unschedule してから）
-- SELECT cron.unschedule('recount-visit-count');

-- SELECT cron.schedule(
--   'recount-visit-count',
--   '0 15 * * *',  -- 毎日 UTC 15:00 = JST 0:00
--   $$
--   UPDATE customers c
--   SET visit_count = sub.cnt
--   FROM (
--     SELECT customer_number, COUNT(*) AS cnt
--     FROM bookings
--     WHERE visited = true AND customer_number IS NOT NULL
--     GROUP BY customer_number
--   ) sub
--   WHERE c.customer_number = sub.customer_number;
--
--   -- 来院記録が一件もない顧客は 0 にリセット
--   UPDATE customers
--   SET visit_count = 0
--   WHERE customer_number NOT IN (
--     SELECT DISTINCT customer_number
--     FROM bookings
--     WHERE visited = true AND customer_number IS NOT NULL
--   );
--   $$
-- );

-- ============================================================
-- 3) ジョブ実行履歴の確認
-- ============================================================
-- SELECT * FROM cron.job_run_details
-- ORDER BY start_time DESC
-- LIMIT 20;

-- ============================================================
-- 4) RLS ポリシーの確認（toggleVisited が動かない場合に確認）
-- ============================================================
-- SELECT schemaname, tablename, policyname, cmd, qual, with_check
-- FROM pg_policies
-- WHERE tablename IN ('bookings', 'customers');
