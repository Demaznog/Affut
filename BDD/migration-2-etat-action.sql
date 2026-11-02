-- =====================================================================
--  Affût — état sanitaire et intervention sur les arbres
--
--  Ces deux colonnes existent déjà dans la base de production : elles
--  y ont été ajoutées en cours de route, sans qu'un fichier soit
--  conservé. L'application les envoie depuis, alors qu'aucune
--  migration ne les déclarait.
--
--  Le défaut ne se voyait pas tant que la base restait en place. Il se
--  serait vu le jour d'une reconstruction depuis les fichiers : les
--  deux colonnes auraient manqué, et la synchronisation aurait échoué
--  sans rien dire. Ce fichier referme ce trou.
--
--  Sans effet si les colonnes sont déjà là.
-- =====================================================================

alter table fiche add column if not exists etat   text;  -- sain, deperit, dangereux, mort
alter table fiche add column if not exists action text;  -- abattre, elaguer, surveil, conserver, abattu

notify pgrst, 'reload schema';

select count(*) as colonnes_presentes
from information_schema.columns
where table_name='fiche' and column_name in ('etat','action');
