DROP TABLE IF EXISTS snib;

CREATE TABLE snib AS 
SELECT familiavalida, generovalido, especievalida as especievalidabusqueda, longitud, latitud, estadomapa, municipiomapa, localidad, fechacolecta, anp, formadecrecimiento, fuente, urlejemplar, idejemplar, ultimafechaactualizacion, idnombrecatvalido, idnombrecat, reino, phylumdivision, clase, orden, familia, genero, especie, autor, estatustax, reftax, taxonvalidado, reinovalido, phylumdivisionvalido, clasevalida, ordenvalido, autorvalido, nombrecomun, ambiente, region, datum, geovalidacion, paismapa, claveestadomapa, clavemunicipiomapa, "incertidumbreXY", altitudmapa, coleccion, institucion, paiscoleccion, numcatalogo, numcolecta, procedenciaejemplar, colector, diacolecta, mescolecta, aniocolecta, tipo, ejemplarfosil, proyecto, formadecitar, licenciauso, urlproyecto, urlorigen, obsusoinfo, "version", idestadomapa, idmunicipiomapa, comentarioscat, comentarioscatvalido, homonimosgenero, homonimosespecie, homonimosinfraespecie, homonimosgenerocatvalido, homonimosespeciecatvalido, homonimosinfraespeciecatvalido, categoriataxonomica, categoriainfraespecievalida
FROM informaciongeoportal;

UPDATE snib SET reinovalido = CASE WHEN reinovalido IS NULL THEN '' ELSE reinovalido END,phylumdivisionvalido = CASE WHEN phylumdivisionvalido IS NULL THEN '' ELSE phylumdivisionvalido END, clasevalida = CASE WHEN clasevalida IS NULL THEN '' ELSE clasevalida END, ordenvalido = CASE WHEN ordenvalido IS NULL THEN '' ELSE ordenvalido END, familiavalida = CASE WHEN familiavalida IS NULL THEN '' ELSE familiavalida END, generovalido = CASE WHEN generovalido IS NULL THEN '' ELSE generovalido END, especievalidabusqueda = CASE WHEN especievalidabusqueda IS NULL THEN '' ELSE especievalidabusqueda END,categoriainfraespecievalida = CASE WHEN categoriainfraespecievalida IS NULL THEN '' ELSE categoriainfraespecievalida END,proyecto = CASE WHEN proyecto IS NULL THEN '' ELSE proyecto END,fechacolecta = CASE WHEN fechacolecta IS NULL THEN '' ELSE fechacolecta END;

ALTER TABLE snib ADD COLUMN the_geom geometry(POINT,4326);
UPDATE snib SET the_geom=ST_SetSRID(ST_MakePoint(longitud,latitud),4326);

CREATE INDEX idx_snib_geom ON snib USING GIST(the_geom);
CREATE INDEX idx_snib_clasevalida ON snib(clasevalida);
CREATE INDEX idx_snib_ordenvalido ON snib(ordenvalido);
CREATE INDEX idx_snib_familiavalida ON snib(familiavalida);
CREATE INDEX idx_snib_generovalido ON snib(generovalido);
CREATE INDEX idx_snib_especievalidabusqueda ON snib(especievalidabusqueda);
-- CREATE INDEX idx_snib_especievalida ON snib(especievalida);
CREATE INDEX idx_snib_categoriainfraespecievalida ON snib(categoriainfraespecievalida);
CREATE INDEX idx_snib_latitud ON snib(latitud);
CREATE INDEX idx_snib_longitud ON snib(longitud);
CREATE INDEX idx_snib_fechacolecta ON snib(fechacolecta);
CREATE INDEX idx_snib_phylumdivisionvalido ON snib(phylumdivisionvalido);
CREATE INDEX idx_snib_idnombrecatvalido ON snib(idnombrecatvalido);
CREATE INDEX idx_snib_idnombrecat ON snib(idnombrecat);
CREATE INDEX idx_snib_ejemplarfosil ON snib(ejemplarfosil);
CREATE INDEX idx_snib_aniocolecta ON snib(aniocolecta); 

ALTER TABLE snib ADD COLUMN spid integer;

CREATE INDEX idx_snib_spid ON snib(spid);
CREATE INDEX idx_snib_idejemplar ON snib USING GIST(idejemplar);

ALTER TABLE snib ADD COLUMN gid integer;

CREATE INDEX idx_snib_gid ON snib(gid);

-- se agrega columna de fuente datos
-- ALTER TABLE snib ADD COLUMN fuente_datos varchar(5);
-- CREATE INDEX idx_snib_fuentedatos ON snib(gid);
-- UPDATE snib SET fuente_datos = 'snib';


