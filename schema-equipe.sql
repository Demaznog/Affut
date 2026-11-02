-- =====================================================================
--  Brisées — schéma de partage en équipe
--  Supabase / PostgreSQL — à coller dans SQL Editor, puis exécuter.
--
--  Principe : tout membre d'une équipe voit et modifie tout ce que
--  l'équipe produit. La dernière écriture l'emporte, l'horodatage
--  étant posé par le serveur et non par le téléphone.
--
--  AVANT D'EXÉCUTER : Authentication > Providers > Anonymous > activer.
--  Sans cela, personne ne peut se connecter.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. ÉQUIPES ET MEMBRES
-- ---------------------------------------------------------------------

create table if not exists equipe (
  id          uuid primary key default gen_random_uuid(),
  nom         text not null,
  code        text not null unique,          -- code d'accès, 8 caractères
  cree_par    uuid not null default auth.uid(),
  cree_le     timestamptz not null default now()
);

create table if not exists membre (
  equipe_id   uuid not null references equipe(id) on delete cascade,
  user_id     uuid not null default auth.uid(),
  nom         text not null,                 -- « Bernard », affiché sur les fiches
  role        text not null default 'chasseur' check (role in ('chef','chasseur')),
  rejoint_le  timestamptz not null default now(),
  primary key (equipe_id, user_id)
);
create index if not exists membre_user on membre(user_id);

-- Les équipes de l'utilisateur courant. En SECURITY DEFINER pour éviter
-- une récursion : les politiques de membre interrogeraient membre.
create or replace function mes_equipes()
returns setof uuid language sql stable security definer set search_path = public as $$
  select equipe_id from membre where user_id = auth.uid();
$$;

-- ---------------------------------------------------------------------
-- 2. DONNÉES DE TERRAIN
-- ---------------------------------------------------------------------
--  Les compositions restent en JSON : elles épousent la nomenclature
--  cynégétique, qui varie d'une espèce à l'autre, et l'application
--  les manipule déjà sous cette forme.

create table if not exists territoire (
  id          uuid primary key default gen_random_uuid(),
  equipe_id   uuid not null references equipe(id) on delete cascade,
  nom         text not null,
  dep         text,
  ring        jsonb not null default '[]'::jsonb,   -- [[lat,lng], ...]
  auteur      uuid not null default auth.uid(),
  cree_le     timestamptz not null default now(),
  modifie_le  timestamptz not null default now(),
  supprime_le timestamptz
);
create index if not exists territoire_equipe on territoire(equipe_id);

create table if not exists fiche (
  id          uuid primary key default gen_random_uuid(),
  equipe_id   uuid not null references equipe(id) on delete cascade,
  territoire_id uuid references territoire(id) on delete set null,
  battue_id   uuid,
  nature      text not null default 'o' check (nature in ('o','p','i')),
  espece      text not null,                        -- code : SAN, CHE, CLV...
  comp        jsonb not null default '{}'::jsonb,   -- {"lsu":1,"mar":5}
  effectif    int  not null default 0,
  lat         double precision not null,
  lng         double precision not null,
  precision_m double precision,
  source      text default 'gps',
  observe_le  timestamptz not null,
  poids_kg    numeric,
  note        text,
  lune        text,
  lune_pct    int,
  soleil_lever  text,
  soleil_coucher text,
  meteo       jsonb,
  auteur      uuid not null default auth.uid(),
  auteur_nom  text,                                  -- figé, survit au départ
  cree_le     timestamptz not null default now(),
  modifie_le  timestamptz not null default now(),
  supprime_le timestamptz
);
create index if not exists fiche_equipe on fiche(equipe_id, observe_le desc);
create index if not exists fiche_maj    on fiche(equipe_id, modifie_le desc);

create table if not exists battue (
  id          uuid primary key default gen_random_uuid(),
  equipe_id   uuid not null references equipe(id) on delete cascade,
  territoire_id uuid references territoire(id) on delete cascade,
  nom         text not null,
  date        date not null,
  responsable text,
  elements    jsonb not null default '[]'::jsonb,    -- postes, traques, lignes
  auteur      uuid not null default auth.uid(),
  cree_le     timestamptz not null default now(),
  modifie_le  timestamptz not null default now(),
  supprime_le timestamptz
);
create index if not exists battue_equipe on battue(equipe_id, date desc);

-- ---------------------------------------------------------------------
-- 3. PRESENCE ET MESSAGES
-- ---------------------------------------------------------------------
--  Une ligne par membre, écrasée à chaque pointage : on ne conserve
--  pas d'historique de déplacement.

create table if not exists presence (
  equipe_id   uuid not null references equipe(id) on delete cascade,
  user_id     uuid not null default auth.uid(),
  nom         text not null,
  lat         double precision not null,
  lng         double precision not null,
  precision_m double precision,
  battue_id   uuid,
  repere      text,                                   -- « poste 4 », « parcelle 43 »
  maj_le      timestamptz not null default now(),
  primary key (equipe_id, user_id)
);

create table if not exists message (
  id          uuid primary key default gen_random_uuid(),
  equipe_id   uuid not null references equipe(id) on delete cascade,
  battue_id   uuid,
  auteur      uuid not null default auth.uid(),
  auteur_nom  text not null,
  texte       text not null check (length(texte) between 1 and 500),
  lat         double precision,
  lng         double precision,
  envoye_le   timestamptz not null default now()
);
create index if not exists message_equipe on message(equipe_id, envoye_le desc);

-- ---------------------------------------------------------------------
-- 4. HORODATAGE SERVEUR
-- ---------------------------------------------------------------------
--  L'heure vient du serveur : une horloge de téléphone déréglée ne peut
--  pas faire gagner une écriture plus ancienne.

create or replace function poser_modifie_le()
returns trigger language plpgsql as $$
begin
  new.modifie_le := now();
  return new;
end $$;

drop trigger if exists trg_maj_territoire on territoire;
create trigger trg_maj_territoire before update on territoire
  for each row execute function poser_modifie_le();

drop trigger if exists trg_maj_fiche on fiche;
create trigger trg_maj_fiche before update on fiche
  for each row execute function poser_modifie_le();

drop trigger if exists trg_maj_battue on battue;
create trigger trg_maj_battue before update on battue
  for each row execute function poser_modifie_le();

-- ---------------------------------------------------------------------
-- 5. RÈGLES D'ACCÈS
-- ---------------------------------------------------------------------
--  Tout est fermé par défaut. Chaque table n'est ouverte qu'aux membres
--  de l'équipe concernée.

alter table equipe     enable row level security;
alter table membre     enable row level security;
alter table territoire enable row level security;
alter table fiche      enable row level security;
alter table battue     enable row level security;
alter table presence   enable row level security;
alter table message    enable row level security;

-- On ne lit que les équipes dont on est membre : le code d'accès des
-- autres équipes reste inaccessible.
drop policy if exists equipe_lecture on equipe;
create policy equipe_lecture on equipe for select
  using (id in (select mes_equipes()));

drop policy if exists membre_lecture on membre;
create policy membre_lecture on membre for select
  using (equipe_id in (select mes_equipes()));

drop policy if exists membre_depart on membre;
create policy membre_depart on membre for delete
  using (user_id = auth.uid());

-- Territoires, fiches et battues : lecture et écriture pour l'équipe.
drop policy if exists territoire_tout on territoire;
create policy territoire_tout on territoire for all
  using (equipe_id in (select mes_equipes()))
  with check (equipe_id in (select mes_equipes()));

drop policy if exists fiche_tout on fiche;
create policy fiche_tout on fiche for all
  using (equipe_id in (select mes_equipes()))
  with check (equipe_id in (select mes_equipes()));

drop policy if exists battue_tout on battue;
create policy battue_tout on battue for all
  using (equipe_id in (select mes_equipes()))
  with check (equipe_id in (select mes_equipes()));

-- Position : chacun ne publie que la sienne, tous les membres la voient.
drop policy if exists presence_lecture on presence;
create policy presence_lecture on presence for select
  using (equipe_id in (select mes_equipes()));

drop policy if exists presence_ecriture on presence;
create policy presence_ecriture on presence for all
  using (user_id = auth.uid() and equipe_id in (select mes_equipes()))
  with check (user_id = auth.uid() and equipe_id in (select mes_equipes()));

-- Messages : lecture par l'équipe, écriture en son propre nom, pas de
-- modification après coup.
drop policy if exists message_lecture on message;
create policy message_lecture on message for select
  using (equipe_id in (select mes_equipes()));

drop policy if exists message_envoi on message;
create policy message_envoi on message for insert
  with check (auteur = auth.uid() and equipe_id in (select mes_equipes()));

-- ---------------------------------------------------------------------
-- 6. CRÉER OU REJOINDRE UNE ÉQUIPE
-- ---------------------------------------------------------------------
--  En SECURITY DEFINER : rejoindre suppose de connaître le code, sans
--  jamais pouvoir lire la table des équipes ni deviner les autres codes.

create or replace function creer_equipe(p_nom text, p_pseudo text)
returns table(equipe_id uuid, code text)
language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_code text;
begin
  if auth.uid() is null then raise exception 'connexion requise'; end if;
  -- code lisible : 8 caracteres, sans O/0/I/1 pour eviter les confusions
  loop
    v_code := (select string_agg(substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789',
                 (floor(random()*32)+1)::int, 1), '')
               from generate_series(1,8));
    exit when not exists (select 1 from equipe e where e.code = v_code);
  end loop;
  insert into equipe(nom, code) values (p_nom, v_code) returning id into v_id;
  insert into membre(equipe_id, user_id, nom, role)
    values (v_id, auth.uid(), p_pseudo, 'chef');
  return query select v_id, v_code;
end $$;

create or replace function rejoindre_equipe(p_code text, p_pseudo text)
returns table(equipe_id uuid, equipe_nom text)
language plpgsql security definer set search_path = public as $$
declare v record;
begin
  if auth.uid() is null then raise exception 'connexion requise'; end if;
  select id, nom into v from equipe where code = upper(trim(p_code));
  if not found then raise exception 'code inconnu'; end if;
  insert into membre(equipe_id, user_id, nom)
    values (v.id, auth.uid(), p_pseudo)
    on conflict (equipe_id, user_id) do update set nom = excluded.nom;
  return query select v.id, v.nom;
end $$;

-- Le code d'accès, réservé aux membres, pour le communiquer aux autres.
create or replace function code_equipe(p_equipe uuid)
returns text language sql stable security definer set search_path = public as $$
  select e.code from equipe e
  where e.id = p_equipe and e.id in (select mes_equipes());
$$;

revoke all on function creer_equipe(text,text) from public;
revoke all on function rejoindre_equipe(text,text) from public;
grant execute on function creer_equipe(text,text)    to authenticated;
grant execute on function rejoindre_equipe(text,text) to authenticated;
grant execute on function code_equipe(uuid)           to authenticated;
grant execute on function mes_equipes()               to authenticated;

-- ---------------------------------------------------------------------
-- 7. TEMPS RÉEL
-- ---------------------------------------------------------------------
alter publication supabase_realtime add table fiche;
alter publication supabase_realtime add table territoire;
alter publication supabase_realtime add table battue;
alter publication supabase_realtime add table presence;
alter publication supabase_realtime add table message;

-- ---------------------------------------------------------------------
--  Vérification rapide, une fois exécuté :
--    select creer_equipe('Les Ajoncs', 'Gonzague');
--  renvoie l'identifiant de l'équipe et le code à transmettre.
-- ---------------------------------------------------------------------
