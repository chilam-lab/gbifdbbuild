#!/usr/bin/env python
"""
Precalcula sp_gbif.cells_<resolucion> (celdas de malla donde cae al menos una
ocurrencia de cada especie) para que get_data_byid del middleware no cruce en
vivo los puntos de gbif con la malla en cada análisis.

Dos fases: primero mallas regulares (64/32/16/8 km), luego las de México
(ageb/cue/mun/state). Cada worker toma lotes con FOR UPDATE SKIP LOCKED, así
que se pueden correr varios en paralelo. Es reanudable: solo toma especies con
cells_dirty = true.

Uso:
  python precompute_gbif_cells.py --setup            # columnas + copias locales de malla (una vez)
  python precompute_gbif_cells.py [--workers 4] [--batch-size 50]
"""
import os
import time
import logging
import argparse
from multiprocessing import Process
from pathlib import Path

import psycopg2
from dotenv import load_dotenv

BASE_DIR = Path(__file__).resolve().parent
load_dotenv(BASE_DIR / '.env')

FASES = [
    ('regulares', 'update_sp_gbif_cells_regular_batch.sql',
     'SELECT count(*) FROM sp_gbif WHERE cells_dirty AND '
     '(cells_64km IS NULL OR cells_32km IS NULL OR cells_16km IS NULL OR cells_8km IS NULL)'),
    ('irregulares', 'update_sp_gbif_cells_irregular_batch.sql',
     'SELECT count(*) FROM sp_gbif WHERE cells_dirty AND '
     'cells_64km IS NOT NULL AND cells_32km IS NOT NULL AND cells_16km IS NOT NULL AND cells_8km IS NOT NULL'),
]

logging.basicConfig(format='[%(asctime)s] %(message)s', datefmt='%Y-%m-%d %H:%M:%S', level=logging.INFO)
log = logging.getLogger('gbif_cells')


def get_sql(name):
    return (BASE_DIR / 'sql' / name).read_text()


def connect():
    conn = psycopg2.connect(
        dbname=os.getenv('DBNICHENAME'), host=os.getenv('DBNICHEHOST'), port=os.getenv('DBNICHEPORT'),
        user=os.getenv('DBNICHEUSER'), password=os.getenv('DBNICHEPASSWD'),
        application_name='gbif_cells_precompute')
    conn.autocommit = True
    return conn


def setup():
    with connect() as conn, conn.cursor() as cur:
        log.info('Agregando columnas cells_* a sp_gbif')
        cur.execute(get_sql('add_sp_gbif_cells_columns.sql'))
        log.info('Copiando mallas locales (grid_<res>_aoi_local)')
        t0 = time.time()
        cur.execute(get_sql('sync_mesh_grids_local.sql'))
        log.info(f'Mallas locales listas en {time.time() - t0:.0f}s')


def worker(wid, batch_size):
    conn = connect()
    cur = conn.cursor()
    for fase, sql_name, count_sql in FASES:
        cur.execute(count_sql)
        pendientes = cur.fetchone()[0]
        log.info(f'[w{wid}] Fase {fase}: especies pendientes={pendientes} batch_size={batch_size}')
        batch_sql = get_sql(sql_name)
        batch_no = done = 0
        t_fase = time.time()
        while True:
            batch_no += 1
            t0 = time.time()
            cur.execute(batch_sql, (batch_size,))
            updated = cur.rowcount or 0
            done += updated
            log.info(f'[w{wid}] [{fase}] Batch {batch_no}: especies={updated} '
                     f'tiempo={time.time() - t0:.1f}s acumulado={done}')
            if updated == 0:
                # En irregulares, otros workers pueden seguir en regulares:
                # esperar a que liberen sus especies antes de salir.
                if fase == 'irregulares':
                    cur.execute(FASES[0][2])
                    if cur.fetchone()[0] > 0:
                        time.sleep(30)
                        continue
                break
        log.info(f'[w{wid}] Fase {fase} lista: {done} especies en {(time.time() - t_fase) / 3600:.2f}h')
    conn.close()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--setup', action='store_true', help='crear columnas y copias locales de malla')
    ap.add_argument('--workers', type=int, default=int(os.getenv('CELLS_WORKERS', '4')))
    ap.add_argument('--batch-size', type=int, default=int(os.getenv('CELLS_BATCH_SIZE', '50')))
    args = ap.parse_args()

    if args.setup:
        setup()
        return

    # Los workers no se esperan entre fases: uno que termina regulares pasa a
    # irregulares mientras otros siguen; la fase 2 solo toma especies con
    # cells_8km ya calculado, así que no hay choque.
    procs = [Process(target=worker, args=(i + 1, args.batch_size)) for i in range(args.workers)]
    for p in procs:
        p.start()
    for p in procs:
        p.join()

    with connect() as conn, conn.cursor() as cur:
        cur.execute('SELECT count(*) FROM sp_gbif WHERE cells_dirty')
        restantes = cur.fetchone()[0]
    log.info(f'Precalculo GBIF completo. Especies pendientes: {restantes}')


if __name__ == '__main__':
    main()
