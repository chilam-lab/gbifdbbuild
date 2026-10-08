-- Arreglos precalculados de celdas por especie, por resolucion de malla.
-- Sustituyen el ST_Intersects en vivo que hace gbif1_controller.js
-- (get_data_byid) contra pool_mallas en cada consulta. Mismo diseño que
-- sp_snib.cells_* en speciesdbbuild.
--
-- cells_dirty marca que faltan (re)calcular los arreglos de esa especie.
-- Nace en true para que toda especie existente se calcule en la primera
-- corrida de precompute_gbif_cells.py.

ALTER TABLE sp_gbif
  ADD COLUMN IF NOT EXISTS cells_64km   INTEGER[],
  ADD COLUMN IF NOT EXISTS cells_32km   INTEGER[],
  ADD COLUMN IF NOT EXISTS cells_16km   INTEGER[],
  ADD COLUMN IF NOT EXISTS cells_8km    INTEGER[],
  ADD COLUMN IF NOT EXISTS cells_ageb   INTEGER[],
  ADD COLUMN IF NOT EXISTS cells_cue    INTEGER[],
  ADD COLUMN IF NOT EXISTS cells_mun    INTEGER[],
  ADD COLUMN IF NOT EXISTS cells_state  INTEGER[],
  ADD COLUMN IF NOT EXISTS cells_dirty  boolean NOT NULL DEFAULT true;

-- Solo acelera el WHERE cells_dirty = true del batch de recalculo.
CREATE INDEX IF NOT EXISTS idx_sp_gbif_cells_dirty ON sp_gbif(id_especie) WHERE cells_dirty = true;
