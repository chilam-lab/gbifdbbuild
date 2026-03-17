CREATE OR REPLACE FUNCTION public.iteratevalidationprocessbydecil(iterations integer, in_spid integer, in_n text, in_alpha numeric, in_minocc integer, in_erased_points integer[], in_cells text, in_grids text, in_cells_tbl text, where_target_bio text, where_target_abio text, type_process text, time_filter boolean, case_filter integer, lim_inf integer, lim_sup integer, fossil text, tblname text, apriori boolean)
 RETURNS TABLE(decil integer, l_sup double precision, l_inf double precision, sum double precision, avg double precision, arraynames text, vp integer, fn integer, nulos integer, recall double precision, iter integer)
 LANGUAGE plpgsql
AS $function$ 
declare 

	
	lista_gridids int[];
	lista_grid_total int[];
	
	lista_grid_total_dicarded int[];
	lista_grid_especie int[];
	lista_gridids_seccion_sp int[];
	
	lista_gridids_train int[];
	
	array_size_tot int;
	array_size_sp int;	
	counter INTEGER := 0;
	val_apriori integer = 0;
	res_n integer = 0;
	new_alpha numeric = 0.0;
	
	lista_cell_mx int[];
	
begin
	raise notice 'INICIA STORE: iteratevalidationprocessbydecil';
	
	-- Tabla donde se retornan los resultados del store procedure
	DROP TABLE IF exists temp_cell;
	create TEMP TABLE temp_cell(
				decil int,
				l_sup float,
				l_inf float,
				sum float,
				avg float,
				arraynames text,
				vp int,
				fn int,
				nulos int,
				recall float,
				iter int
				);
	
	
	LOOP EXIT WHEN counter = iterations;
 		 
 		raise notice '';
		raise notice 'ITERACION %', (counter+1);
 		
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
 			
 			-- obtiene las celdas de prueba de la especie objetivo para cada iteración de la tabla temporal generada por el store procedure: createtemptableforvalidation utilizada cuando se realiza el proceso de validación
 			execute format('select array_agg(cell)
							from(
								select cell
								from %s
								where iter = $1 and tipo_valor = ''train''
								order by cell
							) as t1
							group by true', tblname)
							using counter+1
 							into lista_gridids_train;
 							
			-- se agregan celdas que fueron descartadas por selección de puntos
			lista_gridids := lista_gridids + in_erased_points;
			lista_grid_total_dicarded := lista_gridids + lista_gridids_seccion_sp;
			
		else 
		
			-- se asignan arreglos vacios cuando no es ejecutado el proceso de validación y se añaden caldas descartadas por selección de puntos
			lista_gridids := array[]::integer[];
			lista_gridids_seccion_sp := in_erased_points;
			lista_grid_total_dicarded := lista_gridids;
			
		end case;
		
		--raise notice 'lista_gridids: %', array_length(lista_gridids,1) ;
		--raise notice 'lista_gridids_seccion_sp: %', array_length(lista_gridids_seccion_sp,1);
		--raise notice '';
		
		
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
			
				-- raise notice 'NO time_filter';
			
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
				(res_n - icount(lista_gridids + lista_gridids_seccion_sp)) as n,
				round( cast( 
					get_epsilon(
						new_alpha,
						cast( temp_target.nj as integer), 
						cast( icount(temp_source.cells & temp_target.cells) as integer), 
						cast( temp_source.ni as integer), 
						cast( (res_n - icount(lista_gridids + lista_gridids_seccion_sp)) as integer)
					)as numeric), 2)  as epsilon,
				round( cast(  ln(   
					get_score(
						new_alpha,
						cast( temp_target.nj as integer), 
						cast( icount(temp_source.cells & temp_target.cells) as integer), 
						cast( temp_source.ni as integer), 
						cast( (res_n - icount(lista_gridids + lista_gridids_seccion_sp)) as integer)
					)
				) as numeric), 2) as score
		FROM temp_source,temp_target
		where 
		temp_target.spid <> in_spid
		and icount(temp_target.cells) >= in_minocc;
		
		-- raise notice 'temp_counts (spids): %', (select array_agg(temp_counts.spid) from temp_counts group by true);
		
		--PASO 1
		-- obtiene score por especie y la celda donde esta presente cada una de las coovariables 
		DROP TABLE IF exists score_coovariables;
		CREATE TEMP TABLE IF NOT EXISTS score_coovariables AS
		SELECT 	
				-- temp_counts.spid,
				unnest(temp_counts.cells) as cell,
				temp_counts.ni,
				temp_counts.spid,
				-- 39seg 
				-- temp_counts.spid|| '|' || temp_counts.generovalido || ' ' || temp_counts.especievalidabusqueda || '|' ||temp_counts.epsilon::text|| '|' ||temp_counts.score::text|| '|' ||temp_counts.nj::text as sp_values, 
				
				-- 36 seg
				--temp_counts.especievalidabusqueda || '|' ||temp_counts.epsilon::text|| '|' ||temp_counts.score::text|| '|' ||temp_counts.nj::text as sp_values,
				
				-- 22seg 
				-- temp_counts.spid|| '|' ||temp_counts.epsilon::text|| '|' ||temp_counts.score::text|| '|' ||temp_counts.nj::text as sp_values,
				--temp_counts.epsilon,
				temp_counts.score
		FROM temp_counts;
		
		raise notice 'score_coovariables (spids): %', (select array_agg(spid) from (select spid from score_coovariables limit 100) as temp);
		--raise notice 'score_coovariables (epsilon): %', (select array_agg(epsilon) from (select epsilon from score_coovariables limit 100) as temp);
		-- raise notice 'score_coovariables (especie): %', (select array_agg(especie) from (select especie from score_coovariables limit 100) as temp);
		raise notice 'score_coovariables (cells): %', (select array_agg(cell) from (select cell from score_coovariables limit 100) as temp);
		-- raise notice 'score_coovariables (scores): %', (select array_agg(score) from (select score from score_coovariables limit 100) as temp);
		-- raise notice '';
		
		
		-- obtener score por celda del conjunto de entrenamiento (covariables)
		DROP TABLE IF exists rawdata;
		CREATE TEMP TABLE IF NOT EXISTS rawdata AS
		SELECT 	
				score_coovariables.cell as gridid,
				array_agg(distinct score_coovariables.spid) as spids,
				--array_agg(distinct score_coovariables.sp_values) array_sp,
				score_coovariables.ni,
				sum(score_coovariables.score) as tscore,
				'train'::text as type_value
		from score_coovariables
		group by score_coovariables.cell, score_coovariables.ni
		order by tscore desc;
		
		--raise notice 'rawdata (gridid): %', (select array_agg(gridid) from (select gridid from rawdata limit 100) as temp);
		--raise notice 'rawdata (array_sp): %', (select array_sp from (select array_sp from rawdata limit 1) as temp);
		-- raise notice 'rawdata (tscore): %', (select array_agg(tscore) from (select tscore from rawdata limit 100) as temp);
		raise notice '';
		
						
		case when apriori = true then
			
			val_apriori := (select ln( temp_counts.ni / ( temp_counts.n - temp_counts.ni::numeric) ) from temp_counts limit 1);
			raise notice 'val_apriori: %', val_apriori;
			
			DROP TABLE IF exists prenorm;
			CREATE TEMP TABLE IF NOT EXISTS prenorm as
			select 	
					--allgridids.gridid,
					rawdata.gridid,
					rawdata.ni,
					--rawdata.array_sp,
					rawdata.spids,
					COALESCE(rawdata.tscore+val_apriori, val_apriori) as tscore,
					rawdata.type_value
			from rawdata
			--right join allgridids
			--on rawdata.gridid = allgridids.gridid
			order by rawdata.tscore desc;
			
			
			DROP TABLE IF exists deciles;
			CREATE TEMP TABLE IF NOT EXISTS deciles AS
			SELECT 
					prenorm.gridid,
					prenorm.tscore,
					--prenorm.array_sp,
					prenorm.spids,
					ntile(10) over (order by prenorm.tscore) AS decil 
			FROM prenorm 
			ORDER BY tscore;
			
		else
		
			DROP TABLE IF exists deciles;
			CREATE TEMP TABLE IF NOT EXISTS deciles AS
			SELECT 
					rawdata.gridid,
					rawdata.tscore, 
					--rawdata.array_sp,
					rawdata.spids,
					ntile(10) over (order by rawdata.tscore) AS decil 
			FROM rawdata 
			ORDER BY tscore;
		
		end case;
		
		
		-- deciles (array_sp): {"Artibeus jamaicensis|0.57|0.19|814","Chrotopterus auritus|1.32|1.25|32",...
		raise notice 'deciles (spids): %', (select spids from (select spids from deciles limit 1) as temp);
		raise notice '';
		
		
		-- se obtiene el numero de presencias por decil - por epecie.
		DROP TABLE IF exists names_col;
		CREATE TEMP TABLE IF NOT EXISTS names_col AS
		select 
			deciles.decil,
			unnest(deciles.spids) as specie_data,
			sum(1) as decil_occ
		from deciles 
		group by deciles.decil, specie_data 
		order by deciles.decil desc;
		
		
		-- names_col (decil_occ): {2,4,591,5,648,11,...
		raise notice 'names_col (specie_data): %', (select array_agg(specie_data) from (select specie_data from names_col limit 100 ) as temp);
		raise notice 'names_col (decil_occ): %', (select array_agg(decil_occ) from (select decil_occ from names_col limit 100 ) as temp);
		raise notice 'names_col (decil): %', (select array_agg(temp.decil) from (select names_col.decil from names_col limit 100 ) as temp);
		raise notice '';
		
		
		DROP TABLE IF exists names_col_occ;
		CREATE TEMP TABLE IF NOT EXISTS names_col_occ AS
		select
			names_col.decil,
			temp_counts.especievalidabusqueda || '|' ||temp_counts.epsilon::text|| '|' ||temp_counts.score::text|| '|' ||temp_counts.nj::text|| '|' ||names_col.decil_occ::text as sp_values
		from names_col
		join temp_counts
		on names_col.specie_data = temp_counts.spid;
		
		
		-- names_col_occ (specie_data): Peromyscus maldonadoi|7.28|4.68|2|2
		raise notice 'names_col_occ (sp_values): %', (select sp_values from (select sp_values from names_col_occ limit 1) as temp);
		raise notice 'names_col_occ (decil): %', (select array_agg(temp.decil) from (select names_col_occ.decil from names_col_occ limit 100) as temp);
		raise notice '';
		
		 
		
		-- vuelve a agrupar los valores por decil (ya contiene el numero de ocurrencias por decil)
		DROP TABLE IF exists group_decil_data;
		CREATE TEMP TABLE IF NOT EXISTS group_decil_data AS
		select 	names_col_occ.decil,
				--names_col_occ.decil_occ
				array_agg( names_col_occ.sp_values ) as arraynames
				--array_agg( names_col_occ.decil_occ ) as arrayspids
		from names_col_occ
		group by names_col_occ.decil
		order by names_col_occ.decil;
		
		
		-- group_decil_data (arraynames): {"Tursiops truncatus|1.25|0.51|397|40",...
		raise notice 'group_decil_data (arraynames): %', (select temp.arraynames from (select group_decil_data.arraynames from group_decil_data limit 1) as temp);
		raise notice 'names_col_occ (decil): %', (select array_agg(temp.decil) from (select group_decil_data.decil from group_decil_data limit 100) as temp);
		--raise notice 'group_decil_data count(arraynames): %', (select count(temp.arraynames) from (select group_decil_data.arraynames from group_decil_data limit 1) as temp);
		--raise notice 'group_decil_data count(arrayspids): %', (select count(temp.arrayspids) from (select group_decil_data.arrayspids from group_decil_data limit 1) as temp);
		raise notice '';
		
			
		DROP TABLE IF exists boundaries;
		CREATE TEMP TABLE IF NOT EXISTS boundaries AS
		select 
			deciles.decil,
			cast(round( cast(max(deciles.tscore) as numeric),2) as float) as l_sup, 
			cast(round( cast(min(deciles.tscore) as numeric),2) as float) as l_inf, 
			-- cast(round( cast(sum(deciles.tscore) as numeric),2) as float) as sum, 
			cast(round( cast(avg(deciles.tscore) as numeric),2) as float) as avg,
			group_decil_data.arraynames
			--array_agg( distinct pre_boundaries.spid ) as decil_spids
		from deciles 
		join group_decil_data
		on deciles.decil = group_decil_data.decil
		group by deciles.decil, group_decil_data.arraynames
		order by deciles.decil desc;
		
		raise notice 'boundaries (decil): %', (select array_agg(temp.decil) from (select boundaries.decil from boundaries limit 10) as temp);
		raise notice 'boundaries (avg): %', (select array_agg(temp.avg) from (select boundaries.avg from boundaries limit 10) as temp);
		raise notice 'boundaries (l_inf): %', (select array_agg(temp.l_inf) from (select boundaries.l_inf from boundaries limit 10) as temp);
		raise notice 'boundaries (arraynames): %', (select temp.arraynames from (select boundaries.arraynames from boundaries limit 1) as temp);
		--raise notice '';
		
		
		case when iterations > 1 then
		
			raise notice '';
		
			
			-- 	***** CALCULANDO VALORES DEL CONJUNTO DE PRUEBA *****
		
		
			--PASO 2
			--PASO 2.1
			-- obtiene las especies de las celdas del conjunto de prueba (celdas descartadas) "Solo las celdas de test de la especie objetivo"
			execute format('DROP TABLE IF exists spid_cells_test;
							CREATE TEMP TABLE IF NOT EXISTS spid_cells_test AS
							SELECT 	
									unnest(plantae||animalia||fungi||prokaryotae||protoctista
									||bio01||bio02||bio03||bio04||bio05||bio06||bio07||bio09||bio10
									||bio11||bio12||bio13||bio14||bio15||bio16||bio17||bio18||bio19) as spid,
									%s as cell
							FROM %s
							join unnest($1) as gridid
							on %s.%s = gridid', in_grids, in_cells_tbl, in_cells_tbl, in_grids)
							using lista_gridids_seccion_sp;
							
			raise notice 'spid_cells_test (spids): %', (select array_agg(spid) from (select spid from spid_cells_test limit 100) as temp );
			raise notice 'spid_cells_test (cells): %', (select array_agg(cell) from (select cell from spid_cells_test limit 100) as temp );
			raise notice '';
			
			
			
			--- CHECAR ESTA DANDO NULOS CON LUTZOMYIA!!!!
		
			--PASO 2.2
			-- enlaza el score del conjunto de covariables con las especies del conjunto de prueba y agrupa el score por celda
			-- ******* TODO: Buscar la forma de reducir el tiempo!!!! 
			DROP TABLE IF exists score_spid_test;
			CREATE TEMP TABLE IF NOT EXISTS score_spid_test AS
			SELECT 	distinct
					spid_cells_test.spid,
					spid_cells_test.cell,
					score_coovariables.score
			FROM spid_cells_test
			join score_coovariables
			on spid_cells_test.spid = score_coovariables.spid;
			
			raise notice 'score_spid_test (spids): %', (select array_agg(spid) from (select spid from score_spid_test limit 100) as temp );
			raise notice 'score_spid_test (cells): %', (select array_agg(cell) from (select cell from score_spid_test limit 100) as temp );
			raise notice 'score_spid_test (scores): %', (select array_agg(score) from (select score from score_spid_test limit 100) as temp );
			raise notice '';
			
			
			
			-- Obtiene el score por celda del conjunto de prueba 
			DROP TABLE IF exists score_cell_test;
			CREATE TEMP TABLE IF NOT EXISTS score_cell_test AS
			SELECT 	
					score_spid_test.cell,
					sum(score_spid_test.score) as tscore,
					'test'::text as type_value
			FROM score_spid_test
			group by score_spid_test.cell;
			
			
			raise notice 'score_cell_test (cells): %', (select array_agg(cell) from (select cell from score_cell_test limit 100) as temp);
			raise notice 'score_cell_test (tscore): %', (select array_agg(tscore) from (select tscore from score_cell_test limit 100) as temp);
			raise notice '';
			
			-- end case;
			
			
			--raise notice 'deciles (gridid): %', (select array_agg(gridid) from (select gridid from deciles limit 100) as temp);
			--raise notice 'deciles (tscore): %', (select array_agg(tscore) from (select tscore from deciles limit 100) as temp);
			--raise notice 'deciles (decil): %', (select array_agg(temp.decil) from (select deciles.decil from deciles limit 100) as temp);
			--raise notice '';
			
			
			-- raise notice 'deciles: %', (select array_agg(deciles.tscore) from deciles group by true);
			
				
			
			
			
			
			-- valor de celdas resultantes de cada iteracion
			INSERT INTO temp_cell 
			select 	boundaries.decil, 
					boundaries.l_sup,
					boundaries.l_inf,
					0 as sum, 
					boundaries.avg,
					boundaries.arraynames,
					-- TODO: Revisar estos casos
					case when iterations>1 and count(score_cell_test.*) > 0 -- poner en 6 para probar error de LUTZOMYIA!!!
						then count(score_cell_test.*) filter (WHERE score_cell_test.tscore >= boundaries.l_inf) 
					else 0 end as vp,
					case when iterations>1 and count(score_cell_test.*) > 0
						then count(score_cell_test.*) filter (WHERE score_cell_test.tscore < boundaries.l_inf and score_cell_test.tscore is not null)  
					else 0 end as fn,
					case when iterations>1 and count(score_cell_test.*) > 0
						then count(score_cell_test.*) filter (WHERE score_cell_test.tscore is null) 
					else 0 end as nulos,
					case when iterations>1 and count(score_cell_test.*) > 0
						then (count(score_cell_test.*) filter (WHERE score_cell_test.tscore > boundaries.l_inf))::float / (  (count(score_cell_test.*) filter (WHERE score_cell_test.tscore >= boundaries.l_inf)) + ( count(score_cell_test.*) filter (WHERE score_cell_test.tscore < boundaries.l_inf and score_cell_test.tscore is not null) ) ) 
					else 0 end as recall,
					(counter+1) as iter
			from boundaries
			full outer join score_cell_test
			on true
			group by boundaries.decil, boundaries.l_sup, boundaries.l_inf, boundaries.avg, boundaries.arraynames
			order by boundaries.decil desc;
		
		
		
		else
		
			
				
			
			
			INSERT INTO temp_cell 
			select 	boundaries.decil, 
					boundaries.l_sup,
					boundaries.l_inf,
					-- boundaries.sum,
					0 as sum, 
					boundaries.avg,
					boundaries.arraynames,
					0 as vp,
					0 as fn,
					0 as nulos,
					0 as recall,
					(counter+1) as iter
			from boundaries
			order by boundaries.decil desc;
			
			
			
		end case;
		
		
		
		counter := counter + 1;
		
    	RETURN NEXT;
     END LOOP;
     
     -- Retorna el promedio del score obtenido del analisis de las N iteraciones
	 RETURN QUERY 
	 select 
	 	temp_cell.decil, temp_cell.l_sup, temp_cell.l_inf, temp_cell.sum, temp_cell.avg, temp_cell.arraynames, temp_cell.vp, temp_cell.fn, temp_cell.nulos, temp_cell.recall, temp_cell.iter
     from temp_cell;
     
	 --select 1::int as decil, 1::float as l_sup, 1::float as l_inf, 1::float as sum, 1::float as avg, ''::text as arraynames, 1::int as vp, 1::int as fn, 1::int as nulos, 1::float as recall, 1::int as iter;
     
     -- group by gridid, ni, temp_cell.iter, temp_cell.type_value;
     -- group by gridid, ni, temp_cell.type_value;
	
end; $function$
