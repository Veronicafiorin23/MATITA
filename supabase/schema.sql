-- MATITA shared public mode (fresh Supabase project)
-- Run this first, then seed.sql. All visitors use one shared progress record.
create extension if not exists pgcrypto with schema extensions;

create table if not exists public.question_catalog (
  question_id text primary key,
  discipline text not null check (discipline in ('Matemática','Inglês')),
  year integer not null,
  semester integer not null check (semester in (1,2)),
  question_number integer not null,
  topic text not null,
  priority text not null check (priority in ('Verde','Azul','Amarelo','Especial')),
  source_page integer not null check (source_page > 0),
  annulled boolean not null default false,
  unique(discipline,year,semester,question_number)
);
create index if not exists question_catalog_sampling_idx on public.question_catalog(discipline,annulled,topic);

create table if not exists public.question_progress (
  user_id uuid not null check (user_id='00000000-0000-4000-8000-000000000001'::uuid),
  question_id text not null references public.question_catalog(question_id) on delete cascade,
  solved_at timestamptz not null default now(),
  resolution_path text not null,
  resolution_mime text not null check (resolution_mime in ('application/pdf','image/jpeg','image/png','image/webp')),
  note text not null default '' check (char_length(note)<=2000),
  primary key(user_id,question_id)
);
create table if not exists public.simulations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null check (user_id='00000000-0000-4000-8000-000000000001'::uuid),
  discipline text not null check (discipline in ('Matemática','Inglês')),
  created_at timestamptz not null default now()
);
create table if not exists public.simulation_questions (
  simulation_id uuid not null references public.simulations(id) on delete cascade,
  user_id uuid not null check (user_id='00000000-0000-4000-8000-000000000001'::uuid),
  question_id text not null references public.question_catalog(question_id) on delete cascade,
  position integer not null check(position>0),
  primary key(simulation_id,question_id),
  unique(user_id,question_id),
  unique(simulation_id,position)
);
create index if not exists simulation_questions_shared_idx on public.simulation_questions(user_id,question_id);

alter table public.question_catalog enable row level security;
alter table public.question_progress enable row level security;
alter table public.simulations enable row level security;
alter table public.simulation_questions enable row level security;
revoke all on public.question_catalog,public.question_progress,public.simulations,public.simulation_questions from anon,authenticated;
grant select on public.question_catalog,public.question_progress,public.simulations,public.simulation_questions to anon,authenticated;
grant insert,update on public.question_progress to anon,authenticated;

drop policy if exists "public reads question catalog" on public.question_catalog;
create policy "public reads question catalog" on public.question_catalog for select to anon,authenticated using(true);
drop policy if exists "public reads shared progress" on public.question_progress;
create policy "public reads shared progress" on public.question_progress for select to anon,authenticated using(user_id='00000000-0000-4000-8000-000000000001'::uuid);
drop policy if exists "public writes shared progress" on public.question_progress;
create policy "public writes shared progress" on public.question_progress for insert to anon,authenticated with check(user_id='00000000-0000-4000-8000-000000000001'::uuid);
drop policy if exists "public updates shared progress" on public.question_progress;
create policy "public updates shared progress" on public.question_progress for update to anon,authenticated using(user_id='00000000-0000-4000-8000-000000000001'::uuid) with check(user_id='00000000-0000-4000-8000-000000000001'::uuid);
drop policy if exists "public reads shared simulations" on public.simulations;
create policy "public reads shared simulations" on public.simulations for select to anon,authenticated using(user_id='00000000-0000-4000-8000-000000000001'::uuid);
drop policy if exists "public reads shared simulation questions" on public.simulation_questions;
create policy "public reads shared simulation questions" on public.simulation_questions for select to anon,authenticated using(user_id='00000000-0000-4000-8000-000000000001'::uuid);

create or replace function public.create_simulation(p_discipline text,p_count integer)
returns uuid language plpgsql security definer set search_path='' as $$
declare
  v_user_id constant uuid := '00000000-0000-4000-8000-000000000001';
  v_simulation_id uuid;
  v_inserted integer;
begin
  if p_discipline not in ('Matemática','Inglês') then raise exception 'invalid discipline'; end if;
  if p_count is null or p_count<1 or p_count>100 then raise exception 'question count must be between 1 and 100'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('MATITA-shared-simulation'));
  insert into public.simulations(user_id,discipline) values(v_user_id,p_discipline) returning id into v_simulation_id;
  if p_discipline='Matemática' then
    insert into public.simulation_questions(simulation_id,user_id,question_id,position)
    select v_simulation_id,v_user_id,pick.question_id,row_number() over(order by pick.sample_order)::integer
    from (
      select q.question_id,pg_catalog.random()/greatest(w.target_count::double precision/greatest(w.available_count,1),0.000001) as sample_order
      from public.question_catalog q join (
        select c.topic,count(*)::double precision as target_count,
        count(*) filter(where not exists(select 1 from public.question_progress p where p.user_id=v_user_id and p.question_id=c.question_id) and not exists(select 1 from public.simulation_questions sq where sq.user_id=v_user_id and sq.question_id=c.question_id))::double precision as available_count
        from public.question_catalog c where c.discipline='Matemática' and not c.annulled group by c.topic
      ) w on w.topic=q.topic
      where q.discipline='Matemática' and not q.annulled and w.available_count>0
        and not exists(select 1 from public.question_progress p where p.user_id=v_user_id and p.question_id=q.question_id)
        and not exists(select 1 from public.simulation_questions sq where sq.user_id=v_user_id and sq.question_id=q.question_id)
      order by sample_order limit p_count
    ) pick;
  else
    insert into public.simulation_questions(simulation_id,user_id,question_id,position)
    select v_simulation_id,v_user_id,q.question_id,row_number() over(order by pg_catalog.random())::integer
    from public.question_catalog q where q.discipline='Inglês' and not q.annulled
      and not exists(select 1 from public.question_progress p where p.user_id=v_user_id and p.question_id=q.question_id)
      and not exists(select 1 from public.simulation_questions sq where sq.user_id=v_user_id and sq.question_id=q.question_id)
    order by pg_catalog.random() limit p_count;
  end if;
  get diagnostics v_inserted=row_count;
  if v_inserted=0 then delete from public.simulations where id=v_simulation_id; raise exception 'no new questions available for this discipline'; end if;
  return v_simulation_id;
end;
$$;
revoke all on function public.create_simulation(text,integer) from public,anon,authenticated;
grant execute on function public.create_simulation(text,integer) to anon,authenticated;

-- Source PDFs are public. Resolutions are also public, and any visitor can replace them.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values
 ('proof-pdfs','proof-pdfs',true,26214400,array['application/pdf']),
 ('user-resolutions','user-resolutions',true,20971520,array['application/pdf','image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=excluded.public,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists "public uploads shared resolutions" on storage.objects;
create policy "public uploads shared resolutions" on storage.objects for insert to anon,authenticated with check(bucket_id='user-resolutions' and (storage.foldername(name))[1]='shared');
drop policy if exists "public updates shared resolutions" on storage.objects;
create policy "public updates shared resolutions" on storage.objects for update to anon,authenticated using(bucket_id='user-resolutions' and (storage.foldername(name))[1]='shared') with check(bucket_id='user-resolutions' and (storage.foldername(name))[1]='shared');
drop policy if exists "public deletes shared resolutions" on storage.objects;
create policy "public deletes shared resolutions" on storage.objects for delete to anon,authenticated using(bucket_id='user-resolutions' and (storage.foldername(name))[1]='shared');

