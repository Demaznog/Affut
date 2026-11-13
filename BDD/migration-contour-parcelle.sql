-- =====================================================================
-- Affût — le contour réel d'une parcelle
--
-- La grille est un rectangle ; une parcelle, presque jamais. Celle de
-- La Serve est un quadrilatère allongé de 2,07 ha dont la grille de
-- 9 × 72 déborde largement : 229 des 648 emplacements tombent hors du
-- terrain. Dessiner ce rectangle sur la vue aérienne montre donc une
-- limite qui n'existe pas.
--
-- Cette colonne garde le contour relevé à la main sur la photo :
-- une liste de sommets [[lat, lng], …], dans l'ordre du tracé.
-- On la stocke en jsonb plutôt qu'en geography : l'application ne
-- fait aucune requête spatiale dessus, elle la dessine. PostGIS
-- coûterait une extension pour rien.
--
-- À rejouer sans risque : tout est conditionnel.
-- =====================================================================

alter table parcelle
  add column if not exists contour jsonb not null default '[]'::jsonb;

comment on column parcelle.contour is
  'Contour réel du terrain, relevé sur la vue aérienne : [[lat,lng], …] '
  'dans l''ordre du tracé. Vide tant qu''il n''a pas été relevé — la '
  'carte dessine alors le rectangle de la grille.';

-- Un contour est soit vide, soit un vrai polygone : trois sommets au
-- moins. Deux points ne ferment rien, et une forme à deux sommets
-- dessinée sur la carte serait un trait présenté comme une parcelle.
do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conname = 'parcelle_contour_polygone'
       and conrelid = 'parcelle'::regclass
  ) then
    alter table parcelle
      add constraint parcelle_contour_polygone
      check (jsonb_typeof(contour) = 'array'
             and (jsonb_array_length(contour) = 0
                  or jsonb_array_length(contour) >= 3));
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Vérification
-- ---------------------------------------------------------------------
select
  count(*)                                        as parcelles,
  count(*) filter (where jsonb_array_length(contour) > 2) as avec_contour,
  count(*) filter (where jsonb_array_length(contour) = 0) as sans_contour
from parcelle
where supprime_le is null;
