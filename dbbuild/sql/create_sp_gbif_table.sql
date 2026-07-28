DROP TABLE IF EXISTS sp_gbif;

CREATE TABLE sp_gbif AS
SELECT DISTINCT
    kingdom,
    phylum,
    "class",
    "order",
    family,
    genus,
    species,
    "scientificName",
    "specificEpithet",
    "taxonID",
    "taxonRank",
    "taxonomicStatus"
FROM gbif
WHERE species IS NOT NULL AND species <> '';

ALTER TABLE sp_gbif ADD COLUMN id_especie SERIAL PRIMARY KEY;

UPDATE sp_gbif SET
    kingdom  = COALESCE(kingdom, ''),
    phylum   = COALESCE(phylum, ''),
    "class"  = COALESCE("class", ''),
    "order"  = COALESCE("order", ''),
    family   = COALESCE(family, ''),
    genus    = COALESCE(genus, ''),
    species  = COALESCE(species, '');

CREATE INDEX IF NOT EXISTS idx_sp_gbif_kingdom  ON sp_gbif(kingdom);
CREATE INDEX IF NOT EXISTS idx_sp_gbif_phylum   ON sp_gbif(phylum);
CREATE INDEX IF NOT EXISTS idx_sp_gbif_class    ON sp_gbif("class");
CREATE INDEX IF NOT EXISTS idx_sp_gbif_order    ON sp_gbif("order");
CREATE INDEX IF NOT EXISTS idx_sp_gbif_family   ON sp_gbif(family);
CREATE INDEX IF NOT EXISTS idx_sp_gbif_genus    ON sp_gbif(genus);
CREATE INDEX IF NOT EXISTS idx_sp_gbif_species  ON sp_gbif(species);
CREATE INDEX IF NOT EXISTS idx_sp_gbif_taxonomia ON sp_gbif(kingdom, phylum, "class", "order", family, genus, species);
