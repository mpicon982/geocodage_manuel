create schema if not exists ban;
--accord des droits
grant usage on schema ban to r_scalen_consult;
alter default privileges for role r_scalen_admin grant select on tables to r_scalen_consult;

create table ban.ban54_2026 (
                                id	text,
                                id_fantoir	text,
                                numero	text,
                                rep	text,
                                nom_voie	text,
                                code_postal	text,
                                code_insee	text,
                                nom_commune	text,
                                code_insee_ancienne_commune	text,
                                nom_ancienne_commune	text,
                                x	text,
                                y	text,
                                lon	text,
                                lat	text,
                                type_position	text,
                                alias	text,
                                nom_ld	text,
                                libelle_acheminement	text,
                                nom_afnor	text,
                                source_position	text,
                                source_nom_voie	text,
                                certification_commune	text,
                                cad_parcelles	text

);
--import
/*
 psql -c "\copy ban.ban54_2026 from 'C:\Users\m.picon\Desktop\imports\adresses-54.csv' WITH (HEADER, FORMAT CSV, DELIMITER ';', ENCODING UTF8, NULL '')"

 */

--insert into sauvegardes.aduan values ('ban','annuelle');

create extension if not exists pg_trgm;

drop view if exists social_secure.v_pros_sante_nations;
create view social_secure.v_pros_sante_nations as
(
with pros as (select
                  --distinct on (ps_activite_nom,ps_activite_prenom,adresse_pros)

--regexp pour récup le numéro de voie
                  regexp_substr(coordonnees_voie, '^\d+')::text                                                numero,
                  --regexp pour choper le bis ter quater -->  pattern match, départ au caractère 1, premier caractère qui matche,
                  --isnensible à la casse  'i', résultat dans  le premier groupe entre()
  -- source checkée, que des BIS en majuscules ici d'où ùon simple \d+[a-z]
                  case when regexp_substr(coordonnees_voie, '^\d+([a-z])*', 1, 1, 'i', 1) = 'B' then 'bis' end rep,
                  regexp_replace(regexp_replace(replace(replace(unaccent(lower(coordonnees_voie) || ' ' ||
                                                                         coordonnees_code_postal || ' ' ||
                                                                         lower(coordonnees_ville)), '  ', ' '), '-',
                                                        ' '), '^\d+\s|(\d+(b\s|t\s))', ''), '\sbp\s\d+',
                                 '')                                                                           adresse_pros,

                  *

              from sante.annuaire_cnam_ps_20260405
              where coordonnees_code_postal = '54500')
        ,
     ban as (select numero::text,
                    rep,
                    replace(replace(unaccent(lower(nom_voie) || ' ' || code_postal || ' ' || lower(nom_commune)), '  ',
                                    ' '), '-', ' ')::text adresse_geocodage,
                    x,
                    y

             from ban.ban54_2026
             where code_postal = '54500')
        ,
     premier_tri as (select p.ps_activite_prenom,
                            p.ps_activite_nom,
                            p.specialite_libelle,
                            p.numero,
                            p.adresse_pros,
                            b.numero                                                       numero_ban,
                            b.adresse_geocodage                                            adresse_ban,
                            b.rep                                                          rep_ban,
                            p.rep                                                          rep_pros,
                            b.x,
                            b.y,
                            case when p.numero is null then 'centre de voie' else 'ok' end test_centre_voie

                     from pros p
                              left join ban b
                                        on similarity(b.adresse_geocodage, p.adresse_pros) >= 0.7 and
                                           b.numero = p.numero
                                            --match des bis ter etc. -- similar to pour gérer les null 
                                            and (b.rep is not distinct from p.rep or
                                                 left(p.rep, 1) is not distinct from b.rep)

                     group by p.ps_activite_prenom, p.ps_activite_nom, p.specialite_libelle, b.x, b.y, p.numero,
                              p.adresse_pros, b.rep, p.rep, b.numero, b.adresse_geocodage),
     ban_milieux as (select nom_voie,
                            numero,
                            code_postal,
                            nom_commune,
                            x,
                            y,
                            case
                                when row_number() over w = --numérotation
                                     round(count(*) over w::numeric / 2.0) --total de numéros de rue
                                    then 'centre'
                                else 'non centre' end centre
                     from ban.ban54_2026 b
                     where code_postal = '54500'
                     --comptage du nombre de numéros de rues par voie dans le fenêtrage
                     window w as (partition by nom_voie order by numero::int)
                     ),

     second_tri as (select pt.adresse_pros,
                           pt.ps_activite_nom,
                           pt.ps_activite_prenom,
                           pt.specialite_libelle,
                           pt.x,
                           pt.y
                    from premier_tri pt
                    where test_centre_voie = 'ok'
                    union all

                    select pt.adresse_pros,
                           pt.ps_activite_nom,
                           pt.ps_activite_prenom,
                           pt.specialite_libelle,
                           bm.x,
                           bm.y
                    from premier_tri pt
                             left join ban_milieux bm on similarity(replace(replace(
                                                                                    unaccent(lower(nom_voie) || ' ' || code_postal || ' ' || lower(nom_commune)),
                                                                                    '  ', ' '), '-', ' '),
                                                                    pt.adresse_pros) >= 0.7 and bm.centre = 'centre'
                    where test_centre_voie != 'ok'),
     erreurs_geocodage as (select * from second_tri where x is null),

     table_geocodee_vand as (select distinct on (
         st.adresse_pros,ps_activite_nom,
         ps_activite_prenom) specialite_libelle,
                             x::double precision,
                             y::double precision
                             from second_tri st
                             where x is not null
                             group by st.ps_activite_nom, ps_activite_prenom, specialite_libelle, x, y, adresse_pros

                             union all

                             select specialite_libelle,
                                    case
                                        when adresse_pros ilike '%nat%'
                                            then st_x(st_transform(st_point(6.175210, 48.662230, 4326), 2154))
                                        when adresse_pros ilike '%montet%'
                                            then st_x(st_transform(st_point(6.168460, 48.667650, 4326), 2154))
                                        when adresse_pros ilike '%chu%' then st_x(st_transform(
                                                st_point(6.14653147928965, 48.64759307247181, 4326), 2154))
                                        else null
                                        end x,
                                    case
                                        when adresse_pros ilike '%nat%'
                                            then st_y(st_transform(st_point(6.175210, 48.662230, 4326), 2154))
                                        when adresse_pros ilike '%montet%'
                                            then st_y(st_transform(st_point(6.168460, 48.667650, 4326), 2154))
                                        when adresse_pros ilike '%chu%' then st_y(st_transform(
                                                st_point(6.14653147928965, 48.64759307247181, 4326), 2154))
                                        else null
                                        end y

                             from erreurs_geocodage)
        ,
     table_doubles_geom as (
--jointure avec qpv

         select tgv.*,
                row_number() over (partition by x, y) i,
                count(*) over (partition by x, y) n

         from qpv.limites_qpv qpv
                  join table_geocodee_vand tgv on st_intersects(st_point(tgv.x, tgv.y, 2154), qpv.geom)
         where code_qp = 'QN05416M'),
--max 28 points au même endroit --> 2pi/27 (n-1 car le premier point est fixe)
--rotation tous les 2pi/(n-1) rad + translation de 4m des doublons
     dedoublonnage_geom as (select tdg.specialite_libelle,
                                   case when i > 1 then x + 4.0 * cos(2.0 * pi() * i / (n-1)::numeric) else x end x,
                                   case when i > 1 then y + 4.0 * sin(2.0 * pi() * i / (n-1)::numeric) else y end y,
                                   i,
                                   n


                            from table_doubles_geom tdg)

select row_number() over () id,
       dg.specialite_libelle,
       st_point(x, y, 2154) geom


from dedoublonnage_geom dg);



--48.662230, 6.175210 nat
--48.667650, 6.168460 montet
--48.64759307247181, 6.14653147928965 chu
