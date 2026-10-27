-- ============================================================
-- 顧客情報保護 ステップ2の「予行演習」（何も変更されません）
-- ステップ2を一時的に適用して守られているかを試し、最後に必ずエラーで止めて全部取り消す。
-- 結果は赤いエラーメッセージ「予行演習の結果: ...」として表示される（エラーで正常です）。
-- ============================================================
do $$
declare
  n   int;
  out text := '';
begin
  -- ステップ2と同じ内容を一時的に適用
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
  revoke all on public.customers, public.bookings, public.blocked_times from anon;
  revoke insert, update, delete, truncate, references, trigger on public.holidays, public.app_settings from anon;
  revoke truncate, references, trigger on public.customers, public.bookings, public.holidays, public.app_settings, public.blocked_times from authenticated;

  -- 予約サイトを見ている一般の人（公開キー）として試す
  perform set_config('role', 'anon', true);
  begin select count(*) into n from public.customers; out := out || ' / 一般：顧客一覧=' || n || '人';
  exception when others then out := out || ' / 一般：顧客一覧=拒否'; end;
  begin select count(*) into n from public.bookings; out := out || ' / 一般：予約一覧=' || n || '件';
  exception when others then out := out || ' / 一般：予約一覧=拒否'; end;
  begin delete from public.bookings; out := out || ' / 一般：予約削除=できてしまう';
  exception when others then out := out || ' / 一般：予約削除=拒否'; end;
  begin update public.holidays set reason = reason; out := out || ' / 一般：休業日の書き換え=できてしまう';
  exception when others then out := out || ' / 一般：休業日の書き換え=拒否'; end;
  select count(*) into n from public.holidays;
  out := out || ' / 一般：休業日の表示=' || n || '件（必要）';
  select count(*) into n from public.get_booked_ranges(((now() at time zone 'Asia/Tokyo')::date + 1));
  out := out || ' / 一般：空き枠確認=' || n || '件（時間のみ）';

  -- 院長以外のアカウントでログインした場合
  perform set_config('role', 'none', true);
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', '{"role":"authenticated","email":"someone@else.com"}', true);
  select count(*) into n from public.customers;
  out := out || ' / 院長以外：顧客一覧=' || n || '人';

  -- 院長アカウントでログインした場合
  perform set_config('request.jwt.claims', '{"role":"authenticated","email":"info@lactive-care.com"}', true);
  select count(*) into n from public.customers;
  out := out || ' / 院長：顧客一覧=' || n || '人';
  select count(*) into n from public.bookings;
  out := out || ' / 院長：予約一覧=' || n || '件';

  -- ここで必ず止めて、上の変更をすべて取り消す
  raise exception '予行演習の結果: %', substr(out, 4);
end $$;
