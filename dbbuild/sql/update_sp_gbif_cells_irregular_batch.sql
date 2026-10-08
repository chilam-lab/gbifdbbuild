-- Fase 2 del precalculo de celdas por especie: mallas IRREGULARES
-- (ageb/cue/mun/state). Corre despues de la fase 1 (regulares) y es la que
-- cierra cells_dirty=false. Mismo patron de plan que la fase 1.
WITH batch AS MATERIALIZED (
  SELECT id_especie
  FROM sp_gbif
  WHERE cells_dirty = true AND cells_64km IS NOT NULL AND cells_32km IS NOT NULL AND cells_16km IS NOT NULL AND cells_8km IS NOT NULL
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
cageb AS (
  SELECT p.id_especie, array_agg(DISTINCT g.gridid_ageb ORDER BY g.gridid_ageb) AS cells
  FROM pts p JOIN grid_ageb_aoi_local g ON ST_Intersects(p.geom, g.the_geom)
  GROUP BY p.id_especie
),
ccue AS (
  SELECT p.id_especie, array_agg(DISTINCT g.gridid_cue ORDER BY g.gridid_cue) AS cells
  FROM pts p JOIN grid_cue_aoi_local g ON ST_Intersects(p.geom, g.the_geom)
  GROUP BY p.id_especie
),
cmun AS (
  SELECT p.id_especie, array_agg(DISTINCT g.gridid_mun ORDER BY g.gridid_mun) AS cells
  FROM pts p JOIN grid_mun_aoi_local g ON ST_Intersects(p.geom, g.the_geom)
  GROUP BY p.id_especie
),
cstate AS (
  SELECT p.id_especie, array_agg(DISTINCT g.gridid_state ORDER BY g.gridid_state) AS cells
  FROM pts p JOIN grid_state_aoi_local g ON ST_Intersects(p.geom, g.the_geom)
  GROUP BY p.id_especie
)
UPDATE sp_gbif sp
SET
  cells_ageb = COALESCE(cageb.cells, '{}'::integer[]),
  cells_cue = COALESCE(ccue.cells, '{}'::integer[]),
  cells_mun = COALESCE(cmun.cells, '{}'::integer[]),
  cells_state = COALESCE(cstate.cells, '{}'::integer[]),
  cells_dirty = false
FROM batch b
LEFT JOIN cageb ON cageb.id_especie = b.id_especie
LEFT JOIN ccue ON ccue.id_especie = b.id_especie
LEFT JOIN cmun ON cmun.id_especie = b.id_especie
LEFT JOIN cstate ON cstate.id_especie = b.id_especie
WHERE sp.id_especie = b.id_especie;
