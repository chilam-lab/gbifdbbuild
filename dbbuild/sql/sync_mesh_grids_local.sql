-- Copia local de las tablas finas de celda (una sola vez, o cuando la malla
-- cambie en regiondbbuild), leidas UNA VEZ por el FDW de create_mesh_fdw.sql.
--
-- Por que no se usa mesh_fdw.grid_*_aoi directo en el batch de precalculo:
-- postgres_fdw no empuja ST_Intersects al servidor remoto, asi que el join
-- espacial contra la tabla foranea cae en un Nested Loop sobre la tabla
-- COMPLETA (grid_8km_aoi tiene 1.2M filas). La copia local tiene un indice
-- GiST real. Mismo archivo que speciesdbbuild/dbbuild/sql.

IMPORT FOREIGN SCHEMA public
LIMIT TO (grid_64km_aoi, grid_32km_aoi, grid_16km_aoi, grid_8km_aoi, grid_ageb_aoi, grid_cue_aoi, grid_mun_aoi, grid_state_aoi)
FROM SERVER mesh_server
INTO mesh_fdw;

DROP TABLE IF EXISTS grid_64km_aoi_local;
CREATE TABLE grid_64km_aoi_local AS
  SELECT gridid_64km, the_geom FROM mesh_fdw.grid_64km_aoi;
CREATE INDEX idx_grid_64km_aoi_local_geom ON grid_64km_aoi_local USING GIST(the_geom);
CREATE UNIQUE INDEX idx_grid_64km_aoi_local_gridid ON grid_64km_aoi_local(gridid_64km);
ANALYZE grid_64km_aoi_local;

DROP TABLE IF EXISTS grid_32km_aoi_local;
CREATE TABLE grid_32km_aoi_local AS
  SELECT gridid_32km, the_geom FROM mesh_fdw.grid_32km_aoi;
CREATE INDEX idx_grid_32km_aoi_local_geom ON grid_32km_aoi_local USING GIST(the_geom);
CREATE UNIQUE INDEX idx_grid_32km_aoi_local_gridid ON grid_32km_aoi_local(gridid_32km);
ANALYZE grid_32km_aoi_local;

DROP TABLE IF EXISTS grid_16km_aoi_local;
CREATE TABLE grid_16km_aoi_local AS
  SELECT gridid_16km, the_geom FROM mesh_fdw.grid_16km_aoi;
CREATE INDEX idx_grid_16km_aoi_local_geom ON grid_16km_aoi_local USING GIST(the_geom);
CREATE UNIQUE INDEX idx_grid_16km_aoi_local_gridid ON grid_16km_aoi_local(gridid_16km);
ANALYZE grid_16km_aoi_local;

DROP TABLE IF EXISTS grid_8km_aoi_local;
CREATE TABLE grid_8km_aoi_local AS
  SELECT gridid_8km, the_geom FROM mesh_fdw.grid_8km_aoi;
CREATE INDEX idx_grid_8km_aoi_local_geom ON grid_8km_aoi_local USING GIST(the_geom);
CREATE UNIQUE INDEX idx_grid_8km_aoi_local_gridid ON grid_8km_aoi_local(gridid_8km);
ANALYZE grid_8km_aoi_local;

DROP TABLE IF EXISTS grid_ageb_aoi_local;
CREATE TABLE grid_ageb_aoi_local AS
  SELECT gridid_ageb, the_geom FROM mesh_fdw.grid_ageb_aoi;
CREATE INDEX idx_grid_ageb_aoi_local_geom ON grid_ageb_aoi_local USING GIST(the_geom);
CREATE UNIQUE INDEX idx_grid_ageb_aoi_local_gridid ON grid_ageb_aoi_local(gridid_ageb);
ANALYZE grid_ageb_aoi_local;

DROP TABLE IF EXISTS grid_cue_aoi_local;
CREATE TABLE grid_cue_aoi_local AS
  SELECT gridid_cue, the_geom FROM mesh_fdw.grid_cue_aoi;
CREATE INDEX idx_grid_cue_aoi_local_geom ON grid_cue_aoi_local USING GIST(the_geom);
CREATE UNIQUE INDEX idx_grid_cue_aoi_local_gridid ON grid_cue_aoi_local(gridid_cue);
ANALYZE grid_cue_aoi_local;

DROP TABLE IF EXISTS grid_mun_aoi_local;
CREATE TABLE grid_mun_aoi_local AS
  SELECT gridid_mun, the_geom FROM mesh_fdw.grid_mun_aoi;
CREATE INDEX idx_grid_mun_aoi_local_geom ON grid_mun_aoi_local USING GIST(the_geom);
CREATE UNIQUE INDEX idx_grid_mun_aoi_local_gridid ON grid_mun_aoi_local(gridid_mun);
ANALYZE grid_mun_aoi_local;

DROP TABLE IF EXISTS grid_state_aoi_local;
CREATE TABLE grid_state_aoi_local AS
  SELECT gridid_state, the_geom FROM mesh_fdw.grid_state_aoi;
CREATE INDEX idx_grid_state_aoi_local_geom ON grid_state_aoi_local USING GIST(the_geom);
CREATE UNIQUE INDEX idx_grid_state_aoi_local_gridid ON grid_state_aoi_local(gridid_state);
ANALYZE grid_state_aoi_local;
