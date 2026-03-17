CREATE OR REPLACE FUNCTION public.iteratevalidationprocessbycells(iterations integer, in_spid integer, in_n text, in_alpha numeric, in_minocc integer, in_erased_points integer[], in_cells text, in_grids text, in_cells_tbl text, where_target_bio text, where_target_abio text, type_process text, time_filter boolean, case_filter integer, lim_inf integer, lim_sup integer, in_getrecall boolean, fossil text, tblname text)
 RETURNS TABLE(out_cell integer, out_ni integer, out_score numeric, iter integer, type_value character varying)
 LANGUAGE plpgsql
AS $function$ 
declare 
	
	lista_gridids int[];
	lista_grid_total int[];
	
	lista_grid_total_dicarded int[];
	lista_grid_especie int[];
	lista_gridids_seccion_sp int[];
	
	array_size_tot int;
	array_size_sp int;	
	counter INTEGER := 0;
	res_n integer = 0;
	new_alpha numeric = 0.0;
	
	lista_cell_mx int[];
	
	
begin
	raise notice 'INICIA STORE: iteratevalidationprocessbycells';
	
	-- Tabla donde se retornan los resultados del store procedure
	DROP TABLE IF exists temp_cell;
	create TEMP TABLE temp_cell(
				gridid int,
				ni int,
				score numeric,
				iter int,
				type_value varchar(5));
	
	
	LOOP EXIT WHEN counter = iterations;
 		 
 		-- raise notice 'ITERACION %', (counter+1);
 		
 		case when iterations > 1 then
 		
 			-- obtiene las celdas de prueba para cada iteración de la tabla temporal generada por el store procedure: createtemptableforvalidation utilizada cuando se realiza el proceso de validación
 			execute format('select array_agg(cell)
							from(
								select cell
								from %s
								where iter = $1 and tipo_valor = ''test'' and sp_obj = FALSE
								order by cell
							) as t1
							group by true', tblname)
							using counter+1
 							into lista_gridids;
 							
 			-- obtiene las celdas de prueba de la especie objetivo para cada iteración de la tabla temporal generada por el store procedure: createtemptableforvalidation utilizada cuando se realiza el proceso de validación
 			execute format('select array_agg(cell)
							from(
								select cell
								from %s
								where iter = $1 and tipo_valor = ''test'' and sp_obj = TRUE
								order by cell
							) as t1
							group by true', tblname)
							using counter+1
 							into lista_gridids_seccion_sp;
 			
				
			-- se agregan celdas que fueron descartadas por selección de puntos
			lista_gridids := lista_gridids + in_erased_points;
			lista_grid_total_dicarded := lista_gridids + lista_gridids_seccion_sp;
			
			
		else 
		
			-- se asignan arreglos vacios cuando no es ejecutado el proceso de validación y se añaden caldas descartadas por selección de puntos
			lista_gridids := array[]::integer[];
			lista_gridids_seccion_sp := in_erased_points;
			lista_grid_total_dicarded := lista_gridids;
			
		end case;
		
		raise notice 'lista_gridids: %', lista_gridids;
		raise notice 'lista_gridids_seccion_sp: %', lista_gridids_seccion_sp;
		
		
		execute format('select array_agg(%s)  
						FROM america as ame
						join %s as grid
						on st_intersects(ame.geom, grid.the_geom)
						where gid = 19
						group by true', in_grids, in_cells_tbl)
						into lista_cell_mx;
			
		
		-- 	***** CALCULANDO VALORES CON EL CONJUNTO DE ENTRENAMIENTO *****
		
		-- caso 1: aniocolecta is not null
		-- caso 2: aniocolecta >= $3 and aniocolecta <= $4
		-- caso 3: (aniocolecta >= $3 and aniocolecta <= $4) or aniocolecta is null
		
		
		-- Se obtiene celdas del SOURCE
		-- caso cuando se envian filtros de tiempo y puede tener o no filtros de fosil
		case when time_filter = true
		then
		
			execute format('
			DROP TABLE IF exists temp_source;
			CREATE TEMP TABLE IF NOT EXISTS temp_source AS
	   		SELECT 
				spid, 
				(array_agg(distinct %s) - $1) as cells, 
				icount(array_agg(distinct %s) - $1) as ni
			FROM snib
			WHERE 
				spid = %s	%s
				and especievalidabusqueda <> ''''
				and 
				(case when $2 = 1 
					  then 
							fechacolecta <> ''''
					  when $2 = 2 
					  then
							cast( NULLIF((regexp_split_to_array(fechacolecta, ''-''))[1], '''')  as integer)>= cast( $3  as integer)
							and 
							cast( NULLIF((regexp_split_to_array(fechacolecta, ''-''))[1], '''')  as integer)<= cast( $4  as integer)
					  else
					  		(
								(
								cast( NULLIF((regexp_split_to_array(fechacolecta, ''-''))[1], '''')  as integer)>= cast( $3  as integer)
								and 
								cast( NULLIF((regexp_split_to_array(fechacolecta, ''-''))[1], '''')  as integer)<= cast( $4  as integer)
								)
								or fechacolecta = ''''
							)
				end) = true
				and especievalidabusqueda <> ''''
					and %s is not null
					group by spid', in_grids, in_grids, in_spid, fossil, in_grids)
				USING lista_gridids_seccion_sp, case_filter, lim_inf, lim_sup;
		
		
		
		-- caso cuando se filtran solo fosiles
		when char_length(fossil) > 1
		then
			
			execute format('
			DROP TABLE IF exists temp_source;
			CREATE TEMP TABLE IF NOT EXISTS temp_source AS
	   		SELECT 
				spid, 
				(array_agg(distinct %s) - $1) as cells, 
				icount(array_agg(distinct %s) - $1) as ni
			FROM snib
			WHERE 
				spid = %s	
				%s	
				and especievalidabusqueda <> ''''
					and %s is not null
					group by spid', in_grids, in_grids, in_spid, fossil, in_grids)
				USING lista_gridids_seccion_sp;
		
		-- caso cuando no existe ningun filtro
		else
		
			raise notice 'source sin filtros';
		
			execute format('
			DROP TABLE IF exists temp_source;
			CREATE TEMP TABLE IF NOT EXISTS temp_source AS
	   		SELECT 
				spid, 
				(%s - $1)  as cells,
				icount(%s - $1) as ni
			FROM sp_snib
			WHERE 
				spid = %s
				and especievalidabusqueda <> ''''', in_cells, in_cells, in_spid)
				USING lista_gridids_seccion_sp;
				
		end case;
		
			
			-- raise notice 'temp_source: %', temp_source;
		
		
		-- Se obtiene celdas del TARGET
		
		-- Caso que abarca variables bioticas en el TARGET
		case when type_process = 'bio'
		then
			
			-- NOTA: LA RESTA DE GRIDS CON lista_gridids DESORDENADO ES MUCHO MAS TARDADO QUE CUANDO ESTA ORDENADO
			-- caso cuando se envian filtros de tiempo y puede tener o no filtros de fosil
			case when time_filter = true
			then
				execute format('
					DROP TABLE IF exists temp_target;
					CREATE TEMP TABLE IF NOT EXISTS temp_target AS
					SELECT  spid, 
							reinovalido, 
							phylumdivisionvalido, 
							clasevalida, 
							ordenvalido, 
							familiavalida, 
							generovalido, 
							especievalidabusqueda, 
							(array_agg(distinct %s) - $1) as cells, 
							icount(array_agg(distinct %s) - $1) as nj 
					FROM snib %s %s
						and 
						(case when $2 = 1 
							  then 
									fechacolecta <> ''''
							  when $2 = 2 
							  then
									cast( NULLIF((regexp_split_to_array(fechacolecta, ''-''))[1], '''')  as integer)>= cast( $3  as integer)
									and 
									cast( NULLIF((regexp_split_to_array(fechacolecta, ''-''))[1], '''')  as integer)<= cast( $4  as integer)
							  else
							  		(
										(
										cast( NULLIF((regexp_split_to_array(fechacolecta, ''-''))[1], '''')  as integer)>= cast( $3  as integer)
										and 
										cast( NULLIF((regexp_split_to_array(fechacolecta, ''-''))[1], '''')  as integer)<= cast( $4  as integer)
										)
										or fechacolecta = ''''
									)
						end) = true
						and especievalidabusqueda <> ''''
						and reinovalido <> ''''
						and phylumdivisionvalido <> ''''
						and clasevalida <> ''''
						and ordenvalido <> ''''
						and familiavalida <> ''''
						and generovalido <> ''''
						and %s is not null
						group by spid,
							generovalido,
							especievalidabusqueda,
							reinovalido,
							phylumdivisionvalido,
							clasevalida,
							ordenvalido,
							familiavalida', in_grids, in_grids, where_target_bio, fossil, in_grids)
						USING lista_grid_total_dicarded, case_filter, lim_inf, lim_sup;
			
			-- caso cuando se filtran solo fosiles			
			when char_length(fossil) > 1
			then 
			
				raise notice 'NO time_filter';
			
				execute format('
					DROP TABLE IF exists temp_target;
					CREATE TEMP TABLE IF NOT EXISTS temp_target AS
				SELECT  spid, 
						reinovalido, 
						phylumdivisionvalido, 
						clasevalida, 
						ordenvalido, 
						familiavalida, 
						generovalido, 
						especievalidabusqueda, 
						(array_agg(distinct %s) - $1) as cells, 
						icount(array_agg(distinct %s) - $1) as nj 
				FROM snib %s %s
					and especievalidabusqueda <> ''''
					and reinovalido <> ''''
					and phylumdivisionvalido <> ''''
					and clasevalida <> ''''
					and ordenvalido <> ''''
					and familiavalida <> ''''
					and generovalido <> ''''
					and %s is not null
					group by spid,
						reinovalido, 
						phylumdivisionvalido, 
						clasevalida, 
						ordenvalido, 
						familiavalida, 
						generovalido, 
						especievalidabusqueda', in_grids, in_grids, where_target_bio, fossil, in_grids)
					USING lista_grid_total_dicarded;
			else
			
				raise notice 'target sin filtros, solo bioticos';
				
				-- caso cuando no existe ningun filtro
				execute format('
					DROP TABLE IF exists temp_target;
					CREATE TEMP TABLE IF NOT EXISTS temp_target AS
					SELECT  spid, 
							reinovalido, 
							phylumdivisionvalido, 
							clasevalida, 
							ordenvalido, 
							familiavalida, 
							generovalido, 
							especievalidabusqueda, 
							(%s - $1) as cells, 
							icount(%s - $1) as nj 
					FROM sp_snib %s
						and especievalidabusqueda <> ''''
						and reinovalido <> ''''
						and phylumdivisionvalido <> ''''
						and clasevalida <> ''''
						and ordenvalido <> ''''
						and familiavalida <> ''''
						and generovalido <> ''''', in_cells, in_cells, where_target_bio)
						USING lista_grid_total_dicarded;
			
			end case;
						
						
			
		-- Caso que abarca variables abioticas en el TARGET			
		when type_process = 'abio'
		then
		
			-- caso cuando no existe ningun filtro
			execute format('DROP TABLE IF exists temp_target;
				CREATE TEMP TABLE IF NOT EXISTS temp_target AS
				SELECT  cast('''' as text) generovalido,
						case when type = 1 then
						layer
						else
						case when strpos(label,''Precipit'') = 0 then
						(label || '' '' || round(cast(split_part(split_part(tag,'':'',1),''.'',1) as numeric)/10,2)  ||'' ºC - '' || round(cast(split_part(split_part(tag,'':'',2),''.'',1) as numeric)/10,2) || '' ºC'')
						else
						(label || '' '' || round(cast(split_part(split_part(tag,'':'',1),''.'',1) as numeric),2)  ||'' mm - '' || round(cast(split_part(split_part(tag,'':'',2),''.'',1) as numeric),2) || '' mm'')
						end 
						end as especievalidabusqueda,
						bid as spid,
						cast('''' as text) reinovalido,
						cast('''' as text) phylumdivisionvalido,
						cast('''' as text) clasevalida,
						cast('''' as text) ordenvalido,
						cast('''' as text) familiavalida,
						((%s & $2) - $1) as cells, 
						icount((%s & $2) - $1) as nj 
				FROM raster_bins %s ', in_cells, in_cells, where_target_abio)
				USING lista_grid_total_dicarded, lista_cell_mx;
		
		else
		
			-- caso cuando se envian filtros de tiempo y puede tener o no filtros de fosil
			case when time_filter = true
			then
				
				execute format('DROP TABLE IF exists temp_target;
					CREATE TEMP TABLE IF NOT EXISTS temp_target AS
					SELECT  generovalido,
							especievalidabusqueda,
							spid, 
							reinovalido, 
							phylumdivisionvalido, 
							clasevalida, 
							ordenvalido, 
							familiavalida,  
							(array_agg(distinct %s) - $1) as cells, 
							icount(array_agg(distinct %s) - $1) as nj
					FROM snib %s %s
						and 
						(case when $2 = 1 
							  then 
									fechacolecta <> ''''
							  when $2 = 2 
							  then
									cast( NULLIF((regexp_split_to_array(fechacolecta, ''-''))[1], '''')  as integer)>= cast( $3  as integer)
									and 
									cast( NULLIF((regexp_split_to_array(fechacolecta, ''-''))[1], '''')  as integer)<= cast( $4  as integer)
							  else
							  		(
										(
										cast( NULLIF((regexp_split_to_array(fechacolecta, ''-''))[1], '''')  as integer)>= cast( $3  as integer)
										and 
										cast( NULLIF((regexp_split_to_array(fechacolecta, ''-''))[1], '''')  as integer)<= cast( $4  as integer)
										)
										or fechacolecta = ''''
									)
						end) = true
						and especievalidabusqueda <> ''''
						and reinovalido <> ''''
						and phylumdivisionvalido <> ''''
						and clasevalida <> ''''
						and ordenvalido <> ''''
						and familiavalida <> ''''
						and generovalido <> ''''
						and %s is not null
						group by spid,
							generovalido,
							especievalidabusqueda,
							spid, 
							reinovalido, 
							phylumdivisionvalido, 
							clasevalida, 
							ordenvalido, 
							familiavalida
	
					union
	 
					SELECT  cast('''' as text) generovalido,
							case when type = 1 then
							layer
							else
							case when strpos(label,''Precipit'') = 0 then
							(label || '' '' || round(cast(split_part(split_part(tag,'':'',1),''.'',1) as numeric)/10,2)  ||'' ºC - '' || round(cast(split_part(split_part(tag,'':'',2),''.'',1) as numeric)/10,2) || '' ºC'')
							else
							(label || '' '' || round(cast(split_part(split_part(tag,'':'',1),''.'',1) as numeric),2)  ||'' mm - '' || round(cast(split_part(split_part(tag,'':'',2),''.'',1) as numeric),2) || '' mm'')
							end 
							end as especievalidabusqueda,
							bid as spid,
							cast('''' as text) reinovalido,
							cast('''' as text) phylumdivisionvalido,
							cast('''' as text) clasevalida,
							cast('''' as text) ordenvalido,
							cast('''' as text) familiavalida,
							((%s & $5) - $1) as cells, 
							icount((%s & $5) - $1) as nj 
					FROM raster_bins %s ', in_grids, in_grids, where_target_bio, fossil, in_grids, in_cells, in_cells, where_target_abio)
					USING lista_grid_total_dicarded, case_filter, lim_inf, lim_sup, lista_cell_mx;
					
			-- caso cuando se filtran solo fosiles
			when char_length(fossil) > 1
			then
			
				execute format('DROP TABLE IF exists temp_target;
					CREATE TEMP TABLE IF NOT EXISTS temp_target AS
					SELECT  generovalido,
							especievalidabusqueda,
							spid, 
							reinovalido, 
							phylumdivisionvalido, 
							clasevalida, 
							ordenvalido, 
							familiavalida,  
							(array_agg(distinct %s) - $1) as cells, 
							icount(array_agg(distinct %s) - $1) as nj
					FROM snib %s %s
						and especievalidabusqueda <> ''''
						and reinovalido <> ''''
						and phylumdivisionvalido <> ''''
						and clasevalida <> ''''
						and ordenvalido <> ''''
						and familiavalida <> ''''
						and generovalido <> ''''
						and %s is not null
						group by spid,
							generovalido,
							especievalidabusqueda,
							spid, 
							reinovalido, 
							phylumdivisionvalido, 
							clasevalida, 
							ordenvalido, 
							familiavalida
	
					union
	 
					SELECT  cast('''' as text) generovalido,
							case when type = 1 then
							layer
							else
							case when strpos(label,''Precipit'') = 0 then
							(label || '' '' || round(cast(split_part(split_part(tag,'':'',1),''.'',1) as numeric)/10,2)  ||'' ºC - '' || round(cast(split_part(split_part(tag,'':'',2),''.'',1) as numeric)/10,2) || '' ºC'')
							else
							(label || '' '' || round(cast(split_part(split_part(tag,'':'',1),''.'',1) as numeric),2)  ||'' mm - '' || round(cast(split_part(split_part(tag,'':'',2),''.'',1) as numeric),2) || '' mm'')
							end 
							end as especievalidabusqueda,
							bid as spid,
							cast('''' as text) reinovalido,
							cast('''' as text) phylumdivisionvalido,
							cast('''' as text) clasevalida,
							cast('''' as text) ordenvalido,
							cast('''' as text) familiavalida,
							((%s & $2) - $1) as cells, 
							icount((%s & $2) - $1) as nj 
					FROM raster_bins %s ', in_grids, in_grids, where_target_bio, fossil, in_grids, in_cells, in_cells, where_target_abio)
					USING lista_grid_total_dicarded, lista_cell_mx;
					
			else
			
				-- caso cuando no existe ningun filtro
				execute format('DROP TABLE IF exists temp_target;
					CREATE TEMP TABLE IF NOT EXISTS temp_target AS
					SELECT  generovalido,
							especievalidabusqueda,
							spid, 
							reinovalido, 
							phylumdivisionvalido, 
							clasevalida, 
							ordenvalido, 
							familiavalida,  
							(%s - $1) as cells, 
							icount(%s - $1) as nj 
					FROM sp_snib %s 
						and especievalidabusqueda <> ''''
						and reinovalido <> ''''
						and phylumdivisionvalido <> ''''
						and clasevalida <> ''''
						and ordenvalido <> ''''
						and familiavalida <> ''''
						and generovalido <> ''''
	
					union
	 
					SELECT  cast('''' as text) generovalido,
							case when type = 1 then
							layer
							else
							case when strpos(label,''Precipit'') = 0 then
							(label || '' '' || round(cast(split_part(split_part(tag,'':'',1),''.'',1) as numeric)/10,2)  ||'' ºC - '' || round(cast(split_part(split_part(tag,'':'',2),''.'',1) as numeric)/10,2) || '' ºC'')
							else
							(label || '' '' || round(cast(split_part(split_part(tag,'':'',1),''.'',1) as numeric),2)  ||'' mm - '' || round(cast(split_part(split_part(tag,'':'',2),''.'',1) as numeric),2) || '' mm'')
							end 
							end as especievalidabusqueda,
							bid as spid,
							cast('''' as text) reinovalido,
							cast('''' as text) phylumdivisionvalido,
							cast('''' as text) clasevalida,
							cast('''' as text) ordenvalido,
							cast('''' as text) familiavalida,
							((%s & $2) - $1) as cells, 
							icount((%s & $2) - $1) as nj 
					FROM raster_bins %s ', in_cells, in_cells, where_target_bio, in_cells, in_cells, where_target_abio)
					USING lista_grid_total_dicarded, lista_cell_mx;
				
			end case;
				
		end case;
		
		
		-- raise notice 'icount: %', array_length(lista_gridids+lista_gridids_seccion_sp,1);
		
		case when in_n = 'full' then
			execute format('select count(*) from %s as grid join aoi on st_intersects(grid.small_geom, aoi.geom) where aoi.fgid = 19', in_cells_tbl) into res_n;
		when in_n = 'species_coverage' then
			select array_length(array_agg(distinct cells),1) into res_n from (select unnest(cells) as cells from temp_target where temp_target.spid <> in_spid and icount(temp_target.cells) >= in_minocc) as final_tbl group by true;
		else
			execute format('select count(*) from %s', in_cells_tbl) into res_n;
		end case;
		
		new_alpha := 1.0/res_n;
		raise notice 'new_alpha: %', new_alpha;
		
		
		
		
		-- obtiene conteos del source y target, ya han sido filtrados los elementos requeridos
		DROP TABLE IF exists temp_counts;
		CREATE TEMP TABLE IF NOT EXISTS temp_counts AS
		SELECT 	temp_target.spid,
				temp_target.reinovalido,
				temp_target.phylumdivisionvalido,
				temp_target.clasevalida,
				temp_target.ordenvalido,
				temp_target.familiavalida,
				temp_target.generovalido,
				temp_target.especievalidabusqueda,
				temp_target.cells  as cells,
				icount(temp_source.cells & temp_target.cells) AS niyj,
				temp_target.nj AS nj,
				temp_source.ni AS ni,
				(res_n - icount(lista_gridids + lista_gridids_seccion_sp)) as n
		FROM temp_source,temp_target
		where 
		temp_target.spid <> in_spid
		and icount(temp_target.cells) >= in_minocc;
		
		
		
		
		-- obtiene score por especie y la celda donde esta presente cada una de las coovariables 
		DROP TABLE IF exists score_coovariables;
		CREATE TEMP TABLE IF NOT EXISTS score_coovariables AS
		SELECT 	
				-- temp_counts.spid,
				unnest(temp_counts.cells) as cell,
				temp_counts.ni,
				temp_counts.spid,
				round( cast(  ln(   
					get_score(
						new_alpha,
						cast(temp_counts.nj as integer), 
						cast(temp_counts.niyj as integer), 
						cast(temp_counts.ni as integer), 
						cast(temp_counts.n as integer)
					)
				) as numeric), 2) as score
		FROM temp_counts;
		
		
		
		-- 	***** CALCULANDO VALORES DEL CONJUNTO DE PRUEBA *****
		
		case when in_getrecall = true
		then
			-- obtiene las especies de las celdas del conjunto de prueba (celdas descartadas)
			-- NOTA: Verificar si se añade el filtro de las covariables, verificar si se filtra en el siguietne paso
			-- TODO: Pasar a execute para enlazar la columna d celdas y la tabla correcta
			
		
			-- obtiene las celdas de prueba para cada iteración de la tabla temporal generada por el store procedure: createtemptableforvalidation utilizada cuando se realiza el proceso de validación
 			execute format('DROP TABLE IF exists spid_cells_test;
							CREATE TEMP TABLE IF NOT EXISTS spid_cells_test AS
							SELECT 	
									unnest(plantae||animalia||fungi||prokaryotae||protoctista
									||bio01||bio02||bio03||bio04||bio05||bio06||bio07||bio09||bio10
									||bio11||bio12||bio13||bio14||bio15||bio16||bio17||bio18||bio19) as spid,
									%s as cell
							FROM %s
							join unnest($1) as gridid
							on %s.%s = gridid', in_grids, in_cells_tbl, in_grids, in_cells_tbl)
							using lista_grid_total_dicarded;
		
			/*DROP TABLE IF exists spid_cells_test;
			CREATE TEMP TABLE IF NOT EXISTS spid_cells_test AS
			SELECT 	
					unnest(plantae||animalia||fungi||prokaryotae||protoctista
					||bio01||bio02||bio03||bio04||bio05||bio06||bio07||bio09||bio10
					||bio11||bio12||bio13||bio14||bio15||bio16||bio17||bio18||bio19) as spid,
					gridid_16km as cell
			FROM grid_16km_aoi
			join unnest(lista_grid_total_dicarded) as gridid
			on grid_16km_aoi.gridid_16km = gridid;*/
			
			
			
			-- enlaza el score del conjunto de covariables con las especies del conjunto de prueba y agrupa el score por celda
			-- Es decir, obtiene el score por celda del conjunto de prueba 
			DROP TABLE IF exists score_cell_test;
			CREATE TEMP TABLE IF NOT EXISTS score_cell_test AS
			SELECT 	
					spid_cells_test.cell,
					-- sum(coalesce(score_coovariables.score, 0)) as score,
					sum(score_coovariables.score) as score,
					'test'::text as type_value
			FROM spid_cells_test
			left join score_coovariables
			-- join score_coovariables
			on score_coovariables.spid = spid_cells_test.spid
			group by spid_cells_test.cell;
			-- order by score desc;
			
			
			
			
			-- obtener score por celda del conjunto de entrenamiento (covariables)
			-- Ademas, lo agrupa con el resultado de score por celda del conjunto de prueba (celdas descartadas)
			DROP TABLE IF exists rawdata;
			CREATE TEMP TABLE IF NOT EXISTS rawdata AS
			SELECT 	
					score_coovariables.cell as gridid, 
					score_coovariables.ni,
					sum(score_coovariables.score) as score,
					'train'::text as type_value
			from score_coovariables
			group by gridid, score_coovariables.ni
			union
			select cell as gridid, 
					0 as ni,
					score,
					score_cell_test.type_value::text
			from score_cell_test
			order by score desc;
			
			
			-- valor de celdas resultantes de cada iteracion
			INSERT INTO temp_cell 
			SELECT 	
					rawdata.gridid,
					rawdata.ni,
					rawdata.score,
					(counter+1) as iter,
					-- (iterations+1) as iter,
					rawdata.type_value
			FROM rawdata;
			
			
			
			
		else
		
			DROP TABLE IF exists rawdata;
			CREATE TEMP TABLE IF NOT EXISTS rawdata AS
			SELECT 	
					score_coovariables.cell as gridid, 
					score_coovariables.ni,
					sum(score_coovariables.score) as score,
					'train'::text as type_value
			from score_coovariables
			group by gridid, score_coovariables.ni
			order by score desc;
			
			
			-- valor de celdas resultantes de cada iteracion
			INSERT INTO temp_cell 
			SELECT 	
					rawdata.gridid,
					rawdata.ni,
					rawdata.score,
					--iteration as iter
					(iterations+1) as iter,
					rawdata.type_value
			FROM rawdata;
			
		end case;
		
		counter := counter + 1 ;
		
    	RETURN NEXT;
     END LOOP;
     
     -- Retorna el promedio del score obtenido del analisis de las N iteraciones
	 RETURN QUERY 
	 select temp_cell.gridid as gridid, 
	 		temp_cell.ni,
     		avg(temp_cell.score) as score,
     		-- (counter+1) as iter,
     		temp_cell.iter,
     		temp_cell.type_value
     from temp_cell
     group by gridid, ni, temp_cell.iter, temp_cell.type_value;
     -- group by gridid, ni, temp_cell.type_value;
	
end; $function$
