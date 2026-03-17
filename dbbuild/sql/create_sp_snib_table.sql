DROP TABLE IF EXISTS sp_snib;

CREATE TABLE sp_snib AS SELECT distinct reinovalido,phylumdivisionvalido,clasevalida,ordenvalido,familiavalida,generovalido,especievalidabusqueda FROM snib;

ALTER TABLE sp_snib ADD COLUMN spid serial;
ALTER TABLE sp_snib ADD COLUMN validadoterceros smallint;
ALTER TABLE sp_snib ADD COLUMN especieepiteto varchar(100);
ALTER TABLE sp_snib ADD COLUMN subgenero varchar(100);
ALTER TABLE sp_snib ADD COLUMN nombreinfra varchar(100);
ALTER TABLE sp_snib ADD COLUMN idcat varchar(100);
ALTER TABLE sp_snib ADD COLUMN idbacktax integer;
ALTER TABLE sp_snib ADD COLUMN idnombrecatvalido varchar(100);

UPDATE sp_snib SET validadoterceros = 1;
UPDATE sp_snib SET especieepiteto = CASE WHEN left(split_part(especievalidabusqueda, ' ', 2), 1) = '(' THEN split_part(especievalidabusqueda, ' ', 3) ELSE split_part(especievalidabusqueda, ' ', 2) END, subgenero = CASE WHEN left(split_part(especievalidabusqueda, ' ', 2), 1) = '(' THEN rtrim(ltrim(split_part(especievalidabusqueda, ' ', 2), '('), ')') ELSE '' END, nombreinfra = CASE WHEN split_part(especievalidabusqueda, ' ', 3) <> '' AND left(split_part(especievalidabusqueda, ' ', 2), 1) <> '(' THEN split_part(especievalidabusqueda, ' ', 3) WHEN split_part(especievalidabusqueda, ' ', 4) <> '' AND left(split_part(especievalidabusqueda, ' ', 2), 1) = '(' THEN split_part(especievalidabusqueda, ' ', 4) ELSE '' END;

CREATE INDEX idx_sp_snib_spid ON sp_snib(spid);
CREATE INDEX idx_sp_snib_especieepiteto ON sp_snib(especieepiteto);
CREATE INDEX idx_sp_snib_subgenero ON sp_snib(subgenero);
CREATE INDEX idx_sp_snib_nombreinfra ON sp_snib(nombreinfra);
CREATE INDEX idx_sp_snib_idcat ON sp_snib(idcat);
CREATE INDEX idx_sp_snib_idbacktax ON sp_snib(idbacktax);
CREATE INDEX idx_sp_snib_idnombrecatvalido ON sp_snib(idnombrecatvalido);

UPDATE snib t0 SET spid = t1.spid FROM sp_snib AS t1 WHERE t0.reinovalido = t1.reinovalido AND t0.phylumdivisionvalido = t1.phylumdivisionvalido AND t0.clasevalida = t1.clasevalida AND t0.ordenvalido = t1.ordenvalido AND t0.familiavalida = t1.familiavalida AND t0.generovalido = t1.generovalido AND t0.especievalidabusqueda = t1.especievalidabusqueda AND t0.spid IS NULL;
UPDATE sp_snib SET idcat = CASE WHEN not ss.idnombrecatvalido IS NULL AND ss.idnombrecatvalido <> '' THEN ss.idnombrecatvalido WHEN not ss.idnombrecat IS NULL AND ss.idnombrecat <> '' THEN ss.idnombrecat ELSE '' END FROM ( SELECT DISTINCT spid, idnombrecat, idnombrecatvalido FROM snib WHERE (idnombrecatvalido is not null and idnombrecatvalido <> '') or (idnombrecat is not null and idnombrecat <> '') ) AS ss WHERE sp_snib.spid = ss.spid; 