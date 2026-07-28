DROP TABLE IF EXISTS cat_taxon;

CREATE TABLE cat_taxon (
    id               SERIAL PRIMARY KEY,
    taxon            VARCHAR(20),
    description      VARCHAR(250),
    column_taxon_name VARCHAR(100),
    available_grids  INT[],
    filter_fields    JSONB,
    level_size       BIGINT
);

INSERT INTO cat_taxon (taxon, description, column_taxon_name, available_grids, filter_fields, level_size)
VALUES
    ('reino',   'Reinos en GBIF',   'kingdom',  '{1,4,5,8,9,12,13,16,17,18,19,20}',
        '{"min_occ": "integer", "in_sin_fecha": "boolean"}',
        (SELECT COUNT(DISTINCT kingdom) FROM sp_gbif WHERE kingdom <> '')),

    ('phylum',  'Phylums en GBIF',  'phylum',   '{1,4,5,8,9,12,13,16,17,18,19,20}',
        '{"min_occ": "integer", "in_sin_fecha": "boolean"}',
        (SELECT COUNT(DISTINCT phylum) FROM sp_gbif WHERE phylum <> '')),

    ('clase',   'Clases en GBIF',   'class',    '{1,4,5,8,9,12,13,16,17,18,19,20}',
        '{"min_occ": "integer", "in_sin_fecha": "boolean"}',
        (SELECT COUNT(DISTINCT "class") FROM sp_gbif WHERE "class" <> '')),

    ('orden',   'Ordenes en GBIF',  'order',    '{1,4,5,8,9,12,13,16,17,18,19,20}',
        '{"min_occ": "integer", "in_sin_fecha": "boolean"}',
        (SELECT COUNT(DISTINCT "order") FROM sp_gbif WHERE "order" <> '')),

    ('familia', 'Familias en GBIF', 'family',   '{1,4,5,8,9,12,13,16,17,18,19,20}',
        '{"min_occ": "integer", "in_sin_fecha": "boolean"}',
        (SELECT COUNT(DISTINCT family) FROM sp_gbif WHERE family <> '')),

    ('genero',  'Géneros en GBIF',  'genus',    '{1,4,5,8,9,12,13,16,17,18,19,20}',
        '{"min_occ": "integer", "in_sin_fecha": "boolean"}',
        (SELECT COUNT(DISTINCT genus) FROM sp_gbif WHERE genus <> '')),

    ('especie', 'Especies en GBIF', 'species',  '{1,4,5,8,9,12,13,16,17,18,19,20}',
        '{"min_occ": "integer", "in_sin_fecha": "boolean"}',
        (SELECT COUNT(DISTINCT species) FROM sp_gbif WHERE species <> ''));
