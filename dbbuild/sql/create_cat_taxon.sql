DROP TABLE IF EXISTS cat_taxon;

CREATE TABLE cat_taxon (
	id serial4 NOT NULL,
	taxon varchar(20) NULL,
	description varchar(250) NULL,
	column_taxon_name varchar(100) NULL,
	available_grids _int4 NULL,
	filter_fields jsonb NULL
);

INSERT INTO cat_taxon (taxon,description,column_taxon,available_grids,filter_fields) VALUES
	 ('reino','reinos guardados en GBIF','reinovalido','{1,4,5,8,9,12,13,16,17,18,19,20}','{"min_occ": "integer", "in_fosil": "boolean", "in_sin_fecha": "boolean"}'),
	 ('phylum','phylums guardados en GBIF','phylumdivisionvalido','{1,4,5,8,9,12,13,16,17,18,19,20}','{"min_occ": "integer", "in_fosil": "boolean", "in_sin_fecha": "boolean"}'),
	 ('clase','clases guardados en GBIF','clasevalida','{1,4,5,8,9,12,13,16,17,18,19,20}','{"min_occ": "integer", "in_fosil": "boolean", "in_sin_fecha": "boolean"}'),
	 ('orden','ordenes guardados en GBIF','ordenvalido','{1,4,5,8,9,12,13,16,17,18,19,20}','{"min_occ": "integer", "in_fosil": "boolean", "in_sin_fecha": "boolean"}'),
	 ('familia','familias guardados en GBIF','familiavalida','{1,4,5,8,9,12,13,16,17,18,19,20}','{"min_occ": "integer", "in_fosil": "boolean", "in_sin_fecha": "boolean"}'),
	 ('genero','generos guardados en GBIF','generovalido','{1,4,5,8,9,12,13,16,17,18,19,20}','{"min_occ": "integer", "in_fosil": "boolean", "in_sin_fecha": "boolean"}'),
	 ('especie','especies guardados en GBIF','especievalidabusqueda','{1,4,5,8,9,12,13,16,17,18,19,20}','{"min_occ": "integer", "in_fosil": "boolean", "in_sin_fecha": "boolean"}');


alter table cat_taxon add column level_size varchar(10);

-- Probar segmento de codigo
-- update cat_taxon set level_size = subquery_reino.level_size
-- FROM ( select count(*) as level_size from(select distinct reinovalido from sp_snib ss where reinovalido <> '') as b) AS subquery_reino
-- WHERE cat_taxon.taxon = 'reino'

-- update cat_taxon set level_size = subquery_phylum.level_size
-- FROM ( select count(*) as level_size from(select distinct phylumdivisionvalido from sp_snib ss where phylumdivisionvalido <> '') as b) AS subquery_phylum
-- WHERE cat_taxon.taxon = 'phylum'

-- update cat_taxon set level_size = subquery_clase.level_size
-- FROM ( select count(*) as level_size from(select distinct clasevalida from sp_snib ss where clasevalida <> '') as b) AS subquery_clase
-- WHERE cat_taxon.taxon = 'clase'

-- update cat_taxon set level_size = subquery_orden.level_size
-- FROM ( select count(*) as level_size from(select distinct ordenvalido from sp_snib ss where ordenvalido <> '') as b) AS subquery_orden
-- WHERE cat_taxon.taxon = 'orden'

-- update cat_taxon set level_size = subquery_familia.level_size
-- FROM ( select count(*) as level_size from(select distinct familiavalida from sp_snib ss where familiavalida <> '') as b) AS subquery_familia
-- WHERE cat_taxon.taxon = 'familia'

-- update cat_taxon set level_size = subquery_genero.level_size
-- FROM ( select count(*) as level_size from(select distinct generovalido from sp_snib ss where generovalido <> '') as b) AS subquery_genero
-- WHERE cat_taxon.taxon = 'genero'

-- update cat_taxon set level_size = subquery_especie.level_size
-- FROM ( select count(*) as level_size from(select distinct especievalidabusqueda from sp_snib ss where especievalidabusqueda <> '') as b) AS subquery_especie
-- WHERE cat_taxon.taxon = 'especie'



