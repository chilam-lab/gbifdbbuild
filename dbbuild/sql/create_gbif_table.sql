CREATE TABLE IF NOT EXISTS gbif (
    id              SERIAL PRIMARY KEY,
    "gbifID"        TEXT UNIQUE,
    kingdom         TEXT,
    phylum          TEXT,
    "class"         TEXT,
    "order"         TEXT,
    family          TEXT,
    genus           TEXT,
    species         TEXT,
    "specificEpithet"   TEXT,
    "scientificName"    TEXT,
    "taxonRank"         TEXT,
    "taxonomicStatus"   TEXT,
    "taxonID"           TEXT,
    "basisOfRecord"     TEXT,
    year            TEXT,
    "decimalLatitude"   NUMERIC,
    "decimalLongitude"  NUMERIC,
    geom            GEOMETRY(Point, 4326),
    id_especie      INTEGER
);

CREATE INDEX IF NOT EXISTS idx_gbif_geom        ON gbif USING GIST(geom);
CREATE INDEX IF NOT EXISTS idx_gbif_id_especie  ON gbif(id_especie);
CREATE INDEX IF NOT EXISTS idx_gbif_species     ON gbif(species);
CREATE INDEX IF NOT EXISTS idx_gbif_genus       ON gbif(genus);
CREATE INDEX IF NOT EXISTS idx_gbif_family      ON gbif(family);
CREATE INDEX IF NOT EXISTS idx_gbif_class       ON gbif("class");
CREATE INDEX IF NOT EXISTS idx_gbif_order       ON gbif("order");
CREATE INDEX IF NOT EXISTS idx_gbif_kingdom     ON gbif(kingdom);
CREATE INDEX IF NOT EXISTS idx_gbif_year        ON gbif(year);
CREATE INDEX IF NOT EXISTS idx_gbif_id_especie_null ON gbif(id_especie) WHERE id_especie IS NULL;
