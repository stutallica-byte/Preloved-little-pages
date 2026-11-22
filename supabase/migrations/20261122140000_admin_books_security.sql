begin;

create table if not exists public.admin_users (
  user_id uuid primary key references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.admin_users enable row level security;
revoke all on table public.admin_users from public, anon, authenticated;
grant select on table public.admin_users to authenticated;

drop policy if exists admin_users_read_self on public.admin_users;
create policy admin_users_read_self
  on public.admin_users
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.admin_users
    where user_id = (select auth.uid())
  );
$$;

revoke all on function public.is_admin() from public, anon;
grant execute on function public.is_admin() to authenticated;

alter table public.books enable row level security;
revoke select, insert, update, delete, truncate, references, trigger
  on table public.books
  from public, anon, authenticated;

do $$
declare
  column_record record;
begin
  for column_record in
    select attribute.attname
    from pg_attribute as attribute
    where attribute.attrelid = 'public.books'::regclass
      and attribute.attnum > 0
      and not attribute.attisdropped
  loop
    execute format(
      'revoke select (%I) on table public.books from public, anon, authenticated',
      column_record.attname
    );
  end loop;
end
$$;

grant select (id, created_at, title, author, price, condition, description, image_url, sold)
  on table public.books
  to anon, authenticated;
grant insert, update, delete on table public.books to authenticated;

do $$
declare
  identity_sequence regclass;
begin
  identity_sequence := pg_get_serial_sequence('public.books', 'id')::regclass;
  if identity_sequence is null then
    raise exception 'Could not find the identity sequence for public.books.id';
  end if;

  execute format(
    'grant usage on sequence %s to authenticated',
    identity_sequence
  );
end
$$;

drop policy if exists books_public_read on public.books;
create policy books_public_read
  on public.books
  for select
  to anon, authenticated
  using (true);

drop policy if exists books_admin_insert on public.books;
create policy books_admin_insert
  on public.books
  for insert
  to authenticated
  with check ((select public.is_admin()));

drop policy if exists books_admin_update on public.books;
create policy books_admin_update
  on public.books
  for update
  to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

drop policy if exists books_admin_delete on public.books;
create policy books_admin_delete
  on public.books
  for delete
  to authenticated
  using ((select public.is_admin()));

drop policy if exists books_admin_insert_guard on public.books;
create policy books_admin_insert_guard
  on public.books
  as restrictive
  for insert
  to authenticated
  with check ((select public.is_admin()));

drop policy if exists books_admin_update_guard on public.books;
create policy books_admin_update_guard
  on public.books
  as restrictive
  for update
  to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

drop policy if exists books_admin_delete_guard on public.books;
create policy books_admin_delete_guard
  on public.books
  as restrictive
  for delete
  to authenticated
  using ((select public.is_admin()));

insert into storage.buckets (id, name, public)
values (
  'books-images',
  'books-images',
  true
)
on conflict (id) do update
set public = excluded.public;

drop policy if exists books_images_admin_access on storage.objects;
create policy books_images_admin_access
  on storage.objects
  for all
  to authenticated
  using (bucket_id = 'books-images' and (select public.is_admin()))
  with check (bucket_id = 'books-images' and (select public.is_admin()));

drop policy if exists books_images_admin_guard on storage.objects;
create policy books_images_admin_guard
  on storage.objects
  as restrictive
  for all
  to authenticated
  using (bucket_id <> 'books-images' or (select public.is_admin()))
  with check (bucket_id <> 'books-images' or (select public.is_admin()));

drop policy if exists books_images_anon_guard on storage.objects;
create policy books_images_anon_guard
  on storage.objects
  as restrictive
  for all
  to anon
  using (bucket_id <> 'books-images')
  with check (bucket_id <> 'books-images');

commit;
