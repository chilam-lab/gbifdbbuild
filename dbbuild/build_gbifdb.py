#!/usr/bin/env python3
"""
Pipeline de carga de datos GBIF (Darwin Core) hacia PostgreSQL/PostGIS.

Pasos:
  1. Validar variables de entorno
  2. Instalar extensiones PostGIS
  3. Crear tabla gbif y cargar desde TSV (chunked, con progreso)
  4. Construir tabla sp_gbif (taxonomía única)
  5. Asignar id_especie en gbif (batch update)
  6. Configurar FDW hacia mesh DB
  7. Crear tabla cat_taxon
  8. Insertar/actualizar data_source_info
"""

import os
import sys
import glob
import psycopg2
import psycopg2.extras as extras
import pandas as pd
from pathlib import Path
from psycopg2.extensions import ISOLATION_LEVEL_AUTOCOMMIT
from dotenv import load_dotenv
from aux_functions import get_sql, setup_logger

# ---------------------------------------------------------------------------
# Configuración
# ---------------------------------------------------------------------------

BASE_DIR = Path(__file__).resolve().parent

create_extensions_sql   = str(BASE_DIR / 'sql' / 'create_extensions.sql')
create_gbif_table_sql   = str(BASE_DIR / 'sql' / 'create_gbif_table.sql')
create_sp_gbif_sql      = str(BASE_DIR / 'sql' / 'create_sp_gbif_table.sql')
create_cat_taxon_sql    = str(BASE_DIR / 'sql' / 'create_cat_taxon.sql')
create_mesh_fdw_sql     = str(BASE_DIR / 'sql' / 'create_mesh_fdw.sql')

# Archivo de ocurrencias Darwin Core (TSV)
RUTA_ARCHIVO = os.getenv('GBIF_FILE', '/data/occurrence.txt')
CHUNK_SIZE   = int(os.getenv('GBIF_CHUNK_SIZE', '10000'))
BATCH_SIZE   = int(os.getenv('GBIF_BATCH_SIZE', '1000'))

# Columnas Darwin Core que se cargan en la tabla gbif
GBIF_COLUMNS = [
    'gbifID', 'kingdom', 'phylum', 'class', 'order', 'family',
    'genus', 'species', 'specificEpithet', 'scientificName',
    'taxonRank', 'taxonomicStatus', 'taxonID', 'basisOfRecord',
    'year', 'decimalLatitude', 'decimalLongitude',
]

logger = setup_logger()
load_dotenv()


def get_conn(autocommit=False):
    conn = psycopg2.connect(
        dbname=os.getenv('DBNICHENAME'),
        host=os.getenv('DBNICHEHOST'),
        port=os.getenv('DBNICHEPORT'),
        user=os.getenv('DBNICHEUSER'),
        password=os.getenv('DBNICHEPASSWD'),
    )
    if autocommit:
        conn.set_isolation_level(ISOLATION_LEVEL_AUTOCOMMIT)
    return conn


# ---------------------------------------------------------------------------
# Paso 1: Validar variables de entorno
# ---------------------------------------------------------------------------
try:
    required = ['DBNICHENAME', 'DBNICHEHOST', 'DBNICHEPORT', 'DBNICHEUSER', 'DBNICHEPASSWD']
    missing = [v for v in required if not os.getenv(v)]
    if missing:
        raise EnvironmentError(f'Variables de entorno faltantes: {missing}')
    logger.info(f'Conectando a {os.getenv("DBNICHEUSER")}@{os.getenv("DBNICHEHOST")}:{os.getenv("DBNICHEPORT")}/{os.getenv("DBNICHENAME")}')
except Exception as e:
    logger.error(f'Variables de entorno inválidas: {e}')
    sys.exit(1)


# ---------------------------------------------------------------------------
# Paso 2: Extensiones PostGIS
# ---------------------------------------------------------------------------
try:
    logger.info('Instalando extensiones PostGIS')
    sql_ext = get_sql(create_extensions_sql)
    conn = get_conn(autocommit=True)
    cur = conn.cursor()
    cur.execute(sql_ext)
    cur.close()
    conn.close()
    logger.info('Extensiones instaladas')
except Exception as e:
    logger.error(f'Error instalando extensiones: {e}')
    sys.exit(1)


# ---------------------------------------------------------------------------
# Paso 3: Crear tabla gbif y cargar datos desde TSV
# ---------------------------------------------------------------------------
progress_file = BASE_DIR / 'data' / 'gbif_load_progress.txt'

try:
    logger.info('Creando tabla gbif')
    conn = get_conn(autocommit=True)
    cur = conn.cursor()
    cur.execute(get_sql(create_gbif_table_sql))
    cur.close()
    conn.close()
    logger.info('Tabla gbif creada')
except Exception as e:
    logger.error(f'Error creando tabla gbif: {e}')
    sys.exit(1)

conn = None
cur = None
try:
    logger.info(f'Cargando ocurrencias desde {RUTA_ARCHIVO}')

    start_chunk = int(os.getenv('START_CHUNK', '0'))
    if progress_file.exists():
        saved = progress_file.read_text().strip()
        if saved.isdigit():
            start_chunk = max(start_chunk, int(saved))
    logger.info(f'Iniciando desde chunk {start_chunk}')

    conn = get_conn()
    cur = conn.cursor()

    # Columnas a leer del TSV (intersección con las disponibles en el archivo)
    total_inserted = 0

    for i, chunk in enumerate(pd.read_csv(
        RUTA_ARCHIVO,
        sep='\t',
        dtype=str,
        quoting=3,
        on_bad_lines='skip',
        chunksize=CHUNK_SIZE,
        engine='python',
        low_memory=False,
    )):
        if i < start_chunk:
            continue

        # Normalizar nombres de columna
        chunk.columns = [c.strip() for c in chunk.columns]

        # Filtrar solo columnas que existen en el archivo y en GBIF_COLUMNS
        cols_disponibles = [c for c in GBIF_COLUMNS if c in chunk.columns]
        chunk = chunk[cols_disponibles].copy()

        # Eliminar registros sin coordenadas
        chunk = chunk.dropna(subset=['decimalLatitude', 'decimalLongitude'])
        chunk['decimalLatitude']  = pd.to_numeric(chunk['decimalLatitude'],  errors='coerce')
        chunk['decimalLongitude'] = pd.to_numeric(chunk['decimalLongitude'], errors='coerce')
        chunk = chunk.dropna(subset=['decimalLatitude', 'decimalLongitude'])

        if chunk.empty:
            logger.info(f'Chunk {i}: sin registros con coordenadas, omitido')
            progress_file.write_text(str(i + 1))
            continue

        chunk = chunk.astype(object).where(pd.notnull(chunk), None)

        # Insertar por lotes dentro del chunk
        rows = chunk.to_dict('records')
        insert_cols = ', '.join(f'"{c}"' for c in cols_disponibles)
        placeholders = ', '.join(['%s'] * len(cols_disponibles))
        wkt_geom = "ST_SetSRID(ST_MakePoint(%s, %s), 4326)"

        for j in range(0, len(rows), BATCH_SIZE):
            batch = rows[j:j + BATCH_SIZE]
            values = []
            geom_vals = []
            for row in batch:
                values.append(tuple(row.get(c) for c in cols_disponibles))
                geom_vals.append((
                    float(row['decimalLongitude']),
                    float(row['decimalLatitude']),
                ))

            try:
                args = ','.join(
                    cur.mogrify(
                        f'({placeholders}, {wkt_geom})',
                        list(v) + list(g)
                    ).decode('utf-8')
                    for v, g in zip(values, geom_vals)
                )
                cur.execute(
                    f'INSERT INTO gbif ({insert_cols}, geom) VALUES {args} '
                    f'ON CONFLICT ("gbifID") DO NOTHING'
                )
                conn.commit()
                total_inserted += cur.rowcount
            except Exception as err:
                conn.rollback()
                logger.warning(f'Chunk {i} lote {j}: error de inserción: {err}')

        progress_file.write_text(str(i + 1))
        logger.info(f'Chunk {i}: {len(chunk)} filas procesadas. Total insertado: {total_inserted}')

    logger.info(f'Carga GBIF completada. Total insertado: {total_inserted}')

except Exception as e:
    logger.error(f'Error cargando ocurrencias GBIF: {e}')
    sys.exit(1)
finally:
    if cur:
        cur.close()
    if conn:
        conn.close()


# ---------------------------------------------------------------------------
# Paso 4: Crear tabla sp_gbif (taxonomía única)
# ---------------------------------------------------------------------------
try:
    logger.info('Creando tabla sp_gbif')
    conn = get_conn(autocommit=True)
    cur = conn.cursor()
    cur.execute(get_sql(create_sp_gbif_sql))
    cur.close()
    conn.close()

    conn = get_conn()
    cur = conn.cursor()
    cur.execute('SELECT COUNT(*) FROM sp_gbif')
    count = cur.fetchone()[0]
    cur.close()
    conn.close()
    logger.info(f'sp_gbif creada: {count} especies únicas')
except Exception as e:
    logger.error(f'Error creando sp_gbif: {e}')
    sys.exit(1)


# ---------------------------------------------------------------------------
# Paso 5: Asignar id_especie en gbif (batch update)
# ---------------------------------------------------------------------------
conn = None
cur = None
try:
    logger.info('Asignando id_especie en tabla gbif (por lotes)')

    conn = get_conn()
    cur = conn.cursor()

    cur.execute("""
        CREATE INDEX IF NOT EXISTS idx_sp_gbif_match
        ON sp_gbif(kingdom, phylum, "class", "order", family, genus, species)
    """)
    conn.commit()

    SPID_BATCH = int(os.getenv('SPID_BATCH_SIZE', '50000'))
    total_updated = 0
    batch_no = 0

    while True:
        batch_no += 1
        cur.execute("""
            WITH rows_to_update AS (
                SELECT t0.ctid
                FROM gbif t0
                JOIN sp_gbif t1 ON
                    t0.kingdom = t1.kingdom AND
                    t0.phylum  = t1.phylum  AND
                    t0."class" = t1."class" AND
                    t0."order" = t1."order" AND
                    t0.family  = t1.family  AND
                    t0.genus   = t1.genus   AND
                    t0.species = t1.species
                WHERE t0.id_especie IS NULL
                LIMIT %s
            )
            UPDATE gbif t0
            SET id_especie = t1.id_especie
            FROM sp_gbif t1, rows_to_update r
            WHERE t0.ctid = r.ctid AND
                  t0.kingdom = t1.kingdom AND
                  t0.phylum  = t1.phylum  AND
                  t0."class" = t1."class" AND
                  t0."order" = t1."order" AND
                  t0.family  = t1.family  AND
                  t0.genus   = t1.genus   AND
                  t0.species = t1.species
        """, (SPID_BATCH,))

        updated = cur.rowcount
        conn.commit()

        if updated == 0:
            logger.info('Sin registros pendientes, finaliza asignación de id_especie')
            break

        total_updated += updated
        logger.info(f'Lote {batch_no}: {updated} actualizados. Acumulado: {total_updated}')

    logger.info(f'id_especie asignado. Total: {total_updated}')

except Exception as e:
    if conn:
        conn.rollback()
    logger.error(f'Error asignando id_especie: {e}')
    sys.exit(1)
finally:
    if cur:
        cur.close()
    if conn:
        conn.close()


# ---------------------------------------------------------------------------
# Paso 6: Configurar FDW hacia mesh DB
# ---------------------------------------------------------------------------
try:
    DBMESHNAME   = os.getenv('DBMESHNAME')
    DBMESHHOST   = os.getenv('DBMESHHOST')
    DBMESHPORT   = os.getenv('DBMESHPORT')
    DBMESHUSER   = os.getenv('DBMESHUSER')
    DBMESHPASSWD = os.getenv('DBMESHPASSWD')

    if not all([DBMESHNAME, DBMESHHOST, DBMESHPORT, DBMESHUSER, DBMESHPASSWD]):
        logger.warning('Variables DBMESH* no configuradas, se omite FDW')
    else:
        logger.info('Configurando FDW hacia mesh DB')
        mesh_sql = get_sql(create_mesh_fdw_sql)
        mesh_sql = mesh_sql.replace('__MESHDB_HOST__',  DBMESHHOST)
        mesh_sql = mesh_sql.replace('__MESHDB_PORT__',  DBMESHPORT)
        mesh_sql = mesh_sql.replace('__MESHDB_NAME__',  DBMESHNAME)
        mesh_sql = mesh_sql.replace('__MESHDB_USER__',  DBMESHUSER)
        mesh_sql = mesh_sql.replace('__MESHDB_PASS__',  DBMESHPASSWD.replace("'", "''"))

        conn = get_conn(autocommit=True)
        cur = conn.cursor()
        cur.execute(mesh_sql)
        cur.close()
        conn.close()
        logger.info('FDW configurado correctamente')

except Exception as e:
    logger.error(f'Error configurando FDW: {e}')
    sys.exit(1)


# ---------------------------------------------------------------------------
# Paso 7: Crear tabla cat_taxon
# ---------------------------------------------------------------------------
try:
    logger.info('Creando tabla cat_taxon')
    conn = get_conn(autocommit=True)
    cur = conn.cursor()
    cur.execute(get_sql(create_cat_taxon_sql))
    cur.close()
    conn.close()

    conn = get_conn()
    cur = conn.cursor()
    cur.execute('SELECT COUNT(*), MIN(level_size), MAX(level_size) FROM cat_taxon')
    row = cur.fetchone()
    cur.close()
    conn.close()
    logger.info(f'cat_taxon creada: {row[0]} niveles, level_size min={row[1]} max={row[2]}')

except Exception as e:
    logger.error(f'Error creando cat_taxon: {e}')
    sys.exit(1)


# ---------------------------------------------------------------------------
# Paso 8: Insertar/actualizar data_source_info
# ---------------------------------------------------------------------------
try:
    logger.info('Actualizando data_source_info')
    conn = get_conn(autocommit=True)
    cur = conn.cursor()

    cur.execute("""
        CREATE TABLE IF NOT EXISTS data_source_info (
            id           SERIAL PRIMARY KEY,
            name         VARCHAR(200) NOT NULL UNIQUE,
            description  TEXT,
            source_url   TEXT,
            download_url TEXT,
            dict_url     TEXT,
            created_at   TIMESTAMP WITHOUT TIME ZONE DEFAULT now(),
            updated_at   TIMESTAMP WITHOUT TIME ZONE DEFAULT now()
        )
    """)

    cur.execute("""
        INSERT INTO data_source_info (name, description, source_url, download_url, dict_url)
        VALUES (%s, %s, %s, %s, %s)
        ON CONFLICT (name) DO UPDATE SET
            description  = EXCLUDED.description,
            source_url   = EXCLUDED.source_url,
            download_url = EXCLUDED.download_url,
            dict_url     = EXCLUDED.dict_url,
            updated_at   = now()
    """, (
        'GBIF Data Source',
        'Global Biodiversity Information Facility — registros de ocurrencia de biodiversidad a nivel mundial',
        'https://www.gbif.org/',
        'https://www.gbif.org/occurrence/download',
        'https://ipt.gbif.org/manual/en/ipt/latest/dwca-guide',
    ))

    cur.close()
    conn.close()
    logger.info('data_source_info actualizada correctamente')

except Exception as e:
    logger.error(f'Error actualizando data_source_info: {e}')
    sys.exit(1)


logger.info('Pipeline GBIF completado exitosamente')
