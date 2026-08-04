CREATE TABLE IF NOT EXISTS sp_gbif (
    id_especie        SERIAL PRIMARY KEY,
    kingdom           TEXT NOT NULL DEFAULT '',
    phylum            TEXT NOT NULL DEFAULT '',
    "class"           TEXT NOT NULL DEFAULT '',
    "order"           TEXT NOT NULL DEFAULT '',
    family            TEXT NOT NULL DEFAULT '',
    genus             TEXT NOT NULL DEFAULT '',
    species           TEXT NOT NULL DEFAULT '',
    "scientificName"  TEXT,
    "specificEpithet" TEXT,
    "taxonID"         TEXT,
    "taxonRank"       TEXT,
    "taxonomicStatus" TEXT
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_sp_gbif_taxonomia
    ON sp_gbif(kingdom, phylum, "class", "order", family, genus, species);

-- Inserta solo combinaciones taxonómicas nuevas; conserva id_especie de las existentes
-- para no invalidar el mapeo ya asignado en gbif.id_especie en corridas previas.
INSERT INTO sp_gbif (
    kingdom, phylum, "class", "order", family, genus, species,
    "scientificName", "specificEpithet", "taxonID", "taxonRank", "taxonomicStatus"
)
SELECT DISTINCT ON (
    COALESCE(g.kingdom, ''), COALESCE(g.phylum, ''), COALESCE(g."class", ''),
    COALESCE(g."order", ''), COALESCE(g.family, ''), COALESCE(g.genus, ''), COALESCE(g.species, '')
)
    COALESCE(g.kingdom, ''), COALESCE(g.phylum, ''), COALESCE(g."class", ''),
    COALESCE(g."order", ''), COALESCE(g.family, ''), COALESCE(g.genus, ''), COALESCE(g.species, ''),
    g."scientificName", g."specificEpithet", g."taxonID", g."taxonRank", g."taxonomicStatus"
FROM gbif g
WHERE g.species IS NOT NULL AND g.species <> ''
ORDER BY
    COALESCE(g.kingdom, ''), COALESCE(g.phylum, ''), COALESCE(g."class", ''),
    COALESCE(g."order", ''), COALESCE(g.family, ''), COALESCE(g.genus, ''), COALESCE(g.species, '')
ON CONFLICT (kingdom, phylum, "class", "order", family, genus, species) DO NOTHING;

CREATE INDEX IF NOT EXISTS idx_sp_gbif_kingdom  ON sp_gbif(kingdom);
CREATE INDEX IF NOT EXISTS idx_sp_gbif_phylum   ON sp_gbif(phylum);
CREATE INDEX IF NOT EXISTS idx_sp_gbif_class    ON sp_gbif("class");
CREATE INDEX IF NOT EXISTS idx_sp_gbif_order    ON sp_gbif("order");
CREATE INDEX IF NOT EXISTS idx_sp_gbif_family   ON sp_gbif(family);
CREATE INDEX IF NOT EXISTS idx_sp_gbif_genus    ON sp_gbif(genus);
CREATE INDEX IF NOT EXISTS idx_sp_gbif_species  ON sp_gbif(species);
CREATE INDEX IF NOT EXISTS idx_sp_gbif_taxonomia ON sp_gbif(kingdom, phylum, "class", "order", family, genus, species);
