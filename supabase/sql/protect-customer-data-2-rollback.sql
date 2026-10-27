-- ============================================================
-- 【緊急用】ステップ2を元に戻す（予約サイトが動かなくなった場合のみ実行）
-- ステップ2で削除した「誰でも読み書き可」の状態に戻す。顧客情報は再び外から読める状態になるため、
-- 原因を直したら、もう一度 protect-customer-data-2-lockdown.sql を実行すること。
-- ============================================================
grant select, insert, update, delete on public.customers, public.bookings, public.blocked_times to anon;
grant insert, update, delete on public.holidays, public.app_settings to anon;

create policy allow_select_customers on public.customers for select using (true);
create policy allow_insert_customers on public.customers for insert with check (true);
create policy allow_update_customers on public.customers for update using (true) with check (true);
create policy allow_delete_customers on public.customers for delete using (true);

create policy allow_select_bookings on public.bookings for select using (true);
create policy allow_insert_bookings on public.bookings for insert with check (true);
create policy allow_update_bookings on public.bookings for update using (true) with check (true);
create policy allow_delete_bookings on public.bookings for delete using (true);

create policy anon_all on public.blocked_times for all to anon using (true) with check (true);

create policy allow_insert_holidays on public.holidays for insert with check (true);
create policy allow_update_holidays on public.holidays for update using (true) with check (true);
create policy allow_delete_holidays on public.holidays for delete using (true);

create policy allow_insert_app_settings on public.app_settings for insert with check (true);
create policy allow_update_app_settings on public.app_settings for update using (true) with check (true);
create policy allow_delete_app_settings on public.app_settings for delete using (true);
