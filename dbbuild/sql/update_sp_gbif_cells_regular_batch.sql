-- Fase 1 del precalculo de celdas por especie: mallas REGULARES
-- (64km/32km/16km/8km). Las irregulares (ageb/cue/mun/state) las calcula
-- despues update_sp_gbif_cells_irregular_batch.sql. El middleware usa cada
-- columna cells_<res> en cuanto deja de ser NULL, sin mirar cells_dirty.
--
-- batch y pts van MATERIALIZED y cada malla se une contra pts (los puntos
-- del lote, leidos de gbif una sola vez); sin esto el planner puede invertir
-- el join y recorrer cada poligono contra el GiST de gbif (76M puntos). Ver
-- el mismo archivo en speciesdbbuild.
--
-- Se toman especies con CUALQUIER regular en NULL (no solo cells_8km): el
-- write-back del middleware puede llenar una sola columna antes que el batch.
--
-- FOR UPDATE SKIP LOCKED permite correr varios workers en paralelo.
WITH batch AS MATERIALIZED (
  SELECT id_especie
  FROM sp_gbif
  WHERE cells_dirty = true AND (cells_64km IS NULL OR cells_32km IS NULL OR cells_16km IS NULL OR cells_8km IS NULL)
  ORDER BY id_especie
  LIMIT %s
  FOR UPDATE SKIP LOCKED
),
pts AS MATERIALIZED (
  -- DISTINCT: GBIF repite mucho la misma coordenada por especie y cada
  -- punto unico basta para saber en que celda cae.
  SELECT DISTINCT s.id_especie, s.geom
  FROM batch b
  JOIN gbif s ON s.id_especie = b.id_especie AND s.geom IS NOT NULL
),
c64km AS (
  SELECT p.id_especie, array_agg(DISTINCT g.gridid_64km ORDER BY g.gridid_64km) AS cells
  FROM pts p JOIN grid_64km_aoi_local g ON ST_Intersects(p.geom, g.the_geom)
  GROUP BY p.id_especie
),
c32km AS (
  SELECT p.id_especie, array_agg(DISTINCT g.gridid_32km ORDER BY g.gridid_32km) AS cells
  FROM pts p JOIN grid_32km_aoi_local g ON ST_Intersects(p.geom, g.the_geom)
  GROUP BY p.id_especie
),
c16km AS (
  SELECT p.id_especie, array_agg(DISTINCT g.gridid_16km ORDER BY g.gridid_16km) AS cells
  FROM pts p JOIN grid_16km_aoi_local g ON ST_Intersects(p.geom, g.the_geom)
  GROUP BY p.id_especie
),
c8km AS (
  SELECT p.id_especie, array_agg(DISTINCT g.gridid_8km ORDER BY g.gridid_8km) AS cells
  FROM pts p JOIN grid_8km_aoi_local g ON ST_Intersects(p.geom, g.the_geom)
  GROUP BY p.id_especie
)
UPDATE sp_gbif sp
SET
  cells_64km = COALESCE(c64km.cells, '{}'::integer[]),
  cells_32km = COALESCE(c32km.cells, '{}'::integer[]),
  cells_16km = COALESCE(c16km.cells, '{}'::integer[]),
  cells_8km = COALESCE(c8km.cells, '{}'::integer[])
FROM batch b
LEFT JOIN c64km ON c64km.id_especie = b.id_especie
LEFT JOIN c32km ON c32km.id_especie = b.id_especie
LEFT JOIN c16km ON c16km.id_especie = b.id_especie
LEFT JOIN c8km ON c8km.id_especie = b.id_especie
WHERE sp.id_especie = b.id_especie;
