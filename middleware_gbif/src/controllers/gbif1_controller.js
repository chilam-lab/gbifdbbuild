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


exports.get_data_byid = async function (req, res) {
  try {
    const variable_id   = Number(req.params.id);
    const grid_id       = verb_utils.getParam(req, 'grid_id', 1);
    const levels_id     = verb_utils.getParam(req, 'levels_id', []);
    const filter_names  = verb_utils.getParam(req, 'filter_names', []);
    const filter_values = verb_utils.getParam(req, 'filter_values', []);

    const SPID_BATCH     = 10;
    const WAVE_SIZE      = 10;
    const MAX_PTS_PER_ID = 10000;

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
        {in_fosil} {in_sin_fecha}
      GROUP BY id_especie, $<dic_taxon_group:raw>
      {min_occ}
    `;

    const snibParams = {
      dic_taxon_data:  dic_taxon_data.get(column_taxon),
      dic_taxon_group: dic_taxon_group.get(column_taxon),
    };

    for (let i = 0; i < filter_names.length; i++) {
      const filter_param = filter_names[i];
      const filter_value = filter_values[i];

      if (filter_param === 'min_occ') {
        const min = Number(filter_value);
        if (!Number.isFinite(min) || min < 0) {
          return res.status(400).json({ message: "min_occ debe ser un número >= 0" });
        }
        queryPts = queryPts.replace('{min_occ}',
          `HAVING array_length(array_agg(st_astext(geom)), 1) > ${Math.floor(min)}`);
      } else if (filter_param === 'in_fosil') {
        queryPts = queryPts.replace('{in_fosil}',
          filter_value ? '' : "AND ejemplarfosil = 'NO'");
      } else if (filter_param === 'in_sin_fecha') {
        queryPts = queryPts.replace('{in_sin_fecha}',
          filter_value ? '' : 'AND year IS NOT NULL');
      }
    }

    queryPts = queryPts.replace('{min_occ}', '').replace('{in_fosil}', '').replace('{in_sin_fecha}', '');

    // Fetch points in batches
    const idChunks = [];
    for (let i = 0; i < levels_id.length; i += SPID_BATCH) {
      idChunks.push(levels_id.slice(i, i + SPID_BATCH));
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
      return res.status(200).json([]);
    }

    const query_array = [];
    for (const row of datapoints) {
      if (!row.points || row.points.length === 0) continue;

      const uniquePts = [...new Set(row.points)];
      const pts = uniquePts.length > MAX_PTS_PER_ID
        ? uniquePts.sort(() => Math.random() - 0.5).slice(0, MAX_PTS_PER_ID)
        : uniquePts;

      const query_points = pts
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
          ON ST_Intersects(g.the_geom, p.geom)
        ORDER BY cell;
      `;

      query_temp = query_temp
        .replace('{query_points}', query_points)
        .replace('{res_column}', res_column)
        .replace('{table_cell_name}', table_cell_name);

      query_array.push({ query_temp, id_especie: row.id_especie, datos: row.datos });
    }

    const GRID_WAVE = 10;
    const results = [];
    for (let i = 0; i < query_array.length; i += GRID_WAVE) {
      const wave = query_array.slice(i, i + GRID_WAVE);
      const waveRows = await Promise.all(
        wave.map(({ query_temp }) =>
          pool_mallas.any(query_temp, {}).catch(err => { debug(err); return []; })
        )
      );
      results.push(...waveRows);
    }

    const response_array = query_array.map((q, idx) => {
      const cells = (results[idx] || []).map(r => r.cell);
      return {
        id:       variable_id,
        grid_id,
        level_id: q.id_especie,
        metadata: q.datos,
        cells,
        n: cells.length,
      };
    });

    return res.status(200).json(response_array);

  } catch (error) {
    debug(error);
    return res.status(500).json({ message: "Error interno en get_data_byid" });
  }
};
