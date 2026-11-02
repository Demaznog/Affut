-- =====================================================================
--  Affût — parcelles plantées et relevés d'état
--
--  Une peupleraie n'est pas un bois : c'est une culture plantée en
--  grille régulière. Les arbres n'ont donc pas besoin d'être pointés
--  un par un au GPS — la grille les situe mieux que le téléphone ne
--  saurait le faire, et à 7 m d'écartement la précision du GPS mettrait
--  les arbres dans la mauvaise ligne.
--
--  D'où ces deux tables :
--    parcelle  la grille : origine, orientation, écartements, nombre
--              de lignes et d'arbres. Quelques octets, pas 400 fiches.
--    releve    un passage dans la parcelle : une chaîne d'un caractère
--              par emplacement. 400 arbres tiennent dans 400 octets,
--              et l'historique année par année ne coûte rien.
--
--  Les arbres ne sont donc PAS des lignes de la table fiche. Une
--  peupleraie de 2 ha en aurait créé 400, chacune avec sa météo, ses
--  photos et ses équipes : lourd à synchroniser et sans usage.
-- =====================================================================

-- --------------------------------------------------------------------
-- 1. La parcelle
-- --------------------------------------------------------------------
create table if not exists parcelle (
  id          uuid primary key,
  equipe_id   uuid not null,
  equipes     uuid[] not null default '{}',

  nom         text not null,
  essence     text,            -- code du référentiel, ex. APEUP
  cultivar    text,            -- libellé court, ex. « Koster · AF 8 »
  -- Une peupleraie porte souvent deux clones, et c'est voulu : le CNPF
  -- impose la diversification au-delà de trois hectares. Les garder
  -- séparés, avec leurs lignes, permet de comparer leur mortalité —
  -- deux clones sur le même sol qui ne tiennent pas pareil désignent
  -- le clone, pas le terrain.
  cultivars   jsonb,           -- [{nom, de, a}] — de/a = numéros de ligne
  plante_le   date,            -- année de plantation
  surface_ha  numeric,         -- saisie ou calculée depuis la grille

  -- Géométrie de la grille.
  -- L'origine est l'arbre (ligne 1, rang 1). Le cap est l'orientation
  -- des lignes en degrés depuis le nord géographique. Les lignes se
  -- déduisent par rotation de 90° de ce cap.
  ori_lat     double precision,
  ori_lng     double precision,
  cap         numeric,         -- degrés, 0 = nord, 90 = est
  ecart_ligne numeric,         -- entre deux lignes, m
  ecart_arbre numeric,         -- entre deux arbres d'une même ligne, m
  nb_lignes   integer,
  nb_arbres   integer,         -- par ligne

  travaux     jsonb,           -- [{d, t, haut, lignes, note}, …]
  note        text,

  auteur      uuid not null default auth.uid(),
  auteur_nom  text,
  cree_le     timestamptz not null default now(),
  modifie_le  timestamptz not null default now(),
  supprime_le timestamptz
);
create index if not exists parcelle_equipes on parcelle using gin(equipes);

-- --------------------------------------------------------------------
-- 2. Le relevé
--
--  etats : un caractère par emplacement, lu ligne par ligne depuis
--  l'origine, dans l'ordre logique (et non dans l'ordre de marche).
--      v  vivant
--      d  dépérissant
--      m  mort sur pied
--      a  absent — emplacement vide, rien à abattre avant de replanter
--      ?  non relevé
-- --------------------------------------------------------------------
create table if not exists releve (
  id          uuid primary key,
  parcelle_id uuid not null,
  equipe_id   uuid not null,
  equipes     uuid[] not null default '{}',

  fait_le     date not null,
  etats       text not null,
  note        text,

  auteur      uuid not null default auth.uid(),
  auteur_nom  text,
  cree_le     timestamptz not null default now(),
  modifie_le  timestamptz not null default now(),
  supprime_le timestamptz
);
create index if not exists releve_equipes  on releve using gin(equipes);
create index if not exists releve_parcelle on releve (parcelle_id);

-- --------------------------------------------------------------------
-- 3. Horodatage automatique, comme sur les autres tables
-- --------------------------------------------------------------------
drop trigger if exists trg_maj_parcelle on parcelle;
create trigger trg_maj_parcelle before update on parcelle
  for each row execute function poser_modifie_le();

drop trigger if exists trg_maj_releve on releve;
create trigger trg_maj_releve before update on releve
  for each row execute function poser_modifie_le();

-- --------------------------------------------------------------------
-- 4. Droits — mêmes règles que le reste : on voit ce que son équipe
--    partage, on écrit si l'on n'est pas simple lecteur.
-- --------------------------------------------------------------------
alter table parcelle enable row level security;
alter table releve   enable row level security;

drop policy if exists parcelle_lire on parcelle;
create policy parcelle_lire on parcelle for select
  using (equipes && mes_equipes_arr());

drop policy if exists parcelle_ecrire on parcelle;
create policy parcelle_ecrire on parcelle for all
  using (equipes && mes_equipes_ecriture())
  with check (equipes && mes_equipes_ecriture());

drop policy if exists releve_lire on releve;
create policy releve_lire on releve for select
  using (equipes && mes_equipes_arr());

drop policy if exists releve_ecrire on releve;
create policy releve_ecrire on releve for all
  using (equipes && mes_equipes_ecriture())
  with check (equipes && mes_equipes_ecriture());

grant select, insert, update, delete on parcelle to authenticated;
grant select, insert, update, delete on releve   to authenticated;
grant select on parcelle to anon;
grant select on releve   to anon;

-- --------------------------------------------------------------------
-- 5. Temps réel
-- --------------------------------------------------------------------
do $$
begin
  begin alter publication supabase_realtime add table parcelle; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table releve;   exception when duplicate_object then null; end;
end $$;

notify pgrst, 'reload schema';

-- --------------------------------------------------------------------
-- 6. Vérification
-- --------------------------------------------------------------------
select
  (select count(*) from information_schema.tables
     where table_name in ('parcelle','releve')) as tables_creees,
  (select count(*) from pg_policies
     where tablename in ('parcelle','releve')) as politiques;
