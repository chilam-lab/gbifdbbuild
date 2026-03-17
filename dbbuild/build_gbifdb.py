#!/usr/bin/env python
import os
import time
import sys
import csv
import psycopg2
import psycopg2.extras as extras
from psycopg2.extras import execute_values
from psycopg2 import sql
# import subprocess
# import argparse
import glob
# from osgeo import gdal
# from shutil import copyfile
from aux_functions import *
# from pathlib import Path
import pandas as pd
from shapely.geometry import Point
from shapely import wkt

from psycopg2.extensions import ISOLATION_LEVEL_AUTOCOMMIT
from dotenv import load_dotenv, dotenv_values

create_extensions       = './sql/create_extensions.sql'
create_aoi_table    = './sql/create_aoi_table.sql'
geom_aoi_data       = './sql/geom_aoi.sql'
get_aoi        = './sql/get_aoi.sql'

root_folder                = './'
data_folder                = './data'
stored_procedures_folder   = './sql/stored_procedures'
stored_validation_folder   = '../stored_validation'
# create_snib_table          = './sql/create_snib_table.sql'
# create_sp_snib_table       = './sql/create_sp_snib_table.sql'
columns_file               = 'columns.txt'

# Ruta al archivo DwC
# ruta_archivo = "MX_plantae/occurrence.txt"
# ruta_archivo = "MX_fungi/occurrence_1000.txt"
# ruta_archivo = "EU_viruses/occurrence.txt"
# ruta_archivo = "CA/occurrence.txt"
ruta_archivo = "/data/occurrence.txt"


csv.field_size_limit(sys.maxsize)


create_geoportal_table     = './sql/create_geoportal_table.sql'

logger = setup_logger()
load_dotenv() 

DBNICHENAME=os.getenv("DBNICHENAME")
DBNICHEHOST=os.getenv("DBNICHEHOST")
DBNICHEPORT=os.getenv("DBNICHEPORT")
DBNICHEUSER=os.getenv("DBNICHEUSER")
DBNICHEPASSWD=os.getenv("DBNICHEPASSWD")

# os.chdir(data_folder)


# # Obteniendo variables de ambiente
# try:
    
#     logger.info('lectura de USUARIO: {0} en el HOST: {1}, BASE: {2} y PUERTO: {3}'.format(DBNICHEUSER, DBNICHEHOST, DBNICHENAME, DBNICHEPORT))
# except Exception as e:
#     logger.error('No se pudieron obtener las variables de entorno requeridas : {0}'.format(str(e)))
#     sys.exit()


# # Creando tabla aoi (area de interes) contempla todos los países con la columna de continente por continente
# try:

#     logger.info('Instalando extensiones y Creando tabla aoi a nivel mundial')
#     create_extensions_sql = get_sql(create_extensions) 
#     # # comentar siguietnes dos lineas si ya existen las tablas
#     # create_aoi_table_sql = get_sql(create_aoi_table) 
#     # geom_aoi_data_sql = get_sql(geom_aoi_data) 

#     conn = psycopg2.connect('dbname={0} host={1} port={2} user={3} password={4}'.format(DBNICHENAME, DBNICHEHOST, DBNICHEPORT, DBNICHEUSER, DBNICHEPASSWD))
#     conn.set_isolation_level(ISOLATION_LEVEL_AUTOCOMMIT)
#     cur = conn.cursor()

#     cur.execute(create_extensions_sql)
#     logger.info('create_extensions_sql')

#     # cur.execute(create_aoi_table_sql)
#     # logger.info('create_aoi_table_sql')

#     # cur.execute(geom_aoi_data_sql)
#     # logger.info('geom_aoi_data_sql')

#     cur.close()
#     conn.close()

# except Exception as e:
#     logger.error('No se pudo instalar las extensiones necesarias o crear: {0}'.format(str(e)))
#     sys.exit()


# # Insertando procedimientos almacenados
# try:
#   conn = psycopg2.connect('dbname={0} host={1} port={2} user={3} password={4}'.format(DBNICHENAME, DBNICHEHOST, DBNICHEPORT, DBNICHEUSER, DBNICHEPASSWD))
#   conn.set_isolation_level(ISOLATION_LEVEL_AUTOCOMMIT)

#   cur = conn.cursor()

#   os.chdir(stored_procedures_folder)
#   for file in glob.glob('*.sql'):
#       # print("file: {}".format(file))
#       with open(file, 'r') as f:
#           cur.execute(f.read())
    
#   os.chdir(stored_validation_folder)

#   for file in glob.glob('*.sql'):
#       # print("file: {}".format(file))
#       with open(file, 'r') as f:
#           cur.execute(f.read())
    
#   os.chdir('../..')
#   cur.close()
#   conn.close()

#   logger.info('Procedimientos almacenados insertados')
# except Exception as e:
#   logger.error('No se insertaron todos los procedimientos almacenados: {0}'.format(str(e)))
#   sys.exit()


# ******************* INICIO DE EJECUCIÓN DE SCRIPTS PARA AGREGAR MAS OCURRENCIAS ******************* 
# ****** SE COMENTA ESTA SECCION POR LA GRAN CANTIDAD DE REGISTROS SI LATITUD Y LONGITUD
# Creando tabla base directo del archivo DwC de GBIF
# chunk_size = 10000
# try:
  
#   os.chdir(data_folder)
    
#   logger.info('Cargando datos de ocurrencias')

#   conn = psycopg2.connect( database=DBNICHENAME, user=DBNICHEUSER, password=DBNICHEPASSWD, host=DBNICHEHOST, port=DBNICHEPORT)
#   cursor = conn.cursor()

#   # Cargar archivo con pandas
#   for chunk in pd.read_csv(ruta_archivo, delimiter='\t', dtype=str, quoting=3, on_bad_lines='skip', chunksize=chunk_size, engine='python'):
    
#     chunk.columns = [col.strip().replace(" ", "_").replace("-", "_") for col in chunk.columns]
#     # df = pd.read_csv(ruta_archivo, delimiter='\t', dtype=str, quoting=3, on_bad_lines='skip', engine='python')
#     # df = pd.read_csv(ruta_archivo, delimiter='\t', dtype=str, quoting=3, on_bad_lines='skip')

#     if "gbifID" not in chunk.columns:
#         raise ValueError("El archivo debe contener la columna 'gbifID'.")


    
#     column_definitions = ['"gbifID" TEXT UNIQUE'] + [f'"{col}" TEXT' for col in chunk.columns if col != "gbifID"]
#     # print("column_definitions")
#     # print(column_definitions)

#     create_table_sql = f"""
#     CREATE TABLE IF NOT EXISTS informacion_gbif (
#     id SERIAL PRIMARY KEY,
#     {', '.join(column_definitions)}
#     );"""

#     # print(create_table_sql)

#     cursor.execute(create_table_sql)
#     conn.commit()

#     # Insertar datos sin repetir gbifID
#     columns = chunk.columns.tolist()
#     if "gbifID" in columns:
#         columns.remove("gbifID")
#     columns = ["gbifID"] + columns 

#     # print("columns")
#     # print(columns)

#     placeholders = ', '.join(['%s'] * len(columns))
  
#     insert_sql = f"""
#     INSERT INTO informacion_gbif ({', '.join(['"' + c + '"' for c in columns])})
#     VALUES ({placeholders})
#     ON CONFLICT ("gbifID") DO NOTHING;"""

#     batch_size = 1000
#     rows = chunk[columns].values.tolist()

#     for i in range(0, len(rows), batch_size):
#         cursor.executemany(insert_sql, rows[i:i + batch_size])
#         conn.commit()

    
#   cursor.close()
#   conn.close()

# except Exception as e:
#   logger.error('No se pudieron agregar todas las ocurrencias: {0}'.format(str(e)))
#   sys.exit()
#   cursor.close()





# # Construyendo tabla con geometrias
# chunk_size = 10000
# try:
#     conn = psycopg2.connect('dbname={0} host={1} port={2} user={3} password={4}'.format(DBNICHENAME, DBNICHEHOST, DBNICHEPORT, DBNICHEUSER, DBNICHEPASSWD))
#     conn.set_isolation_level(ISOLATION_LEVEL_AUTOCOMMIT)
#     cur = conn.cursor()
    
#     logger.info('Creación de tablas')
#     os.chdir(data_folder)

#     # Cargar los nombres de las columnas
#     with open(columns_file, 'r') as f:
#         columnas_deseadas = [line.strip() for line in f.readlines() if line.strip()]

#     # logger.info(f"Columnas deseadas: {columnas_deseadas}")


#     # Cargar archivo con pandas en chunks
#     for chunk in pd.read_csv(ruta_archivo, delimiter='\t', dtype=str, quoting=3, on_bad_lines='skip', chunksize=chunk_size, engine='python'):

#         chunk.columns = [col.strip().replace(" ", "_").replace("-", "_") for col in chunk.columns]
#         # df = pd.read_csv(ruta_archivo, delimiter='\t', dtype=str, quoting=3, on_bad_lines='skip', engine='python')
#         # df = pd.read_csv(ruta_archivo, delimiter='\t', dtype=str, quoting=3, on_bad_lines='skip')

#         if "gbifID" not in chunk.columns:
#             raise ValueError("El archivo debe contener la columna 'gbifID'.")

#         # Cargar datos principales
#         # df = pd.read_csv(ruta_archivo, delimiter='\t', dtype=str, quoting=3, on_bad_lines='skip')
#         # df.columns = [col.strip().replace(" ", "_").replace("-", "_") for col in df.columns]
#         # if "gbifID" not in df.columns:
#         #     raise ValueError("El archivo debe contener la columna 'gbifID'.")


#         # Filtrar solo las columnas deseadas + gbifID
#         columnas_a_usar = [col for col in columnas_deseadas if col in chunk.columns]
#         columnas_a_usar_create = [col for col in columnas_deseadas if col in chunk.columns and col != 'gbifID']
#         # df_geom = df[columnas_a_usar].copy()
#         # df = df[columnas_a_usar]

#         # Eliminar registros donde latitud o longitud sean nulos
#         chunk = chunk.dropna(subset=["decimalLatitude", "decimalLongitude"])

#         # Crear tabla de geometrías si no existe
#         columns_sql = ', '.join([f'"{col}" TEXT' for col in columnas_a_usar_create if col not in ['decimalLatitude', 'decimalLongitude']])
#         create_table_sql = f"""
#         CREATE TABLE IF NOT EXISTS gbif (
#             id SERIAL PRIMARY KEY,
#             "gbifID" TEXT UNIQUE,
#             {columns_sql},
#             geom GEOMETRY(Point, 4326)
#         );
#         """

#         # print("create: gbif_table:")
#         # print(create_table_sql)

#         cur.execute(create_table_sql)
#         conn.commit()

#         # Insertar datos
#         insert_columns = [col for col in columnas_a_usar if col not in ['decimalLatitude', 'decimalLongitude']]
        
#         # placeholders = ', '.join(['%s'] * (len(insert_columns) + 1))  # +1 para geom
#         # insert_sql = f"""
#         # INSERT INTO gbif ({" ,".join(['"' + c + '"' for c in insert_columns])}, geom)
#         # VALUES ({placeholders})
#         # ON CONFLICT ("gbifID") DO NOTHING;
#         # """

#         # print("insert_sql:")
#         # print(insert_sql)


#         batch_size = 1000
#         batch = []

#         for idx, row in chunk.iterrows():
#             try:
#                 lat = float(row["decimalLatitude"])
#                 lon = float(row["decimalLongitude"])
#                 geom = f'SRID=4326;POINT({lon} {lat})'
#                 values = [row[col] for col in insert_columns] + [geom]
#                 batch.append(values)

#                 if len(batch) >= batch_size:
#                     args_str = ','.join(cur.mogrify(f"({','.join(['%s'] * (len(insert_columns)))}, ST_GeomFromText(%s, 4326))", x).decode('utf-8') for x in batch)
#                     cur.execute(f"""INSERT INTO gbif ({', '.join(f'"{c}"' for c in insert_columns)}, geom) VALUES {args_str} ON CONFLICT ("gbifID") DO NOTHING;""")
#                     conn.commit()
#                     batch = []

#             except Exception as e:
#                 logger.warning(f"Registro omitido en índice {idx} por error: {e}")

#         # Insertar el último batch
#         if batch:
#             args_str = ','.join(cur.mogrify(f"({','.join(['%s'] * (len(insert_columns)))}, ST_GeomFromText(%s, 4326))", x).decode('utf-8') for x in batch)
#             cur.execute(f"""INSERT INTO gbif ({', '.join(f'"{c}"' for c in insert_columns)}, geom) VALUES {args_str} ON CONFLICT ("gbifID") DO NOTHING;""")
#             conn.commit()

#     logger.info('Se insertaron las ocurrencias con geometrías correctamente.')
#     cur.close()
#     conn.close()
     
# except Exception as err:
    
#     logger.error('No se crearon correctamente las variables bioticas: {0}'.format(str(err)))
#     err_type, err_obj, traceback = sys.exc_info()
#     line_num = traceback.tb_lineno
#     print ("\nERROR:", err, "on line number:", line_num)
#     print ("traceback:", traceback, "-- type:", err_type)
#     sys.exit()





# # Construyendo y llenando tabla sp_gbif
# try:
#     conn = psycopg2.connect('dbname={0} host={1} port={2} user={3} password={4}'.format(DBNICHENAME, DBNICHEHOST, DBNICHEPORT, DBNICHEUSER, DBNICHEPASSWD))
#     conn.set_isolation_level(ISOLATION_LEVEL_AUTOCOMMIT)

#     cur = conn.cursor()
#     logger.info('Creación de tabla de registros catalogo')

#     create_table_sql = """
#     DROP TABLE IF EXISTS sp_gbif;
#     CREATE TABLE sp_gbif (
#         id_especie SERIAL PRIMARY KEY,
#         "scientificName" TEXT,
#         kingdom TEXT,
#         phylum TEXT,
#         class TEXT,
#         "order" TEXT,
#         family TEXT,
#         genus TEXT,
#         species TEXT,
#         "specificEpithet" TEXT,
#         "taxonID" TEXT,
#         "taxonRank" TEXT, 
#         "taxonomicStatus" TEXT
#     );
#     """
#     cur.execute(create_table_sql)
#     logger.info("Tabla sp_gbif creada correctamente.")


#     logger.info("Insertando especies únicas desde informacion_gbif...")

#     insert_sql = """
#     INSERT INTO sp_gbif ("scientificName", kingdom, phylum, class, "order", family, genus, species, "specificEpithet", "taxonID" , "taxonRank" , "taxonomicStatus")
#     SELECT DISTINCT "scientificName", kingdom, phylum, class, "order", family, genus, species, "specificEpithet", "taxonID" , "taxonRank" , "taxonomicStatus"
#     FROM gbif;
#     """
#     cur.execute(insert_sql)

#     cur.close()
#     conn.close()
#     logger.info("Se insertaron las especies únicas correctamente.")
    
            
# except Exception as err:
    
#     logger.error('No se crearon correctamente las especies únicas: {0}'.format(str(err)))
#     err_type, err_obj, traceback = sys.exc_info()
#     line_num = traceback.tb_lineno
#     print ("\nERROR:", err, "on line number:", line_num)
#     print ("traceback:", traceback, "-- type:", err_type)
#     sys.exit()


# Ultimos ajustes sobre poblado de tablas gbif y sp_gbif
try:
    conn = psycopg2.connect('dbname={0} host={1} port={2} user={3} password={4}'.format(DBNICHENAME, DBNICHEHOST, DBNICHEPORT, DBNICHEUSER, DBNICHEPASSWD))
    conn.set_isolation_level(ISOLATION_LEVEL_AUTOCOMMIT)

    cur = conn.cursor()

    
    # logger.info("Creando columnas para almancenar id_especie en tabla gbif")

    # sql = """
    # ALTER TABLE gbif ADD COLUMN IF NOT EXISTS id_especie int;
    # CREATE INDEX IF NOT EXISTS idx_gbif_idespecie ON gbif(id_especie);
    # """
    # cur.execute(sql)


    # logger.info("Creando indice para columnas multiples en gbif")

    # sql = """
    # CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_gbif_taxonomia
    # ON gbif(kingdom, phylum, "class", "order", "family", genus, species)
    # WHERE id_especie IS NULL;
    # """
    # cur.execute(sql)


    # logger.info("Creando indice para filtro en gbif")

    # sql = """
    # CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_gbif_id_especie_null
    # ON gbif(id_especie)
    # WHERE id_especie IS NULL;
    # """
    # cur.execute(sql)


    # logger.info("Creando un índice multicolumna para la tabla de referencia en sp_gbif")

    # sql = """
    # CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_sp_gbif_taxonomia
    # ON sp_gbif(kingdom, phylum, "class", "order", "family", genus, species);
    # """
    # cur.execute(sql)


    # sql = """
    # UPDATE gbif t0 SET id_especie = t1.id_especie FROM sp_gbif AS t1 WHERE t0.kingdom = t1.kingdom AND t0.phylum = t1.phylum AND t0."class" = t1."class" AND t0."order" = t1."order" AND t0."family" = t1."family" AND t0.genus = t1.genus AND t0.species = t1.species AND t0.id_especie IS NULL;
    # """
    # cur.execute(sql)

    logger.info("Asignando id_especie a tabla gbif en bloques")
    
    BATCH_SIZE = 1000
    total_updated = 0

    while True:
        
        print("Ejecutando siguiente lote...")

        update_query = """
            WITH rows_to_update AS (
                SELECT t0.ctid AS ctid
                FROM gbif t0
                JOIN sp_gbif t1 ON
                    t0.kingdom = t1.kingdom AND
                    t0.phylum = t1.phylum AND
                    t0."class" = t1."class" AND
                    t0."order" = t1."order" AND
                    t0."family" = t1."family" AND
                    t0.genus = t1.genus AND
                    t0.species = t1.species
                WHERE t0.id_especie IS NULL
                LIMIT %s
            )
            UPDATE gbif t0
            SET id_especie = t1.id_especie
            FROM sp_gbif t1, rows_to_update r
            WHERE t0.ctid = r.ctid AND
                  t0.kingdom = t1.kingdom AND
                  t0.phylum = t1.phylum AND
                  t0."class" = t1."class" AND
                  t0."order" = t1."order" AND
                  t0."family" = t1."family" AND
                  t0.genus = t1.genus AND
                  t0.species = t1.species;
            """

        cur.execute(update_query, (BATCH_SIZE,))
        rows_affected = cur.rowcount

        if rows_affected == 0:
            print("No hay más registros por actualizar.")
            break

        conn.commit()

        total_updated += rows_affected
        print(f"Actualizados {rows_affected} registros. Total acumulado: {total_updated}")

    cur.close()
    conn.close()
    logger.info("Se creo y lleno columna id_especie en tabla gbif")
    
            
except Exception as err:
    
    logger.error('No se crearon correctamente las especies únicas: {0}'.format(str(err)))
    err_type, err_obj, traceback = sys.exc_info()
    line_num = traceback.tb_lineno
    print ("\nERROR:", err, "on line number:", line_num)
    print ("traceback:", traceback, "-- type:", err_type)
    sys.exit()
    


# # Construyendo tabla catalogo cat_taxon
# try:
#     conn = psycopg2.connect('dbname={0} host={1} port={2} user={3} password={4}'.format(DBNICHENAME, DBNICHEHOST, DBNICHEPORT, DBNICHEUSER, DBNICHEPASSWD))
#     conn.set_isolation_level(ISOLATION_LEVEL_AUTOCOMMIT)

#     cur = conn.cursor()
#     logger.info('Creación de tabla catalogo')

    

#     create_snib_table_sql = get_sql(create_snib_table)
#     create_sp_snib_table_sql = get_sql(create_sp_snib_table)
#     # create_geo_snib_table_sql = get_sql(create_geo_snib_table)

#     logger.info('Creando tabla snib')
#     cur.execute(create_snib_table_sql)

#     logger.info('Creando tabla sp_snib')
#     cur.execute(create_sp_snib_table_sql)

#     # logger.info('Creando tabla geo_snib')
#     # cur.execute(create_geo_snib_table_sql)

#     cur.close()
#     conn.close()
#     logger.info('Se crearon las variables bioticas correctamente')
            
# except Exception as err:
    
#     logger.error('No se crearon correctamente las variables bioticas: {0}'.format(str(err)))
#     err_type, err_obj, traceback = sys.exc_info()
#     line_num = traceback.tb_lineno
#     print ("\nERROR:", err, "on line number:", line_num)
#     print ("traceback:", traceback, "-- type:", err_type)
#     sys.exit()



