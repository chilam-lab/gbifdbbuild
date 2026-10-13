var debug = require('debug')('verbs:controllers')
var verb_utils = require('./verb_utils')
var pgp = require('pg-promise')()
var config = require('../../config')

var pool = verb_utils.pool
var pool_mallas = verb_utils.pool_mallas

let dic_taxon_data = new Map();
dic_taxon_data.set('species','{"reino":"\'||kingdom||\'","phylum":"\'||phylum||\'","clase":"\'||"class"||\'","orden":"\'||"order"||\'", "familia":"\'||"family"||\'", "genero":"\'||genus||\'", "especie":"\'||species||\'"}')
dic_taxon_data.set('genus','{"reino":"\'||kingdom||\'","phylum":"\'||phylum||\'","clase":"\'||"class"||\'","orden":"\'||"order"||\'", "familia":"\'||"family"||\'", "genero":"\'||genus||\'"}')
dic_taxon_data.set('family','{"reino":"\'||kingdom||\'","phylum":"\'||phylum||\'","clase":"\'||"class"||\'","orden":"\'||"order"||\'", "familia":"\'||"family"||\'"}')
dic_taxon_data.set('order','{"reino":"\'||kingdom||\'","phylum":"\'||phylum||\'","clase":"\'||"class"||\'","orden":"\'||"order"||\'"}')
dic_taxon_data.set('class','{"reino":"\'||kingdom||\'","phylum":"\'||phylum||\'","clase":"\'||"class"||\'"}')
dic_taxon_data.set('phylum','{"reino":"\'||kingdom||\'","phylum":"\'||phylum||\'"}')
dic_taxon_data.set('kingdom','{"reino":"\'||kingdom||\'"}')

let dic_taxon_group = new Map();
dic_taxon_group.set('species','species, kingdom, phylum, "class", "order", "family", genus')
dic_taxon_group.set('genus','genus, kingdom, phylum, "class", "order", "family"')
dic_taxon_group.set('family','"family", kingdom, phylum, "class", "order"')
dic_taxon_group.set('order','"order", kingdom, phylum, "class"')
dic_taxon_group.set('class','"class", kingdom, phylum')
dic_taxon_group.set('phylum','phylum, kingdom')
dic_taxon_group.set('kingdom','kingdom')

let valid_filters = ["levels_id","reino","phylum","clase","orden","familia","genero","especie"]

let dic_taxon_db = new Map();
dic_taxon_db.set('levels_id','id_especie')
dic_taxon_db.set('especie','species')
dic_taxon_db.set('genero','genus')
dic_taxon_db.set('familia','"family"')
dic_taxon_db.set('orden','"order"')
dic_taxon_db.set('clase','"class"')
dic_taxon_db.set('phylum','phylum')
dic_taxon_db.set('reino','kingdom')


exports.variables = async function (req, res) {
  try {
    const data = await pool.any(
      `SELECT id, taxon AS variable, filter_fields, available_grids
       FROM cat_taxon
       ORDER BY id;`,
      {}
    );
    return res.status(200).json({ data });
  } catch (error) {
    debug(error);
    return res.status(500).json({ message: "Error interno al obtener el catálogo de variables" });
  }
};


exports.secuencia = async function (req, res) {
  try {
    const { variableLevel, variableValue, nextVariableLevel } = req.body || {};

    if (!variableLevel || !nextVariableLevel || variableValue === undefined || variableValue === null || variableValue === '') {
      return res.status(400).json({
        message: "Parámetros requeridos: variableLevel, variableValue, nextVariableLevel"
      });
    }

    if (!dic_taxon_db.has(variableLevel) || !dic_taxon_db.has(nextVariableLevel)) {
      return res.status(400).json({ message: "variableLevel o nextVariableLevel no son válidos" });
    }

    const currentColSql = dic_taxon_db.get(variableLevel);
    const nextColSql    = dic_taxon_db.get(nextVariableLevel);

    const query = `
      SELECT DISTINCT
        ${nextColSql} AS value,
        ${nextColSql} AS label
      FROM sp_gbif
      WHERE ${nextColSql} <> ''
        AND ${currentColSql} = $1
      ORDER BY ${nextColSql};
    `;

    const data = await pool.any(query, [variableValue]);
    return res.status(200).json({ data });

  } catch (error) {
    debug(error);
    return res.status(500).json({ message: "Error interno al obtener secuencia" });
  }
};


exports.get_sourceinfo = async function (req, res) {
  try {
    const data = await pool.oneOrNone(
      `SELECT name, description, source_url, download_url, dict_url
       FROM data_source_info
       ORDER BY updated_at DESC, id DESC
       LIMIT 1;`,
      {}
    );

    if (!data) {
      return res.status(404).json({ message: "No se encontró información de la fuente de datos" });
    }

    return res.status(200).json({ data });
  } catch (error) {
    debug(error);
    return res.status(500).json({ message: "Error interno al obtener información de la fuente de datos" });
  }
};


exports.get_variable_byid = async function (req, res) {
  try {
    const variable_id = Number(req.params.id);
    const q      = verb_utils.getParam(req, 'q', '');
    const offset = Number(verb_utils.getParam(req, 'offset', 0));
    const limit  = Number(verb_utils.getParam(req, 'limit', 10));

    const catRow = await pool.oneOrNone(
      'SELECT id, column_taxon_name FROM cat_taxon WHERE id = $1',
      [variable_id]
    );

    if (!catRow) {
      return res.status(404).json({ message: `variable_id ${variable_id} no existe` });
    }

    const column_taxon = catRow.column_taxon_name;
    // class/order/family are PostgreSQL reserved words — always quote as identifier
    const column_taxon_sql = `"${column_taxon}"`;

    const query_array = [];
    if (q !== '') {
      for (const filter of q.split(';')) {
        const [rawParam, rawValue] = filter.split('=');
        if (!rawParam || !rawValue) continue;

        const filter_param = rawParam.trim();
        if (!valid_filters.includes(filter_param)) continue;

        const values = rawValue.trim().split(',');
        const col = dic_taxon_db.get(filter_param);
        const clauses = values.map(v => {
          if (filter_param === 'levels_id') {
            return `${col} = ${v.trim()}`;
          }
          const safeValue = String(v.trim()).replace(/'/g, "''");
          if (filter_param === 'especie') {
            // exacto para no incluir subespecies
            return `lower(${col}) = lower('${safeValue}')`;
          }
          // prefijo para el resto de los niveles (mismo comportamiento que SNIB)
          return `lower(${col}) like lower('${safeValue}%')`;
        });
        query_array.push(`( ${clauses.join(' OR ')} )`);
      }
    }

    let query = `
      SELECT $<id:raw> AS id,
             array_agg(id_especie) AS level_id,
             ('$<dic_taxon_data:raw>')::jsonb AS datos
      FROM sp_gbif
      WHERE $<column_taxon_sql:raw> <> '' {filters}
      GROUP BY $<dic_taxon_group:raw>
      ORDER BY $<column_taxon_sql:raw>
      OFFSET $<offset:raw>
      LIMIT $<limit:raw>
    `;

    const filtersClause = query_array.length > 0
      ? ' AND ' + query_array.join(' AND ')
      : '';
    query = query.replace('{filters}', filtersClause);
    query = query.replace(/levels_id/g, 'id_especie');

    const data = await pool.any(query, {
      id:               catRow.id,
      column_taxon_sql,
      dic_taxon_data:   dic_taxon_data.get(column_taxon),
      dic_taxon_group:  dic_taxon_group.get(column_taxon),
      offset,
      limit,
    });

    return res.status(200).json({ data });

  } catch (error) {
    debug(error);
    return res.status(500).json({ message: "Error interno al obtener variables" });
  }
};


// Año del registro: year es texto ('2020'); NULL = registro sin fecha.
const GBIF_ANIO_SQL = `(CASE WHEN year ~ '^[0-9]{4}' THEN substr(year, 1, 4)::int END)`;

/**
 * filter_names/filter_values -> condiciones SQL sobre gbif (sin el AND).
 * Devuelve { conditions, minOcc, error }; minOcc es null si no se pidió.
 */
function gbifFilterConditions(filter_names, filter_values) {
  const conditions = [];
  let minOcc = null;
  for (let i = 0; i < filter_names.length; i++) {
    const filter_param = filter_names[i];
    const filter_value = filter_values[i];

    if (filter_param === 'min_occ') {
      const min = Number(filter_value);
      if (!Number.isFinite(min) || min < 0) return { error: "min_occ debe ser un número >= 0" };
      minOcc = Math.floor(min);
    } else if (filter_param === 'in_fosil') {
      // GBIF no tiene ejemplarfosil: los fósiles vienen como basisOfRecord.
      if (!filter_value) conditions.push(`"basisOfRecord" IS DISTINCT FROM 'FOSSIL_SPECIMEN'`);
    } else if (filter_param === 'in_sin_fecha') {
      if (!filter_value) conditions.push(`${GBIF_ANIO_SQL} IS NOT NULL`);
    } else if (filter_param === 'fecha_inicio' || filter_param === 'fecha_fin') {
      // Rango de años; los registros sin fecha los decide in_sin_fecha.
      if (filter_value === null || filter_value === undefined || filter_value === '') continue;
      const year = Number(filter_value);
      if (!Number.isInteger(year) || year < 0 || year > 9998) return { error: `${filter_param} debe ser un año válido` };
      const op = filter_param === 'fecha_inicio' ? '>=' : '<=';
      conditions.push(`(${GBIF_ANIO_SQL} IS NULL OR ${GBIF_ANIO_SQL} ${op} ${year})`);
    } else {
      return { error: `Filtro no válido: ${filter_param}` };
    }
  }
  return { conditions, minOcc, error: null };
}

/**
 * Registros del target dentro de una celda (popup del mapa de Target):
 * nombre, año y liga a la ficha en gbif.org. Mismos filtros que get-data.
 * Body: { grid_id, cell_id, levels_id, filter_names, filter_values, limit }
 */
exports.get_cell_occ = async function (req, res) {
  try {
    const grid_id = Number(verb_utils.getParam(req, 'grid_id', 0));
    const cell_id = Number(verb_utils.getParam(req, 'cell_id', NaN));
    const levels_id_raw = verb_utils.getParam(req, 'levels_id', []);
    const filter_names = verb_utils.getParam(req, 'filter_names', []);
    const filter_values = verb_utils.getParam(req, 'filter_values', []);
    const limit = Math.min(Math.max(Number(verb_utils.getParam(req, 'limit', 500)) || 500, 1), 2000);

    const levels_id = Array.isArray(levels_id_raw)
      ? levels_id_raw.map(Number).filter(n => Number.isInteger(n) && n > 0)
      : [];
    if (!Number.isInteger(grid_id) || grid_id <= 0 || !Number.isFinite(cell_id) || levels_id.length === 0) {
      return res.status(400).json({ message: 'Se requieren grid_id, cell_id y levels_id' });
    }
    if (!Array.isArray(filter_names) || !Array.isArray(filter_values) || filter_names.length !== filter_values.length) {
      return res.status(400).json({ message: 'filter_names y filter_values deben ser arreglos del mismo tamaño' });
    }
    const parsed = gbifFilterConditions(filter_names, filter_values);
    if (parsed.error) return res.status(400).json({ message: parsed.error });

    const gridInfo = await pool_mallas.oneOrNone(
      'SELECT resolution, table_cell_name FROM cat_grid WHERE grid_id = $1', [grid_id]
    );
    if (!gridInfo) return res.status(404).json({ message: 'No existe la malla solicitada (grid_id)' });

    const cell = await pool_mallas.oneOrNone(
      `SELECT ST_AsEWKB(the_geom) AS geom FROM ${gridInfo.table_cell_name} WHERE gridid_${gridInfo.resolution} = $1`,
      [cell_id]
    );
    if (!cell) return res.status(404).json({ message: 'No existe la celda en la malla' });

    const rows = await pool.any(
      `SELECT species AS nombre,
              ${GBIF_ANIO_SQL} AS anio,
              NULL::text AS fecha,
              'https://www.gbif.org/occurrence/' || "gbifID" AS url
       FROM gbif
       WHERE id_especie IN ($<ids:csv>)
         AND geom IS NOT NULL
         AND ST_Intersects(geom, ST_GeomFromEWKB($<geom>))
         ${parsed.conditions.map(c => ` AND ${c}`).join('')}
       ORDER BY nombre, anio DESC NULLS LAST
       LIMIT $<limit>`,
      { ids: levels_id, geom: cell.geom, limit: limit + 1 }
    );

    return res.status(200).json({
      cell_id,
      truncated: rows.length > limit,
      data: rows.slice(0, limit),
    });
  } catch (error) {
    debug(error);
    return res.status(500).json({ message: 'Error interno al obtener los registros de la celda' });
  }
};

exports.get_data_byid = async function (req, res) {
  try {
    const variable_id   = Number(req.params.id);
    const grid_id       = verb_utils.getParam(req, 'grid_id', 1);
    const levels_id     = verb_utils.getParam(req, 'levels_id', []);
    const filter_names  = verb_utils.getParam(req, 'filter_names', []);
    const filter_values = verb_utils.getParam(req, 'filter_values', []);
    // with_counts: agrega n_occ (registros con coordenadas que pasan los
    // filtros) a cada especie; lo usa el resumen del mapa de Target.
    const with_counts   = verb_utils.getParam(req, 'with_counts', false) === true;

    const SPID_BATCH     = 10;
    const WAVE_SIZE      = 10;

    const [catRow, gridInfo] = await Promise.all([
      pool.oneOrNone('SELECT id, column_taxon_name FROM cat_taxon WHERE id = $1', [variable_id]),
      pool_mallas.oneOrNone('SELECT resolution, table_cell_name FROM cat_grid WHERE grid_id = $1', [grid_id]),
    ]);

    if (!catRow) return res.status(404).json({ message: `variable_id ${variable_id} no existe` });
    if (!gridInfo) return res.status(404).json({ message: `grid_id ${grid_id} no existe` });

    const column_taxon = catRow.column_taxon_name;
    const { table_cell_name } = gridInfo;
    const res_column = `gridid_${String(gridInfo.resolution).toLowerCase()}`;

    let queryPts = `
      SELECT DISTINCT
        id_especie,
        array_agg(st_astext(geom)) AS points,
        ('$<dic_taxon_data:raw>')::jsonb AS datos
      FROM gbif s
      WHERE id_especie IN ($<spids:csv>)
        AND geom IS NOT NULL
        {filters}
      GROUP BY id_especie, $<dic_taxon_group:raw>
      {min_occ}
    `;

    const snibParams = {
      dic_taxon_data:  dic_taxon_data.get(column_taxon),
      dic_taxon_group: dic_taxon_group.get(column_taxon),
    };

    const parsed = gbifFilterConditions(filter_names, filter_values);
    if (parsed.error) {
      return res.status(400).json({ message: parsed.error });
    }
    const conditions = parsed.conditions;
    if (parsed.minOcc !== null) {
      queryPts = queryPts.replace('{min_occ}',
        `HAVING array_length(array_agg(st_astext(geom)), 1) > ${parsed.minOcc}`);
    }

    queryPts = queryPts
      .replace('{min_occ}', '')
      .replace('{filters}', conditions.map(c => ` AND ${c}`).join(''));

    // Cache: sp_gbif.cells_<resolucion> lo llena dbbuild/precompute_gbif_cells.py
    // y también el write-back de abajo. Solo es seguro sin filtros activos:
    // min_occ/in_sin_fecha cambian qué ocurrencias cuentan y el precálculo
    // asume la vista sin filtrar.
    const VALID_RESOLUTIONS = new Set(['64km', '32km', '16km', '8km', 'ageb', 'cue', 'mun', 'state']);
    const canUseCache = filter_names.length === 0 && VALID_RESOLUTIONS.has(String(gridInfo.resolution));
    const cellsColumn = `cells_${gridInfo.resolution}`;

    let cachedRows = [];
    let pendingLevelsId = levels_id;
    if (canUseCache && levels_id.length > 0) {
      cachedRows = await pool.any(
        `SELECT id_especie, ${cellsColumn} AS cells, ('$<dic_taxon_data:raw>')::jsonb AS datos
         FROM sp_gbif
         WHERE id_especie IN ($<spids:csv>) AND ${cellsColumn} IS NOT NULL`,
        { spids: levels_id, ...snibParams }
      ).catch(err => { debug('cache lookup:', err.message); return []; });
      cachedRows.forEach(r => { r.id_especie = Number(r.id_especie); });
      const cachedIds = new Set(cachedRows.map(r => r.id_especie));
      pendingLevelsId = levels_id.filter(id => !cachedIds.has(Number(id)));
    }

    const respond = async (rows) => {
      if (with_counts && rows.length > 0) {
        const counts = await pool.any(
          `SELECT id_especie, count(*)::int AS n_occ
           FROM gbif
           WHERE id_especie IN ($<ids:csv>) AND geom IS NOT NULL
           ${conditions.map(c => ` AND ${c}`).join('')}
           GROUP BY id_especie`,
          { ids: rows.map(r => r.level_id) }
        ).catch(err => { debug('counts:', err.message); return []; });
        const nById = new Map(counts.map(r => [Number(r.id_especie), r.n_occ]));
        rows.forEach(r => { r.n_occ = nById.get(Number(r.level_id)) ?? 0; });
      }
      return res.status(200).json(rows);
    };

    const cachedResponse = cachedRows.map(r => ({
      id:       variable_id,
      grid_id,
      level_id: r.id_especie,
      metadata: r.datos,
      cells:    r.cells || [],
      n:        (r.cells || []).length,
    }));

    // Fetch points in batches
    const idChunks = [];
    for (let i = 0; i < pendingLevelsId.length; i += SPID_BATCH) {
      idChunks.push(pendingLevelsId.slice(i, i + SPID_BATCH));
    }

    const datapoints = [];
    for (let i = 0; i < idChunks.length; i += WAVE_SIZE) {
      const wave = idChunks.slice(i, i + WAVE_SIZE);
      const waveRows = await Promise.all(
        wave.map(batch =>
          pool.any(queryPts, { spids: batch, ...snibParams })
            .catch(err => { debug('gbif batch:', err.message); return []; })
        )
      );
      datapoints.push(...waveRows.flat());
    }

    if (datapoints.length === 0) {
      return respond(cachedResponse);
    }

    // Todos los puntos únicos, sin muestreo: el resultado debe coincidir con
    // el precálculo (sp_gbif.cells_*) porque se guarda en el cache. Una
    // especie con más de MAX_PTS_PER_QUERY puntos se parte en varias
    // consultas y sus celdas se unen al final.
    const MAX_PTS_PER_QUERY = 20000;
    const species = [];
    const query_array = [];
    for (const row of datapoints) {
      if (!row.points || row.points.length === 0) continue;
      species.push(row);

      const pts = [...new Set(row.points)];
      for (let i = 0; i < pts.length; i += MAX_PTS_PER_QUERY) {
        const query_points = pts.slice(i, i + MAX_PTS_PER_QUERY)
          .map(wkt => `ST_SetSRID(ST_GeomFromText('${wkt}'), 4326)`)
          .join(', ');

        let query_temp = `
          WITH puntos AS (
            SELECT ARRAY[{query_points}] AS geom_array
          ),
          point_geom AS (
            SELECT unnest(geom_array) AS geom FROM puntos
          )
          SELECT DISTINCT {res_column} AS cell
          FROM point_geom p
          JOIN {table_cell_name} g
            ON ST_Intersects(g.the_geom, p.geom);
        `;

        query_temp = query_temp
          .replace('{query_points}', query_points)
          .replace('{res_column}', res_column)
          .replace('{table_cell_name}', table_cell_name);

        query_array.push({ query_temp, id_especie: row.id_especie });
      }
    }

    const GRID_WAVE = 25; // debe ser <= db_mallas.poolSize (config.js)
    const cellsById = new Map();   // id_especie -> Set de celdas
    const failedIds = new Set();   // algún trozo falló: resultado incompleto
    for (let i = 0; i < query_array.length; i += GRID_WAVE) {
      const wave = query_array.slice(i, i + GRID_WAVE);
      const waveRows = await Promise.all(
        wave.map(({ query_temp, id_especie }) =>
          pool_mallas.any(query_temp, {}).catch(err => {
            debug(err);
            failedIds.add(id_especie);
            return [];
          })
        )
      );
      waveRows.forEach((rows, idx) => {
        const id = wave[idx].id_especie;
        if (!cellsById.has(id)) cellsById.set(id, new Set());
        rows.forEach(r => cellsById.get(id).add(r.cell));
      });
    }

    const response_array = species.map(row => {
      const cells = [...(cellsById.get(row.id_especie) || [])].sort((a, b) => a - b);
      return {
        id:       variable_id,
        grid_id,
        level_id: row.id_especie,
        metadata: row.datos,
        cells,
        n: cells.length,
      };
    });

    // Write-back: guarda lo calculado en vivo para que la próxima consulta de
    // la misma especie/resolución salga del cache. No bloquea la respuesta.
    // Solo especies cuyas consultas terminaron todas: un resultado incompleto
    // no debe quedar en cache.
    if (canUseCache) {
      Promise.all(response_array
        .filter(r => !failedIds.has(r.level_id))
        .map(r => pool.none(
          `UPDATE sp_gbif SET ${cellsColumn} = $<cells>::integer[] WHERE id_especie = $<id>`,
          { cells: r.cells, id: r.level_id }
        ).catch(err => debug('cache write-back:', err.message)))
      ).catch(() => {});
    }

    return respond(cachedResponse.concat(response_array));

  } catch (error) {
    debug(error);
    return res.status(500).json({ message: "Error interno en get_data_byid" });
  }
};
