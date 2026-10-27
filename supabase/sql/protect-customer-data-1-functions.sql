-- ============================================================
-- 顧客情報保護 ステップ1：お客様用の窓口（RPC）と管理者用の権限を追加
-- 既存の公開ポリシーはまだ残すため、この時点では今のサイトの動作に影響しない。
-- ステップ2（protect-customer-data-2-lockdown.sql）で公開ポリシーを削除する。
-- ============================================================

-- ── 管理者判定：Supabase Auth でログインした院長アカウントのみ ──
create or replace function public.is_admin()
returns boolean
language sql
stable
set search_path = ''
as $$
  select coalesce(auth.jwt() ->> 'role', '') = 'authenticated'
     and lower(coalesce(auth.jwt() ->> 'email', '')) = 'info@lactive-care.com';
$$;

-- ── 顧客番号＋お名前（姓の前方一致・空白無視）で本人確認 ──
create or replace function public._verify_customer(p_number text, p_name text)
returns public.customers
language sql
stable
security definer
set search_path = ''
as $$
  select c.*
  from public.customers c
  where c.customer_number = p_number
    and length(regexp_replace(coalesce(p_name, ''), '[\s　]', '', 'g')) > 0
    and starts_with(
          regexp_replace(c.name, '[\s　]', '', 'g'),
          regexp_replace(p_name, '[\s　]', '', 'g'))
  limit 1;
$$;
revoke all on function public._verify_customer(text, text) from public, anon, authenticated;

-- メニューごとの所要時間（施術＋インターバル10分）。画面側 MENU_DURATIONS と同じ値
create or replace function public._menu_duration(p_menu text)
returns integer
language sql
immutable
set search_path = ''
as $$
  select case p_menu
    when '初回整体 90分'         then 100
    when '初回ピラティス 60分'    then 70
    when '整体（運動療法）30分'   then 40
    when '整体×ピラティス 45分'  then 55
    when 'マシンピラティス 45分'  then 55
    when 'マットピラティス 45分'  then 55
    else 40
  end;
$$;

create or replace function public._today_jst()
returns date
language sql
stable
set search_path = ''
as $$ select (now() at time zone 'Asia/Tokyo')::date; $$;

-- ── 空き枠確認：時間と所要時間のみ返す（名前などは返さない） ──
create or replace function public.get_booked_ranges(p_date date)
returns table ("time" text, duration integer)
language sql
stable
security definer
set search_path = ''
as $$
  select b.time, coalesce(b.duration, 40) from public.bookings b where b.date = p_date;
$$;

-- ── ログイン：本人の顧客情報を返す（不一致なら0行） ──
create or replace function public.customer_login(p_number text, p_name text)
returns setof public.customers
language sql
stable
security definer
set search_path = ''
as $$
  select * from public._verify_customer(p_number, p_name) c where c.id is not null;
$$;

-- ── 本人の予約一覧 ──
create or replace function public.get_my_bookings(p_number text, p_name text)
returns setof public.bookings
language plpgsql
stable
security definer
set search_path = ''
as $$
declare c public.customers;
begin
  c := public._verify_customer(p_number, p_name);
  if c.id is null then raise exception 'AUTH_FAILED'; end if;
  return query
    select * from public.bookings b
    where b.customer_number = c.customer_number
    order by b.date, b.time;
end;
$$;

-- ── 本人の予約キャンセル（今日以降のみ）。Googleカレンダーの予定IDを返す ──
create or replace function public.cancel_my_booking(p_number text, p_name text, p_booking_id integer)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  c public.customers;
  b public.bookings;
begin
  c := public._verify_customer(p_number, p_name);
  if c.id is null then raise exception 'AUTH_FAILED'; end if;
  select * into b from public.bookings
   where id = p_booking_id and customer_number = c.customer_number;
  if b.id is null then raise exception 'NOT_FOUND'; end if;
  if b.date < public._today_jst() then raise exception 'PAST_BOOKING'; end if;
  -- 来院済みなら、その1回分を手動加算分へ移して来院回数を保持
  if b.visited then
    update public.customers set
      manual_seitai  = manual_seitai  + (case when b.menu like '%整体%'     then 1 else 0 end),
      manual_pilates = manual_pilates + (case when b.menu like '%ピラティス%' then 1 else 0 end)
    where id = c.id;
  end if;
  delete from public.bookings where id = b.id;
  return b.gcal_event_id;
end;
$$;

-- ── 本人の連絡先変更（今後の予約にも反映） ──
create or replace function public.update_my_profile(p_number text, p_name text, p_phone text, p_email text)
returns setof public.customers
language plpgsql
security definer
set search_path = ''
as $$
declare c public.customers;
begin
  c := public._verify_customer(p_number, p_name);
  if c.id is null then raise exception 'AUTH_FAILED'; end if;
  if coalesce(trim(p_phone), '') = '' or coalesce(trim(p_email), '') = '' then
    raise exception 'REQUIRED';
  end if;
  update public.customers set phone = trim(p_phone), email = trim(p_email) where id = c.id;
  update public.bookings set phone = trim(p_phone), email = trim(p_email)
   where customer_number = c.customer_number and date >= public._today_jst();
  return query select * from public.customers where id = c.id;
end;
$$;

-- ── 新規登録：重複しない6桁の顧客番号を発行 ──
create or replace function public.register_customer(p_name text, p_phone text, p_email text)
returns setof public.customers
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_number text;
  v_tries  integer := 0;
begin
  if coalesce(trim(p_name), '') = '' or coalesce(trim(p_phone), '') = '' or coalesce(trim(p_email), '') = '' then
    raise exception 'REQUIRED';
  end if;
  loop
    v_number := (100000 + floor(random() * 900000))::integer::text;
    exit when not exists (select 1 from public.customers where customer_number = v_number);
    v_tries := v_tries + 1;
    if v_tries > 5000 then raise exception 'NUMBER_EXHAUSTED'; end if;
  end loop;
  return query
    insert into public.customers (customer_number, name, phone, email)
    values (v_number, trim(p_name), trim(p_phone), trim(p_email))
    returning *;
end;
$$;

-- ── 予約登録：重なりをデータベース側でも確認（同じ日の同時登録は順番に処理） ──
create or replace function public.create_booking(p jsonb)
returns setof public.bookings
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin    boolean := public.is_admin();
  v_date     date    := (p ->> 'date')::date;
  v_time     text    := p ->> 'time';
  v_menu     text    := p ->> 'menu';
  v_number   text    := nullif(p ->> 'customer_number', '');
  v_duration integer := public._menu_duration(v_menu);
  v_start    integer;
  c          public.customers;
begin
  if v_date is null or coalesce(v_time, '') !~ '^\d{1,2}:\d{2}$' or coalesce(v_menu, '') = ''
     or coalesce(trim(p ->> 'name'), '') = '' then
    raise exception 'REQUIRED';
  end if;
  if not v_admin and v_date <= public._today_jst() then raise exception 'PAST_DATE'; end if;
  -- 顧客番号つきの予約は本人確認（管理者は不要）
  if v_number is not null and not v_admin then
    c := public._verify_customer(v_number, p ->> 'login_name');
    if c.id is null then raise exception 'AUTH_FAILED'; end if;
  end if;

  v_start := split_part(v_time, ':', 1)::integer * 60 + split_part(v_time, ':', 2)::integer;
  perform pg_advisory_xact_lock(hashtext('booking:' || v_date::text));
  if exists (
    select 1 from public.bookings b
    where b.date = v_date
      and v_start < split_part(b.time, ':', 1)::integer * 60 + split_part(b.time, ':', 2)::integer + coalesce(b.duration, 40)
      and split_part(b.time, ':', 1)::integer * 60 + split_part(b.time, ':', 2)::integer < v_start + v_duration
  ) then
    raise exception 'SLOT_CONFLICT';
  end if;

  return query
    insert into public.bookings (
      customer_number, name, phone, email, menu, date, time, duration, memo,
      symptom, treatment_history, symptom_start, exercise_ok, daily_impact, line_user_id)
    values (
      v_number, trim(p ->> 'name'), coalesce(p ->> 'phone', ''), coalesce(p ->> 'email', ''),
      v_menu, v_date, v_time, v_duration, nullif(p ->> 'memo', ''),
      nullif(p ->> 'symptom', ''), nullif(p ->> 'treatment_history', ''), nullif(p ->> 'symptom_start', ''),
      nullif(p ->> 'exercise_ok', ''), nullif(p ->> 'daily_impact', ''), nullif(p ->> 'line_user_id', ''))
    returning *;
end;
$$;

-- ── 予約直後の Googleカレンダー予定ID / LINE ID の保存（未設定の場合のみ） ──
create or replace function public.set_booking_gcal_event(p_booking_id integer, p_event_id text)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.bookings set gcal_event_id = p_event_id
   where id = p_booking_id and gcal_event_id is null;
$$;

create or replace function public.set_booking_line_user(p_booking_id integer, p_line_user_id text)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.bookings set line_user_id = p_line_user_id
   where id = p_booking_id and line_user_id is null
     and created_at > (now() at time zone 'UTC') - interval '1 day';
$$;

-- 実行権限：お客様（anon）と管理者（authenticated）に窓口のみ許可
do $$
declare f text;
begin
  foreach f in array array[
    'public.get_booked_ranges(date)',
    'public.customer_login(text, text)',
    'public.get_my_bookings(text, text)',
    'public.cancel_my_booking(text, text, integer)',
    'public.update_my_profile(text, text, text, text)',
    'public.register_customer(text, text, text)',
    'public.create_booking(jsonb)',
    'public.set_booking_gcal_event(integer, text)',
    'public.set_booking_line_user(integer, text)'
  ] loop
    execute format('revoke all on function %s from public', f);
    execute format('grant execute on function %s to anon, authenticated', f);
  end loop;
end $$;

-- ── 管理者（院長アカウント）に全テーブルの読み書きを許可 ──
do $$
declare t text;
begin
  foreach t in array array['customers', 'bookings', 'holidays', 'app_settings', 'blocked_times'] loop
    execute format('drop policy if exists admin_all on public.%I', t);
    execute format(
      'create policy admin_all on public.%I for all to authenticated using (public.is_admin()) with check (public.is_admin())', t);
  end loop;
end $$;
