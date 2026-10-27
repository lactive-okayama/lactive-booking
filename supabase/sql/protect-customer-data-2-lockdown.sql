-- ============================================================
-- 顧客情報保護 ステップ2：公開ポリシーを削除（誰でも読み書きできる状態を終わらせる）
-- ※ 必ず「お客様用の窓口（RPC）を使う新しい予約サイト」が公開された後に実行すること。
--    先に実行すると、古い予約サイトから予約・ログインができなくなる。
--
-- 実行後の状態:
--   customers / bookings / blocked_times : 院長アカウント（is_admin()）のみ読み書き可
--   holidays / app_settings              : 誰でも読み取り可（休業日・受付状況の表示用）、書き込みは院長のみ
--   お客様の操作は protect-customer-data-1-functions.sql の窓口（RPC）経由のみ
--   リマインド（メール・LINE）はサービスロールで動くため影響なし
-- ============================================================

drop policy if exists allow_select_customers on public.customers;
drop policy if exists allow_insert_customers on public.customers;
drop policy if exists allow_update_customers on public.customers;
drop policy if exists allow_delete_customers on public.customers;

drop policy if exists allow_select_bookings on public.bookings;
drop policy if exists allow_insert_bookings on public.bookings;
drop policy if exists allow_update_bookings on public.bookings;
drop policy if exists allow_delete_bookings on public.bookings;

drop policy if exists anon_all on public.blocked_times;

drop policy if exists allow_insert_holidays on public.holidays;
drop policy if exists allow_update_holidays on public.holidays;
drop policy if exists allow_delete_holidays on public.holidays;

drop policy if exists allow_insert_app_settings on public.app_settings;
drop policy if exists allow_update_app_settings on public.app_settings;
drop policy if exists allow_delete_app_settings on public.app_settings;

-- 公開キー（anon）からテーブルを直接操作する権限も外す（RLS に加えた二重の守り）
revoke all on public.customers, public.bookings, public.blocked_times from anon;
revoke insert, update, delete, truncate, references, trigger on public.holidays, public.app_settings from anon;
revoke truncate, references, trigger on public.customers, public.bookings, public.holidays, public.app_settings, public.blocked_times from authenticated;

-- 確認：残っているポリシー一覧（admin_all と holidays/app_settings の select のみになっていればOK）
select tablename, policyname, cmd, roles from pg_policies where schemaname = 'public' order by tablename, policyname;
