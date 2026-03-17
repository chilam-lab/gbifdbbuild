CREATE OR REPLACE FUNCTION public.iteratevalidationprocess(iterations integer, in_spid integer, in_n text, in_alpha numeric, in_minocc integer, in_erased_points integer[], in_cells text, in_grids text, in_cells_tbl text, where_target_bio text, where_target_abio text, type_process text, time_filter boolean, case_filter integer, lim_inf integer, lim_sup integer, fossil text, tblname text)
 RETURNS TABLE(out_spid integer, out_tipo integer, out_reinovalido text, out_phylumdivisionvalido text, out_clasevalida text, out_ordenvalido text, out_familiavalida text, out_generovalido text, out_especievalidabusqueda text, out_cells integer[], out_ni integer, out_nj integer, out_nij integer, out_n integer, out_epsilon numeric, out_score numeric, out_iter integer)
 LANGUAGE plpgsql
AS $function$ 
declare 
	
	lista_gridids int[];
	lista_grid_total int[];
	lista_grid_total_sp int[];
	lista_grid_especie int[];
	lista_gridids_seccion_sp int[];
	array_size_tot int;
	array_size_sp int;
	res_n integer = 0;
	res_n_test integer = 0;
	new_alpha numeric = 0.0;
	
	lista_cell_mx int[];
	
	counter INTEGER := 0;
begin
	raise notice 'INICIA STORE: iteratevalidationprocess';
	
	
	DROP TABLE IF exists temp_rawdata;
	create TEMP TABLE temp_rawdata(
				spid int, 
				tipo int,
				reinovalido text,
				phylumdivisionvalido text,
				clasevalida text,
				ordenvalido text,
				familiavalida text,
				generovalido text,
				especievalidabusqueda text,
				cells int[], ni int, nj int, nij int, n int, epsilon numeric, score numeric, iter int);
	
	LOOP EXIT WHEN counter = iterations;
 		 
 		raise notice 'ITERACION %', (counter+1);
 		
 		case when iterations > 1 then
 		
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
 							

			-- select  into lista_gridids;
			-- select (lista_grid_especie)[0:(array_size_sp/iterations*(counter+1))-1] into lista_gridids_seccion_sp;
			-- raise notice 'index in: %', 0;
			-- raise notice 'index out: %', (array_length(lista_grid_total,1)/iterations*(counter+1));
				
			lista_gridids := lista_gridids + in_erased_points;
			
		else 
		
			-- lista_gridids := in_erased_points;
			-- lista_gridids_seccion_sp := array[]::integer[];
			
			lista_gridids := array[]::integer[];
			lista_gridids_seccion_sp := in_erased_points;
			
		end case;
		
		
		execute format('select array_agg(%s)  
						FROM america as ame
						join %s as grid
						on st_intersects(ame.geom, grid.the_geom)
						where gid = 19
						group by true', in_grids, in_cells_tbl)
						into lista_cell_mx;
		
		
		
		
		-- No contiene las celdas 
		-- raise notice 'lista_gridids: %', lista_gridids;
		-- raise notice 'lista_gridids_seccion_sp: %', lista_gridids_seccion_sp;
		
		-- caso 1: aniocolecta is not null
		-- caso 2: aniocolecta >= $3 and aniocolecta <= $4
		-- caso 3: (aniocolecta >= $3 and aniocolecta <= $4) or aniocolecta is null
		
		
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
				spid = %s	
				%s	
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
				
		else
		
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
		
		
		-- obtiene el conjunto de la especie objetivo - N parte de ocurrencias por celda y la N parte del conjunto de celdas totales
			
		
		case when type_process = 'bio'
		then
			-- LA RESTA DE GRIDS CON lista_gridids DESORDENADO ES MUCHO MAS TARDADO QUE CUANDO ESTA ORDENADO
			case when time_filter = true
			then
				-- raise notice 'time_filter';
				
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
						icount(array_agg(distinct %s) - $1) as nj,
						0 as tipo
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
						reinovalido, 
						phylumdivisionvalido, 
						clasevalida, 
						ordenvalido, 
						familiavalida, 
						generovalido, 
						especievalidabusqueda', in_grids, in_grids, where_target_bio, fossil, in_grids)
					USING lista_gridids, case_filter, lim_inf, lim_sup;
					
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
						icount(array_agg(distinct %s) - $1) as nj,
						0 as tipo
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
					USING lista_gridids;
			else
			
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
							icount(%s - $1) as nj,
							0 as tipo
					FROM sp_snib %s
						and especievalidabusqueda <> ''''
						and reinovalido <> ''''
						and phylumdivisionvalido <> ''''
						and clasevalida <> ''''
						and ordenvalido <> ''''
						and familiavalida <> ''''
						and generovalido <> ''''', in_cells, in_cells, where_target_bio)
						USING lista_gridids;
				
			
			end case;
			
		when type_process = 'abio'
		then
		
			execute format('DROP TABLE IF exists temp_target;
			CREATE TEMP TABLE IF NOT EXISTS temp_target AS
			SELECT  cast('''' as text) generovalido,
					case when type = 1 then
					layer
					else
						case when strpos(label,''Precipit'') = 0 then
						(layer || '' '' || round(cast(split_part(split_part(tag,'':'',1),''.'',1) as numeric)/10,2)  ||'' ºC - '' || round(cast(split_part(split_part(tag,'':'',2),''.'',1) as numeric)/10,2) || '' ºC'')
						else
						(layer || '' '' || round(cast(split_part(split_part(tag,'':'',1),''.'',1) as numeric),2)  ||'' mm - '' || round(cast(split_part(split_part(tag,'':'',2),''.'',1) as numeric),2) || '' mm'')
						end
					end as especievalidabusqueda,
					bid as spid,
					cast('''' as text) reinovalido,
					cast('''' as text) phylumdivisionvalido,
					cast('''' as text) clasevalida,
					cast('''' as text) ordenvalido,
					cast('''' as text) familiavalida,
					((%s & $2) - $1) as cells, 
					icount((%s & $2) - $1) as nj,
					0 as tipo
			FROM raster_bins %s ', in_cells, in_cells, where_target_abio)
			USING lista_gridids, lista_cell_mx;
		
		else -- both
			
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
							icount(array_agg(distinct %s) - $1) as nj,
							0 as tipo
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
							(layer || '' '' || round(cast(split_part(split_part(tag,'':'',1),''.'',1) as numeric)/10,2)  ||'' ºC - '' || round(cast(split_part(split_part(tag,'':'',2),''.'',1) as numeric)/10,2) || '' ºC'')
							else
							(layer || '' '' || round(cast(split_part(split_part(tag,'':'',1),''.'',1) as numeric),2)  ||'' mm - '' || round(cast(split_part(split_part(tag,'':'',2),''.'',1) as numeric),2) || '' mm'')
							end 
							end as especievalidabusqueda,
							bid as spid,
							cast('''' as text) reinovalido,
							cast('''' as text) phylumdivisionvalido,
							cast('''' as text) clasevalida,
							cast('''' as text) ordenvalido,
							cast('''' as text) familiavalida,
							((%s & $5) - $1) as cells, 
							icount((%s & $5) - $1) as nj,
							1 as tipo
					FROM raster_bins %s ', in_grids, in_grids, where_target_bio, fossil, in_grids, in_cells, in_cells, where_target_abio)
					USING lista_gridids, case_filter, lim_inf, lim_sup, lista_cell_mx;
			
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
							icount(array_agg(distinct %s) - $1) as nj,
							0 as tipo
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
							(layer || '' '' || round(cast(split_part(split_part(tag,'':'',1),''.'',1) as numeric)/10,2)  ||'' ºC - '' || round(cast(split_part(split_part(tag,'':'',2),''.'',1) as numeric)/10,2) || '' ºC'')
							else
							(layer || '' '' || round(cast(split_part(split_part(tag,'':'',1),''.'',1) as numeric),2)  ||'' mm - '' || round(cast(split_part(split_part(tag,'':'',2),''.'',1) as numeric),2) || '' mm'')
							end 
							end as especievalidabusqueda,
							bid as spid,
							cast('''' as text) reinovalido,
							cast('''' as text) phylumdivisionvalido,
							cast('''' as text) clasevalida,
							cast('''' as text) ordenvalido,
							cast('''' as text) familiavalida,
							((%s & $2) - $1) as cells, 
							icount((%s & $2) - $1) as nj,
							1 as tipo 
					FROM raster_bins %s ', in_grids, in_grids, where_target_bio, fossil, in_grids, in_cells, in_cells, where_target_abio)
					USING lista_gridids, lista_cell_mx;
			
			else
				
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
								icount(%s - $1) as nj,
								0 as tipo
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
								(layer || '' '' || round(cast(split_part(split_part(tag,'':'',1),''.'',1) as numeric)/10,2)  ||'' ºC - '' || round(cast(split_part(split_part(tag,'':'',2),''.'',1) as numeric)/10,2) || '' ºC'')
								else
								(layer || '' '' || round(cast(split_part(split_part(tag,'':'',1),''.'',1) as numeric),2)  ||'' mm - '' || round(cast(split_part(split_part(tag,'':'',2),''.'',1) as numeric),2) || '' mm'')
								end 
								end as especievalidabusqueda,
								bid as spid,
								cast('''' as text) reinovalido,
								cast('''' as text) phylumdivisionvalido,
								cast('''' as text) clasevalida,
								cast('''' as text) ordenvalido,
								cast('''' as text) familiavalida,
								((%s & $2) - $1) as cells, 
								icount((%s & $2) - $1) as nj,
								1 as tipo
						FROM raster_bins %s ', in_cells, in_cells, where_target_bio, in_cells, in_cells, where_target_abio)
						USING lista_gridids, lista_cell_mx;
				
			end case;
		
			
		end case;
		
		
		case when in_n = 'full' then
			execute format('select count(*) from %s as grid join aoi on st_intersects(grid.small_geom, aoi.geom) where aoi.fgid = 19', in_cells_tbl) into res_n;
		when in_n = 'species_coverage' then
			select array_length(array_agg(distinct cells),1) into res_n from (select unnest(cells) as cells from temp_target where temp_target.spid <> in_spid and icount(temp_target.cells) >= in_minocc) as final_tbl group by true;
		else
			execute format('select count(*) from %s', in_cells_tbl) into res_n;
		end case;
		
		
				
		raise notice 'res_n: %', res_n;
		new_alpha := 1.0/res_n;
		raise notice 'new_alpha: %', new_alpha;
		
		
		 --where temp_target.spid <> in_spid and icount(temp_target.cells) >= in_minocc;
		-- raise notice 'temp_target: %', (select icount(temp_target.cells) into res_n_test from temp_target);
		
		--raise notice 'temp_target (gridid): %', (select array_agg(array_length(cells, 1)) from (select cells from temp_target limit 100) as temp);
		
		--raise notice 'icount: %', (icount('{1,2,3}'::int[] & '{3,5}'::int[]));
		--raise notice 'temp_source: %', (select icount(temp_source.cells)  from temp_source);
		
		
		
		
			
		-- raise notice 'icount: %', array_length(lista_gridids+lista_gridids_seccion_sp,1);	
		
		DROP TABLE IF exists temp_counts;
		CREATE TEMP TABLE IF NOT EXISTS temp_counts AS
		SELECT 	temp_target.spid,
				temp_target.tipo,
				temp_target.reinovalido,
				temp_target.phylumdivisionvalido,
				temp_target.clasevalida,
				temp_target.ordenvalido,
				temp_target.familiavalida,
				temp_target.generovalido,
				temp_target.especievalidabusqueda,
				temp_target.cells  as cells,
				icount(temp_source.cells & temp_target.cells) AS niyj,
				icount(temp_target.cells) AS nj,
				icount(temp_source.cells) AS ni,
				(res_n - icount(lista_gridids + lista_gridids_seccion_sp)) as n
		FROM temp_source,temp_target
		where 
		temp_target.spid <> in_spid
		and icount(temp_target.cells) >= in_minocc;
		
		--raise notice 'temp_counts nj: %', (select temp_counts.nj from temp_counts limit 1);
		
		INSERT INTO temp_rawdata 
		SELECT 	
				temp_counts.spid,
				temp_counts.tipo,
				temp_counts.reinovalido,
				temp_counts.phylumdivisionvalido,
				temp_counts.clasevalida,
				temp_counts.ordenvalido,
				temp_counts.familiavalida,
				temp_counts.generovalido,
				temp_counts.especievalidabusqueda,
				
				temp_counts.cells,
				temp_counts.ni,
				temp_counts.nj,
				temp_counts.niyj as nij,
				temp_counts.n,
				round( cast(  
					get_epsilon(
						new_alpha,
						cast(temp_counts.nj as integer), 
						cast(temp_counts.niyj as integer), 
						cast(temp_counts.ni as integer), 
						cast(temp_counts.n as integer)
					) as numeric), 2)  as epsilon,
				round( cast(  ln(   
					get_score(
						new_alpha,
						cast(temp_counts.nj as integer), 
						cast(temp_counts.niyj as integer), 
						cast(temp_counts.ni as integer), 
						cast(temp_counts.n as integer)
					)
				) as numeric), 2) as score,
				(counter+1) as iter
		FROM temp_counts;
		
		counter := counter + 1 ;
		
    	RETURN NEXT;
     END LOOP;
        
    
	 RETURN QUERY 
	 select spid, 
	 		tipo,
	 		reinovalido, 
	 		phylumdivisionvalido, 
	 		clasevalida, 
	 		ordenvalido, 
			familiavalida, 
			generovalido, 
			especievalidabusqueda,
			cells, ni, nj, nij, n, epsilon, score, iter
	 from temp_rawdata;
	
end; $function$
