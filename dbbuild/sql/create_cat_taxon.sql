DROP TABLE IF EXISTS cat_taxon;

CREATE TABLE cat_taxon (
    id                SERIAL PRIMARY KEY,
    taxon             VARCHAR(20),
    description       VARCHAR(250),
    column_taxon_name VARCHAR(100),
    available_grids   INT[],
    filter_fields     JSONB,
    level_size        BIGINT
);

INSERT INTO cat_taxon (taxon, description, column_taxon_name, available_grids, filter_fields, level_size)
VALUES
    ('reino',   'Reinos en GBIF',   'kingdom',  '{}'::int[],
        '{"min_occ": "integer", "in_sin_fecha": "boolean"}',
        (SELECT COUNT(DISTINCT kingdom) FROM sp_gbif WHERE kingdom <> '')),

    ('phylum',  'Phylums en GBIF',  'phylum',   '{}'::int[],
        '{"min_occ": "integer", "in_sin_fecha": "boolean"}',
        (SELECT COUNT(DISTINCT phylum) FROM sp_gbif WHERE phylum <> '')),

    ('clase',   'Clases en GBIF',   'class',    '{}'::int[],
        '{"min_occ": "integer", "in_sin_fecha": "boolean"}',
        (SELECT COUNT(DISTINCT "class") FROM sp_gbif WHERE "class" <> '')),

    ('orden',   'Ordenes en GBIF',  'order',    '{}'::int[],
        '{"min_occ": "integer", "in_sin_fecha": "boolean"}',
        (SELECT COUNT(DISTINCT "order") FROM sp_gbif WHERE "order" <> '')),

    ('familia', 'Familias en GBIF', 'family',   '{}'::int[],
        '{"min_occ": "integer", "in_sin_fecha": "boolean"}',
        (SELECT COUNT(DISTINCT family) FROM sp_gbif WHERE family <> '')),

    ('genero',  'Géneros en GBIF',  'genus',    '{}'::int[],
        '{"min_occ": "integer", "in_sin_fecha": "boolean"}',
        (SELECT COUNT(DISTINCT genus) FROM sp_gbif WHERE genus <> '')),

    ('especie', 'Especies en GBIF', 'species',  '{}'::int[],
        '{"min_occ": "integer", "in_sin_fecha": "boolean"}',
        (SELECT COUNT(DISTINCT species) FROM sp_gbif WHERE species <> ''));


-- Calcula available_grids dinámicamente cruzando gbif.geom con mesh_fdw.cat_grid.
-- Todos los niveles taxonómicos comparten la misma cobertura geográfica,
-- por lo que se calcula una vez y se aplica a todos los registros de cat_taxon.
DO $$
DECLARE
  t               record;
  total_targets   int;
  i               int := 0;
  total_ok        int := 0;
  v_sql           text;
  has_presence    boolean;
  has_region_col  boolean;
  has_border_col  boolean;
  result_grids    int4[];
  t0              timestamptz;
BEGIN
  t0 := clock_timestamp();

  CREATE TEMP TABLE tmp_gbif_mesh_presence (
    table_view_name text,
    region_id       int4,
    has_presence    boolean,
    PRIMARY KEY (table_view_name, region_id)
  ) ON COMMIT DROP;

  SELECT count(*)
  INTO total_targets
  FROM (
    SELECT DISTINCT table_view_name, region_id
    FROM mesh_fdw.cat_grid
    WHERE table_view_name IS NOT NULL
      AND region_id IS NOT NULL
  ) q;

  RAISE NOTICE '[gbif_available_grids] Inicio. combinaciones (vista,region)=%', total_targets;

  FOR t IN
    SELECT DISTINCT table_view_name, region_id
    FROM mesh_fdw.cat_grid
    WHERE table_view_name IS NOT NULL
      AND region_id IS NOT NULL
    ORDER BY table_view_name, region_id
  LOOP
    i := i + 1;
    RAISE NOTICE '[gbif_available_grids] %/% -> vista=% region=%', i, total_targets, t.table_view_name, t.region_id;

    -- Verificar que la vista existe en mesh_fdw
    IF to_regclass(format('mesh_fdw.%I', t.table_view_name)) IS NULL THEN
      RAISE NOTICE '[gbif_available_grids] omite: tabla no existe mesh_fdw.%', t.table_view_name;
      INSERT INTO tmp_gbif_mesh_presence VALUES (t.table_view_name, t.region_id, false)
      ON CONFLICT DO NOTHING;
      CONTINUE;
    END IF;

    -- Verificar columnas requeridas en la vista
    SELECT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'mesh_fdw'
        AND table_name   = t.table_view_name
        AND column_name  = 'region_id'
    ) INTO has_region_col;

    SELECT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'mesh_fdw'
        AND table_name   = t.table_view_name
        AND column_name  = 'border'
    ) INTO has_border_col;

    IF NOT has_region_col OR NOT has_border_col THEN
      RAISE NOTICE '[gbif_available_grids] omite mesh_fdw.%: falta region_id o border', t.table_view_name;
      INSERT INTO tmp_gbif_mesh_presence VALUES (t.table_view_name, t.region_id, false)
      ON CONFLICT DO NOTHING;
      CONTINUE;
    END IF;

    -- Spatial join: ¿existe algún punto GBIF dentro de esta región del grid?
    v_sql := format($f$
      SELECT EXISTS (
        SELECT 1
        FROM gbif s
        JOIN mesh_fdw.%I g
          ON g.region_id = %s
         AND s.geom IS NOT NULL
         AND s.geom && g.border
         AND ST_Covers(g.border, s.geom)
        LIMIT 1
      )
    $f$, t.table_view_name, t.region_id);

    BEGIN
      EXECUTE v_sql INTO has_presence;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE '[gbif_available_grids] error evaluando %.region=%: %', t.table_view_name, t.region_id, SQLERRM;
      has_presence := false;
    END;

    IF has_presence THEN
      total_ok := total_ok + 1;
      RAISE NOTICE '[gbif_available_grids] presencia=true vista=% region=%', t.table_view_name, t.region_id;
    END IF;

    INSERT INTO tmp_gbif_mesh_presence (table_view_name, region_id, has_presence)
    VALUES (t.table_view_name, t.region_id, has_presence)
    ON CONFLICT (table_view_name, region_id)
    DO UPDATE SET has_presence = EXCLUDED.has_presence;
  END LOOP;

  -- Recopilar grid_ids con presencia
  SELECT COALESCE(array_agg(cg.grid_id ORDER BY cg.grid_id), '{}'::int4[])
  INTO result_grids
  FROM mesh_fdw.cat_grid cg
  JOIN tmp_gbif_mesh_presence p
    ON p.table_view_name = cg.table_view_name
   AND p.region_id       = cg.region_id
  WHERE p.has_presence;

  -- Aplicar a todos los niveles taxonómicos (misma cobertura geográfica)
  UPDATE cat_taxon SET available_grids = result_grids;

  RAISE NOTICE '[gbif_available_grids] Fin. grids_con_presencia=% de %', total_ok, total_targets;
  RAISE NOTICE '[gbif_available_grids] grids resultado=%', result_grids;
  RAISE NOTICE '[gbif_available_grids] tiempo=%', (clock_timestamp() - t0);
END$$;
