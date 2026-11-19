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
grant insert on public.simulations,public.simulation_questions to anon,authenticated;

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
drop policy if exists "public creates shared simulations" on public.simulations;
create policy "public creates shared simulations" on public.simulations for insert to anon,authenticated with check(user_id='00000000-0000-4000-8000-000000000001'::uuid);
drop policy if exists "public reads shared simulation questions" on public.simulation_questions;
create policy "public reads shared simulation questions" on public.simulation_questions for select to anon,authenticated using(user_id='00000000-0000-4000-8000-000000000001'::uuid);
drop policy if exists "public creates shared simulation questions" on public.simulation_questions;
create policy "public creates shared simulation questions" on public.simulation_questions for insert to anon,authenticated with check(user_id='00000000-0000-4000-8000-000000000001'::uuid);

do $matita$
declare t text;
begin
  foreach t in array array['question_progress','simulations','simulation_questions','study_modules','study_pdfs'] loop
    if not exists (
      select 1 from pg_catalog.pg_publication_tables
      where pubname='supabase_realtime' and schemaname='public' and tablename=t
    ) then
      execute pg_catalog.format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $matita$;

create or replace function public.create_simulation(p_discipline text,p_count integer)
returns uuid language plpgsql security invoker set search_path='' as $$
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
  if v_inserted=0 then raise exception 'no new questions available for this discipline'; end if;
  return v_simulation_id;
end;
$$;
revoke all on function public.create_simulation(text,integer) from public,anon,authenticated;
grant execute on function public.create_simulation(text,integer) to anon,authenticated;

-- Source PDFs are public. Resolutions are also public, and any visitor can replace them.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values
 ('user-resolutions','user-resolutions',true,20971520,array['application/pdf','image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=excluded.public,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists "public uploads shared resolutions" on storage.objects;
create policy "public uploads shared resolutions" on storage.objects for insert to anon,authenticated with check(bucket_id='user-resolutions' and (storage.foldername(name))[1]='shared');
drop policy if exists "public updates shared resolutions" on storage.objects;
create policy "public updates shared resolutions" on storage.objects for update to anon,authenticated using(bucket_id='user-resolutions' and (storage.foldername(name))[1]='shared') with check(bucket_id='user-resolutions' and (storage.foldername(name))[1]='shared');
drop policy if exists "public deletes shared resolutions" on storage.objects;
create policy "public deletes shared resolutions" on storage.objects for delete to anon,authenticated using(bucket_id='user-resolutions' and (storage.foldername(name))[1]='shared');



-- Shared study handouts: modules and public PDF files, maximum 20 MiB per file.
create table if not exists public.study_modules (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null check(user_id='00000000-0000-4000-8000-000000000001'::uuid),
  title text not null check(char_length(btrim(title)) between 1 and 120),
  subject text not null check(subject in ('Álgebra','Geometria','Cálculo','Combinatória','Matrizes e determinantes','Trigonometria','Probabilidade','Estatística','Sequências e séries','Compreensão e gramática')),
  priority text not null check(priority in ('Verde','Azul','Amarelo','Especial')),
  created_at timestamptz not null default now()
);
create table if not exists public.study_pdfs (
  id uuid primary key default gen_random_uuid(),
  module_id uuid not null references public.study_modules(id) on delete cascade,
  user_id uuid not null check(user_id='00000000-0000-4000-8000-000000000001'::uuid),
  title text not null check(char_length(btrim(title)) between 1 and 160),
  object_path text not null unique,
  file_size bigint not null check(file_size between 1 and 20971520),
  mime_type text not null check(mime_type='application/pdf'),
  created_at timestamptz not null default now()
);
create index if not exists study_pdfs_module_idx on public.study_pdfs(module_id,created_at);
alter table public.study_modules enable row level security;
alter table public.study_pdfs enable row level security;
revoke all on public.study_modules,public.study_pdfs from anon,authenticated;
grant select,insert on public.study_modules,public.study_pdfs to anon,authenticated;
drop policy if exists "public reads shared study modules" on public.study_modules;
create policy "public reads shared study modules" on public.study_modules for select to anon,authenticated using(user_id='00000000-0000-4000-8000-000000000001'::uuid);
drop policy if exists "public creates shared study modules" on public.study_modules;
create policy "public creates shared study modules" on public.study_modules for insert to anon,authenticated with check(user_id='00000000-0000-4000-8000-000000000001'::uuid);
drop policy if exists "public reads shared study pdfs" on public.study_pdfs;
create policy "public reads shared study pdfs" on public.study_pdfs for select to anon,authenticated using(user_id='00000000-0000-4000-8000-000000000001'::uuid);
drop policy if exists "public creates shared study pdfs" on public.study_pdfs;
create policy "public creates shared study pdfs" on public.study_pdfs for insert to anon,authenticated with check(
  user_id='00000000-0000-4000-8000-000000000001'::uuid
  and exists(select 1 from public.study_modules m where m.id=module_id and m.user_id='00000000-0000-4000-8000-000000000001'::uuid)
);
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('study-handouts','study-handouts',true,20971520,array['application/pdf'])
on conflict(id) do update set public=excluded.public,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;
drop policy if exists "public uploads shared study pdfs" on storage.objects;
create policy "public uploads shared study pdfs" on storage.objects for insert to anon,authenticated with check(
  bucket_id='study-handouts'
  and (storage.foldername(name))[1]='shared'
  and array_length(storage.foldername(name),1)=2
  and lower(name) like '%.pdf'
  and exists(select 1 from public.study_modules m where m.id::text=(storage.foldername(name))[2] and m.user_id='00000000-0000-4000-8000-000000000001'::uuid)
);
