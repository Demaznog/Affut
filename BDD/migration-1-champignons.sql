-- =====================================================================
--  Affût — module champignons
--
--  Un coin à champignons n'est pas une observation ponctuelle : le
--  mycélium est pérenne, et c'est la répétition sur plusieurs saisons
--  qui fait la valeur du relevé. D'où la colonne passages, qui garde
--  la trace de chaque visite plutôt qu'une seule date.
--
--  Aucune colonne ne porte d'avis de comestibilité, et aucune n'en
--  portera : l'application ne décide pas de ce qui se mange.
-- =====================================================================

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

-- --------------------------------------------------------------------
-- 4. Vérification
-- --------------------------------------------------------------------
notify pgrst, 'reload schema';

select
  (select count(*) from information_schema.columns
     where table_name='fiche'
       and column_name in ('subst','hote','abond','stade','arbre_id','passages')
  ) as colonnes_ajoutees,
  (select pg_get_constraintdef(oid) from pg_constraint
     where conname='fiche_nature_check'
  ) as contrainte_nature;
