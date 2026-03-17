var debug = require('debug')('verbs:auth')
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
dic_taxon_db.set("familia",'\"family\"')
dic_taxon_db.set('orden','\"order\"')
dic_taxon_db.set('clase','\"class\"')
dic_taxon_db.set('phylum','\"phylum\"')
dic_taxon_db.set('reino','kingdom')

exports.variables = function(req, res) {

	let { } = req.body;

	// Se recomienda agregar la columna available_grids a este catalogo con ayuda de los servicios disponibles del proyecto regionmiddleware
	// const query = `SELECT id, description as variable, level_size, filter_fields, available_grids FROM cat_taxon order by id;`

	const query = `SELECT id, description as variable, filter_fields, available_grids
			FROM cat_taxon order by id;`

	pool.any(query, {}).then( 
		function(data) {
			// debug(data);
		res.status(200).json({
			data: data
		})
  	})
  	.catch(error => {
      debug(error)
      res.status(403).json({
      	message: "error al obtener catalogo", 
      	error: error
      })
   	});
}


exports.get_variable_byid = function(req, res) {

	let variable_id = req.params.id
	debug("variable_id: " + variable_id)

	let q = verb_utils.getParam(req, 'q', '')
	let offset = verb_utils.getParam(req, 'offset', 0)
	let limit = verb_utils.getParam(req, 'limit', 10)

	debug("q: " + q)
	debug("offset: " + offset)
	debug("limit: " + limit)

	let query_array = []
	
	let filter_separator = ";"
	let pair_separator = "="
	let group_separator = ","

	// q: "levels_id = 310245,265492; familia = Acanthaceae"
	
	if(q != ""){

		let array_queries = q.split(filter_separator)
		debug(array_queries)

		if(array_queries.length == 0){
			debug("Sin filtros definidos")
		}
		else{
			array_queries.forEach((filter, index) => {

				let filter_pair = filter.split(pair_separator)
				debug(filter_pair)

				if(filter_pair.length == 0){
					debug("Filtro indefinido")
				}
				else{
					
					let filter_param = filter_pair[0].trim()
					// debug("filter_param: " + filter_param)

					// TODO:Revisar por que no jala en enalce del mapa con su llave valor
					// debug(dic_taxon_db.keys())
					// debug("dic_taxon_db: " + dic_taxon_db.get(filter_param))
					

					if(valid_filters.indexOf(filter_param) == -1){
						debug("Filtro invalido")
					}
					else{
						
						if(filter_pair.length != 2){
							debug("Filtro invalido por composición")
						}
						else{
							let filter_value = filter_pair[1].trim().split(group_separator)	
							
							let query_temp = "( "
							filter_value.forEach((value, index) => {

								if(filter_param !== "levels_id"){
									value = "'" + value + "'"
								}
								
								if(index == 0){
									query_temp = query_temp + dic_taxon_db.get(filter_param) + " = " + value
								}
								else{
									query_temp = query_temp + " or " + dic_taxon_db.get(filter_param) + " = " + value + " "
								}

							})
							query_temp = query_temp + " )"
							query_array.push(query_temp)

						}

					}

				}

			})	

			debug(query_array)

		}

	}


	pool.task(t => {

		return t.one(
			"select id, column_taxon_name from cat_taxon where id = $<variable_id:raw>", {
				variable_id: variable_id
			}	
		).then(resp => {

			let column_taxon = resp.column_taxon_name
			debug("column_taxon: " + column_taxon)

			let id = resp.id
			debug("id variable: " + id)
		
			let query = `select $<id:raw> as id, array_agg(id_especie) as level_id, ('$<dic_taxon_data:raw>')::jsonb as datos
				from sp_gbif
				where $<column_taxon:raw> <> {queries}
				group by $<dic_taxon_group:raw>
				order by $<column_taxon:raw>
				offset $<offset:raw>
				limit $<limit:raw>`
				// '' and "scientificName" not like '%BOLD:%'

			query_array.forEach((query_temp, index) => {
				
				query = query.replace("{queries}", " and " + query_temp + " {queries} ")

			})

			query = query.replace("{queries}", "")
			query = query.replace(/levels_id/g, "id_especie")
			
			debug(query)
				
			return t.any(query, {
					id: id,
					column_taxon:column_taxon,
					dic_taxon_data:dic_taxon_data.get(column_taxon),
					dic_taxon_group: dic_taxon_group.get(column_taxon),
					offset: offset,
					limit: limit
				}	

			).then(resp => {

				res.status(200).json({
					data: resp
				})

			}).catch(error => {
		      debug(error)
		      res.status(403).json({
		      	error: "Error al obtener la malla solicitada", 
		      	message: "error al obtener datos"
		      })
		   	})

		}).catch(error => {
	      debug(error)

	      res.status(403).json({	      	
	      	error: "Error al obtener la malla solicitada", 
	      	message: "error al obtener datos"
	      })
	   	})

	}).catch(error => {
      debug(error)
      res.status(403).json({
      	message: "error general", 
      	error: error
      })
   	});
  	
}


exports.get_data_byid = function(req, res) {

	let variable_id = req.params.id
	debug("variable_id: " + variable_id)

	let grid_id = verb_utils.getParam(req, 'grid_id', 1)
	debug("grid_id: " + grid_id)

	let levels_id = verb_utils.getParam(req, 'levels_id', [])
	// debug("levels_id: " + levels_id)

	let filter_names = verb_utils.getParam(req, 'filter_names', [])
	debug(filter_names)

	let filter_values = verb_utils.getParam(req, 'filter_values', [])
	debug(filter_values)

	// TODO: validaciones para verificar los filtros
	let filter_array = []

	if(filter_names.length > 0){
		filter_names.forEach((filter_name, index) => {
			let filter_temp = {}
			filter_temp = {filter_param: filter_name, filter_value: filter_values[index]}
			filter_array.push(filter_temp)
		})
	}
	// debug(filter_array)
	
	pool.task(t => {

		return t.one(
			"select id, column_taxon_name from cat_taxon where id = $<variable_id:raw>", {
				variable_id: variable_id
			}	
		).then(resp => {

			let column_taxon = resp.column_taxon_name
			debug("column_taxon: " + column_taxon)
			debug("json: " + dic_taxon_data.get(column_taxon))
			debug("json: " + dic_taxon_group.get(column_taxon))


			let query = `select distinct id_especie, array_agg(st_astext(geom)) as points, ('$<dic_taxon_data:raw>')::jsonb as datos 
					from gbif s
					where id_especie in ($<spids:raw>)  
					and geom is not null {in_fosil} {in_sin_fecha}
					group by id_especie, $<dic_taxon_group:raw> {min_occ}`
			
			filter_array.forEach((filter_item) => {

				let filter_query = ""

				switch (filter_item.filter_param) {
				    
				    case "min_occ":
				        debug("min_occ");

						filter_query = " having array_length(array_agg(st_astext(geom)),1) > " + filter_item.filter_value + " "
						query = query.replace("{min_occ}", filter_query)
				        
				        break;

				    case "in_fosil":
				        debug("Incluir registros fosil");

				        if(filter_item.filter_value){
				        	filter_query = " "	
				        }
				        else{
				        	filter_query = " and ejemplarfosil = 'NO' "		
				        }

						query = query.replace("{in_fosil}", filter_query)
				        
				        break;

				    case "in_sin_fecha":
				    	debug("Incluir registros sin fecha");

				    	if(filter_item.filter_value){
				        	filter_query = " "
				        }
				        else{
				        	// filter_query = " and (fechacolecta is not null and fechacolecta <> '9999-99-99') "
				        	filter_query = " and year is not null "
				        }

				        query = query.replace("{in_sin_fecha}", filter_query)
				        
				        break;

				    default:
				        console.log("Filtro no valido: " + filter_item.filter_param);
				}
				
			})

			query = query.replace("{min_occ}", "")
			query = query.replace("{in_fosil}", "")
			query = query.replace("{in_sin_fecha}", "")

			debug("query: " + query)

			return t.any(query, {
					spids: levels_id.toString(),
					dic_taxon_data:dic_taxon_data.get(column_taxon),
					dic_taxon_group: dic_taxon_group.get(column_taxon)
				}	
			).then(resp => {

				debug(resp)

				let datapoints = resp
				let response_array = []
				let cells = []
				let query_array = []

				if (datapoints == null || datapoints.length == 0) {

					response_array.push({
						id: variable_id,
						grid_id: grid_id,
						cells: [],
						n: 0,
						message: "No hay datos para esta solicitud"
					})

					res.status(404).json(
						response_array
					)

				}

				datapoints.forEach((points_byspid) => {
					
					let query_temp = ""
					let query_points = ""

					if(points_byspid.points == null || points_byspid.points.length == 0){
						debug("el " + points_byspid.spid + " no tiene occurrencias registradas")
						return
					}

					points_byspid.points.forEach((point, index) => {

						if(index==0){
							query_points = query_points + " ST_SetSRID(ST_GeomFromText('" + point + "'), 4326)"	
						}
						else{
							query_points = query_points + ", ST_SetSRID(ST_GeomFromText('" + point + "'), 4326)"
						}
						
					})

					query_temp = `WITH puntos AS (
						    SELECT ARRAY[{query_points}] AS geom_array
						),
						point_geom as (
							SELECT unnest(geom_array) as geom 
							from puntos as p
						)
						select distinct g.gridid_64km as cell
						from point_geom as p
						join grid_64km_aoi as g 
						ON ST_Intersects(g.the_geom, p.geom)
						order by cell;`

					query_temp = query_temp.replace("{query_points}", query_points)
					query_array.push({query_temp: query_temp, spid: points_byspid.spid, datos: points_byspid.datos}) 
					
				})

				debug(query_array)

				
				// contrucción de respuesta
				let peticiones = query_array.length
				

				query_array.forEach((query_str) => {

					pool_mallas.task(t => {

						return t.any(
							query_str.query_temp, {}	
						).then(resp => {

							// enviando respuesta hasta que se reciban todas las peticiones del array
							peticiones = peticiones - 1

							// agrupacion de celdas de la respuesta del query
							let cells = resp.map(obj => {
							  return obj.cell
							});

							response_array.push({
								id: variable_id,
								grid_id: grid_id,
								level_id: query_str.spid,
								metadata: query_str.datos,
								cells: cells,
								n: cells.length
							})

							if(peticiones == 0){
								res.status(200).json(
									response_array
								)
							}
							
							
						})
					}).catch(error => {
				      debug(error)
				      peticiones = peticiones - 1
				      // res.status(403).json({
				      // 	message: "error general", 
				      // 	error: error
				      // })
				   	});

				})
				

			}).catch(error => {
		      debug(error)

		      res.status(403).json({	      	
		      	error: "Error al obtener la malla solicitada", 
		      	message: "error al obtener datos"
		      })
		   	})





		}).catch(error => {
	      debug(error)

	      res.status(403).json({	      	
	      	error: "Error al obtener la malla solicitada", 
	      	message: "error al obtener datos"
	      })
	   	})


		


	}).catch(error => {
      debug(error)
      res.status(403).json({
      	message: "error general", 
      	error: error
      })
   	});	
  	
}
