-- =====================================================================
--  AFFÛT — migration du 2 novembre 2026
--
--  Un seul fichier, à coller en entier dans Supabase → SQL Editor,
--  puis Run. Il réunit les trois migrations en attente :
--
--    1. champignons      nature 'c' et colonnes du relevé mycologique
--    2. état / action    deux colonnes d'arbre jamais déclarées
--    3. parcelles        tables parcelle et releve
--
--  Rejouable sans risque : tout est en « if not exists » ou précédé
--  d'un « drop if exists ». Le relancer une seconde fois ne fait rien.
--
--  Prérequis déjà en place : poser_modifie_le(), mes_equipes_arr(),
--  mes_equipes_ecriture().
-- =====================================================================


-- #####################################################################
-- #  1 sur 3 — CHAMPIGNONS
-- #####################################################################

-- --------------------------------------------------------------------
-- 1. La nature de fiche accepte un cinquième règne
--    o = observation · p = prélèvement · i = indice
--    a = arbre       · c = champignon
-- --------------------------------------------------------------------
alter table fiche drop constraint if exists fiche_nature_check;
alter table fiche add  constraint fiche_nature_check
  check (nature = any (array['o'::text,'p'::text,'i'::text,'a'::text,'c'::text]));

-- --------------------------------------------------------------------
-- 2. Colonnes propres au champignon
-- --------------------------------------------------------------------
alter table fiche add column if not exists subst    text;   -- sol, souche, tronc, litière, mousse, fumier, brûlis
alter table fiche add column if not exists hote     text;   -- essence hôte observée sur place (texte libre)
alter table fiche add column if not exists abond    text;   -- rien, quelques, poignee, panier, abondant
alter table fiche add column if not exists stade    text;   -- primordium, jeune, mature, passe
alter table fiche add column if not exists arbre_id uuid;   -- fiche arbre liée (truffière, mycorhize)
alter table fiche add column if not exists passages jsonb;  -- [{d:'2026-10-21', ab:'panier', st:'mature'}, ...]

-- --------------------------------------------------------------------
-- 3. Contrôle de cohérence
--    Le lien vers un arbre ne doit pointer que sur une fiche existante
--    de la même équipe. On ne pose pas de clé étrangère dure : une
--    fiche arbre peut être supprimée alors que le coin reste valable.
--    Le nettoyage est donc fait côté application, pas par la base.
-- --------------------------------------------------------------------
create index if not exists fiche_arbre_id_idx on fiche (arbre_id) where arbre_id is not null;
create index if not exists fiche_nature_idx    on fiche (nature);

-- #####################################################################
-- #  2 sur 3 — ÉTAT SANITAIRE ET INTERVENTION
-- #####################################################################

alter table fiche add column if not exists etat   text;  -- sain, deperit, dangereux, mort
alter table fiche add column if not exists action text;  -- abattre, elaguer, surveil, conserver, abattu

-- #####################################################################
-- #  3 sur 3 — PARCELLES PLANTÉES
-- #####################################################################

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

-- =====================================================================
--  VÉRIFICATION
--  Les quatre colonnes doivent afficher les valeurs attendues.
-- =====================================================================

notify pgrst, 'reload schema';

select
  (select count(*) from information_schema.columns
     where table_name='fiche'
       and column_name in ('subst','hote','abond','stade','arbre_id','passages',
                           'etat','action')
  )                                                      as colonnes_fiche_sur_8,
  (select count(*) from information_schema.tables
     where table_name in ('parcelle','releve'))          as tables_creees_sur_2,
  (select count(*) from pg_policies
     where tablename in ('parcelle','releve'))           as politiques_sur_4,
  (select pg_get_constraintdef(oid) from pg_constraint
     where conname='fiche_nature_check')                 as natures_acceptees;
