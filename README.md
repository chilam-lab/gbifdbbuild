# Proyecto gbifdbbuild

El proyecto **gbifdbbuild** se compone de dos elementos:

1. `dbbuild`: conjunto de scripts para construir la fuente de datos GBIF en PostgreSQL/PostGIS.
2. `middleware_gbif`: API REST que expone esa fuente de datos siguiendo el estándar de entrega definido en [species_v3.0](https://github.com/chilam-lab/species_v3.0).

Este README se organizó tomando como referencia la estructura de:  
https://github.com/chilam-lab/speciesdbbuild

---

## dbbuild - Sistema de Construcción de Fuente de Datos GBIF

`dbbuild` es el módulo encargado de cargar y transformar ocurrencias bióticas provenientes de GBIF (archivo tipo DwC, por ejemplo `occurrence.txt`) para generar las tablas y funciones que consume el middleware.

Referencia GBIF: https://www.gbif.org/es/

---

## Objetivo del Proyecto

Construir una base de datos PostgreSQL/PostGIS con:

- ocurrencias georreferenciadas de GBIF,
- catálogo taxonómico único,
- funciones y procedimientos SQL para consultas por niveles taxonómicos y agregación espacial,
- estructura compatible con el ecosistema SPECIES v3.0.

---

## Estructura del Proyecto (`dbbuild`)

```text
dbbuild/
├── build_gbifdb.py                    # Script principal del pipeline
├── aux_functions.py                   # Logger y utilidades auxiliares
├── data/
│   ├── columns.txt                    # Columnas esperadas para la carga
│   ├── 0010157-250415084134356.zip    # Ejemplo de descarga masiva GBIF
│   ├── MX_plantae/
│   ├── MX_fungi/
│   └── EU_viruses/
└── sql/
    ├── create_extensions.sql
    ├── create_aoi_table.sql
    ├── geom_aoi.sql
    ├── get_aoi.sql
    ├── create_cat_taxon.sql
    ├── create_snib_table.sql
    ├── create_sp_snib_table.sql
    ├── stored_procedures/
    │   ├── funciones_de_malla.sql
    │   ├── man_insert_raster_cells.sql
    │   ├── get_score.sql
    │   ├── get_epsilon.sql
    │   ├── aggr_array_cat.sql
    │   └── array_intersection.sql
    └── stored_validation/
        ├── create_temp_table_for_validation.sql
        ├── create_temp_table_taxons_grop_validation.sql
        ├── delete_temp_table_for_validation.sql
        ├── iterate_validation_process.sql
        ├── iterate_validation_process_by_cells.sql
        └── iterate_validation_process_by_decil.sql
```

---

## Flujo General del Pipeline (`build_gbifdb.py`)

El script está organizado para ejecutar (según la etapa habilitada):

1. Carga de variables de entorno (`python-dotenv`) para conexión a PostgreSQL.
2. Instalación de extensiones geoespaciales (PostGIS y relacionadas).
3. Creación/carga de tablas base y catálogos.
4. Carga de ocurrencias GBIF en bloques (`chunks`) desde archivo tabular.
5. Construcción de geometrías `POINT` (`SRID=4326`) a partir de latitud/longitud.
6. Creación de tabla taxonómica única (`sp_gbif`) y relación con `gbif`.
7. Actualización por lotes de `id_especie` en `gbif`.
8. Carga de stored procedures y scripts de validación.

Nota: en el script actual hay secciones comentadas para habilitar/inhabilitar etapas según volumen de datos o fase de construcción.

---

## Tablas de Trabajo Relevantes

- `gbif`: ocurrencias georreferenciadas de GBIF.
- `sp_gbif`: catálogo taxonómico único derivado de `gbif`.
- `cat_taxon`: catálogo de niveles taxonómicos y filtros disponibles para el API.

---

## Variables de Entorno (`dbbuild/.env`)

Configurar al menos:

```dotenv
DBNICHENAME=tu_base
DBNICHEHOST=tu_host
DBNICHEPORT=5432
DBNICHEUSER=tu_usuario
DBNICHEPASSWD=tu_password
```

---

## Ejecución de `dbbuild`

```bash
cd dbbuild
python3 build_gbifdb.py
```

---

## Requisitos de `dbbuild`

- Python 3.9+
- PostgreSQL 14+
- Extensiones PostgreSQL:
  - `postgis`
  - `postgis_raster`
  - `postgis_topology`
- Librerías Python:
  - `psycopg2`
  - `pandas`
  - `shapely`
  - `python-dotenv`

---

## middleware_gbif - API REST de la Fuente GBIF

`middleware_gbif` expone la información construida por `dbbuild` bajo el estándar de interoperabilidad de [species_v3.0](https://github.com/chilam-lab/species_v3.0).

---

## Descripción general

Este servicio implementa:

- API REST con Node.js + Express,
- conexión a base principal y base de mallas,
- endpoints para catálogo de variables, niveles taxonómicos y agregación espacial por malla,
- salida en formato compatible con consumidores SPECIES.

---

## Estructura del Proyecto (`middleware_gbif`)

```text
middleware_gbif/
├── src/
│   ├── server.js                       # Arranque del servidor Express
│   ├── routes/
│   │   └── gbif1router.js             # Rutas /gbif1
│   └── controllers/
│       ├── gbif1_controller.js        # Lógica principal de endpoints
│       └── verb_utils.js              # Pool de conexiones y utilidades
├── api/swagger/
│   ├── SPECIES-API.yaml
│   ├── SPECIES-API_2.yaml
│   ├── swagger.yaml
│   └── swagger_dos.yaml
├── config.js                           # Configuración por variables de entorno
├── package.json
└── README.md
```

---

## Endpoints principales

Prefijo base: `/gbif1`

- `GET /gbif1/variables`  
  Devuelve catálogo de variables (`cat_taxon`).

- `GET /gbif1/variables/:id`  
  Devuelve niveles taxonómicos por variable, con filtros opcionales (`q`, `offset`, `limit`).

- `GET /gbif1/get-data/:id`  
  Devuelve celdas de malla por especie/nivel (`grid_id`, `levels_id`, `filter_names`, `filter_values`).

---

## Variables de Entorno (`middleware_gbif`)

Definir en un archivo `.env` dentro de `middleware_gbif` (ejemplo mínimo):

```dotenv
PORT=8089
DBNAME=tu_base_gbif
DBUSER=tu_usuario
DBPWD=tu_password
DBHOST=tu_host
DBPORT=5432

DBNAME_MALLAS=tu_base_mallas
DBUSER_MALLAS=tu_usuario_mallas
DBPWD_MALLAS=tu_password_mallas
DBHOST_MALLAS=tu_host_mallas
DBPORT_MALLAS=5432
```

---

## Instalación y ejecución del middleware

```bash
cd middleware_gbif
npm install
npm start
```

Por defecto, el servidor arranca en el puerto `8089` según `src/server.js`.

---

## Estructura General del Repositorio

```text
gbifdbbuild/
├── dbbuild/           # Construcción y carga de base de datos GBIF
├── middleware_gbif/   # API REST compatible con species_v3.0
└── README.md
```

---

## Referencias

- GBIF (sitio oficial): https://www.gbif.org/es/
- Estándar SPECIES v3.0: https://github.com/chilam-lab/species_v3.0
- README de referencia (estructura): https://github.com/chilam-lab/speciesdbbuild
