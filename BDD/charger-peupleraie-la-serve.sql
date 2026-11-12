-- =====================================================================
--  La peupleraie de La Serve — parcelle et relevé du 12 novembre 2026
--
--  A coller dans l'editeur SQL de Supabase, APRES migration-parcelles.
--  Le script ne cree rien en double : relance-le sans crainte.
--
--  Ce qu'il charge :
--    la grille      10 lignes x 73 emplacements, 7 m x 7 m,
--                   plantee le 12 mars 2026 (Koster et AF 8)
--    le releve      419 emplacements notes a la main sur le terrain :
--                   242 vivants, 170 morts, 7 a receper.
--
--  Deux partis pris, a corriger ensuite dans l'application en touchant
--  le plan :
--
--  1. Les 311 emplacements sans plant sont notes « hors parcelle » et
--     NON « non plantable ». La parcelle n'est pas rectangulaire : la
--     seule ligne 1 compte 62 places vides entre son troisieme et son
--     soixante-sixieme plant. Ce sont les contours du terrain, pas de
--     la roche. Marquer de la roche ou l'on n'en a pas constate serait
--     inventer une cause de mortalite.
--
--  2. Les cultivars ne sont PAS repartis par ligne. La facture porte
--     150 Koster et 274 AF 8, et le releve compte 133 plants sur les
--     lignes 1 a 4 contre 286 sur les lignes 5 a 9 : les deux
--     decoupages se ressemblent, mais rien ne le prouve. Tant que le
--     plan de plantation de l'entreprise n'est pas au dossier, ecrire
--     cette repartition ferait dire a l'application une chose qu'elle
--     ne sait pas.
--
--  La ligne 10 n'a pas ete relevee : elle reste en « non relevé » et
--  sort de tous les pourcentages.
-- =====================================================================

do $$
declare
  -- ============================================================
  --  LE SEUL REGLAGE : dans quelle equipe deposer la peupleraie.
  --  Laisse vide s'il n'y en a qu'une, elle sera trouvee seule.
  --  S'il y en a plusieurs, ecris ici le nom de la bonne, entre
  --  apostrophes. La casse et les accents n'ont pas d'importance,
  --  et un fragment suffit : 'serve' trouve « La Serve ».
  --  Si le nom ne correspond a rien, le script affiche la liste
  --  de tes equipes et ne touche a rien.
  -- ============================================================
  equipe_voulue constant text := 'famille';

  eq   uuid;
  moi  uuid;
  nom_auteur text;   -- pas « nom » : c'est aussi une colonne de parcelle
  nbeq integer;
  liste text;
  pid  uuid := '9c1e7a40-5d2b-4f18-93a7-6e0b1f2c8d44';  -- fixe : pas de doublon
  rid  uuid := '3f8b2c61-07de-4a95-b1c3-5a9e4d7f0b26';
  etats constant text := 'vvvhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhvvmmmmmmmvvcvvvhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhmmmvvmmmmmmmvmmmmmmmmvmmmvcvmmvvvmhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhvvmmmmmmvmvcmmvmmmmvvvvvvvvmmmvmmvhhhhhhhhhhhmcvvhvvvvvvvmmmmmmmmvmmmmmmvmmmvmmmvvvcmvvvvmmmmmvvvvvvvvvvvvvvvmvvvhhhhvvmmmhvmmvmmmmmmmmmmmvvvvvvvvvmmvvvvvvvvvvvvvvvmvvvvvmvvvvvmmmvvvmvmvmvmmmmmmmhmmmvmmmmvvmmmvvvvvvvvmvmvvvvmmmmvvvmmvmvvvmhhhhvmvvmmmmmvvvmmmmvvmmmvmvvhvvvvvvvvvvvvvvvvvvvvmvvvmvvvvvvvvmvvvvvvmvvhhhhhhhhhvvcmvvvvvvvvvvmmvvvmmmvmvvvhhhhhhhhvvvvvvvvvvvvvmvvvvvmvmmcmvmvhhhhhhhhhhhhhmmmvmvvvvvmvmmvmmhhhhhhhhhhhhhhhhhhhhhhhhhhhhhvvvvvvhhhhhhhhh?????????????????????????????????????????????????????????????????????????';
begin
  -- L'equipe : celle de l'utilisateur courant quand on le connait.
  -- Dans l'editeur SQL de Supabase on ne le connait PAS : la requete
  -- n'y tourne pas sous une session authentifiee, et auth.uid() y vaut
  -- NULL. On retombe alors sur l'unique equipe de la base, et on
  -- s'arrete s'il y en a plusieurs plutot que d'en choisir une au
  -- hasard.
  -- De quoi ecrire un message utile en cas de refus.
  select string_agg(quote_literal(nom), ', ' order by nom) into liste from equipe;

  -- 1. Un nom donne en tete du script l'emporte sur tout le reste.
  --    La comparaison ignore casse et accents sans passer par
  --    l'extension unaccent, qui n'est pas toujours activee.
  if coalesce(equipe_voulue,'') <> '' then
    select count(*) into nbeq from equipe
     where translate(lower(nom),
             'àâäãéèêëíìîïóòôöõúùûüçñ','aaaaeeeeiiiiooooouuuucn')
           like '%'||translate(lower(equipe_voulue),
             'àâäãéèêëíìîïóòôöõúùûüçñ','aaaaeeeeiiiiooooouuuucn')||'%';
    if nbeq = 0 then
      raise exception 'Aucune equipe ne correspond a %. Tes equipes : %',
        quote_literal(equipe_voulue), liste;
    elsif nbeq > 1 then
      raise exception '% correspond a % equipes, precise davantage. Tes equipes : %',
        quote_literal(equipe_voulue), nbeq, liste;
    end if;
    select id into eq from equipe
     where translate(lower(nom),
             'àâäãéèêëíìîïóòôöõúùûüçñ','aaaaeeeeiiiiooooouuuucn')
           like '%'||translate(lower(equipe_voulue),
             'àâäãéèêëíìîïóòôöõúùûüçñ','aaaaeeeeiiiiooooouuuucn')||'%';
  end if;

  -- 2. Sinon, l'equipe de l'utilisateur courant quand on le connait.
  if eq is null then
    select e.id into eq
      from equipe e
     where auth.uid() is not null
       and exists (select 1 from membre m
                    where m.equipe_id = e.id and m.user_id = auth.uid())
     order by e.cree_le
     limit 1;
  end if;

  -- 3. Sinon l'unique equipe de la base — et seulement si elle est
  --    unique : choisir au hasard deposerait la peupleraie chez les
  --    mauvaises personnes, qui la verraient toutes.
  if eq is null then
    select count(*) into nbeq from equipe;
    if nbeq = 0 then
      raise exception
        'Aucune equipe : cree ton equipe dans l''application avant de lancer ce script.';
    elsif nbeq > 1 then
      raise exception
        'Cette base contient % equipes et la session SQL n''en designe aucune. '
        'Ecris le nom de la bonne dans equipe_voulue, en tete du script. '
        'Tes equipes : %', nbeq, liste;
    end if;
    select id into eq from equipe limit 1;
  end if;

  -- L'auteur. Les colonnes « auteur » de parcelle et de releve sont
  -- NOT NULL avec auth.uid() pour valeur par defaut : dans l'editeur
  -- SQL ce defaut vaut NULL et l'insertion echoue. On nomme donc
  -- explicitement le createur de l'equipe, qui est un vrai compte.
  select coalesce(auth.uid(), e.cree_par) into moi
    from equipe e where e.id = eq;
  if moi is null then
    raise exception
      'Impossible de determiner l''auteur : l''equipe % n''a pas de createur connu.', eq;
  end if;
  select m.nom into nom_auteur
    from membre m where m.equipe_id = eq and m.user_id = moi;

  if length(etats) <> 730 then
    raise exception 'Le releve devrait compter 730 caracteres, il en a %', length(etats);
  end if;

  insert into parcelle
    (id, equipe_id, equipes, nom, essence, cultivar, cultivars,
     plante_le, surface_ha, ecart_ligne, ecart_arbre, nb_lignes, nb_arbres,
     travaux, note, auteur, auteur_nom)
  values
    (pid, eq, array[eq], 'La peupleraie de La Serve', 'APEU',
     'Koster · AF 8', null,
     date '2026-03-12', 2.05, 7, 7, 10, 73,
     '[]'::jsonb,
     'Plantee le 12 mars 2026, plants conserves au froid pour retarder la montee de seve. '
     'Facture : 150 Koster et 274 AF 8 — repartition par ligne inconnue, a demander a l''entreprise. '
     'Les reperes de la grille (origine, cap) restent a poser sur place. '
     'Ligne 10 non relevee.',
     moi, nom_auteur)
  on conflict (id) do update
     set nom = excluded.nom, essence = excluded.essence,
         cultivar = excluded.cultivar, plante_le = excluded.plante_le,
         surface_ha = excluded.surface_ha,
         ecart_ligne = excluded.ecart_ligne, ecart_arbre = excluded.ecart_arbre,
         nb_lignes = excluded.nb_lignes, nb_arbres = excluded.nb_arbres,
         note = excluded.note, modifie_le = now();

  insert into releve
    (id, parcelle_id, equipe_id, equipes, fait_le, etats, note,
     auteur, auteur_nom)
  values
    (rid, pid, eq, array[eq], date '2026-11-12', etats,
     'Releve a la main sur le terrain, reporte depuis le plan papier. '
     '242 vivants, 170 morts, 7 a receper sur 419 emplacements plantes.',
     moi, nom_auteur)
  on conflict (id) do update
     set etats = excluded.etats, fait_le = excluded.fait_le,
         note = excluded.note, modifie_le = now();
end $$;

notify pgrst, 'reload schema';

-- --------------------------------------------------------------------
--  Verification : les chiffres doivent etre 242 / 170 / 7 / 73.
-- --------------------------------------------------------------------
select
  (select nom from parcelle where id = '9c1e7a40-5d2b-4f18-93a7-6e0b1f2c8d44') as parcelle,
  length(r.etats)                                      as emplacements,
  length(r.etats) - length(replace(r.etats,'v',''))    as vivants,
  length(r.etats) - length(replace(r.etats,'m',''))    as morts,
  length(r.etats) - length(replace(r.etats,'c',''))    as a_receper,
  length(r.etats) - length(replace(r.etats,'h',''))    as hors_parcelle,
  length(r.etats) - length(replace(r.etats,'?',''))    as non_releves
from releve r
where r.id = '3f8b2c61-07de-4a95-b1c3-5a9e4d7f0b26';
