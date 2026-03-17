CREATE OR REPLACE FUNCTION public.createtemptabletaxonsgroupvalidation_2(filter text, grid text, tblname text, iter integer, res_celda_sp text, res_celda_snib_tb text, region integer, resolution integer)
 RETURNS boolean
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
	counter INTEGER := 0;
	
begin
	  	raise notice 'INICIA STORE';
	  
	  	
	  	execute format('
			CREATE TABLE %s (
	  		cell integer,
			tipo_valor text,
			iter integer,
			sp_obj boolean
	  	)', tblname);
	  	
	  	
		execute format('
			select array_agg(cells)
			from 
			(
				SELECT * FROM (
					SELECT DISTINCT b.%s AS cells
					FROM snib_grid_%skm AS b
					JOIN 
						(
							SELECT spid
							FROM sp_snib AS a
							WHERE %s
							and a.spid is not null
							and array_length(a.%s, 1) > 0
						) AS c
					ON b.spid = c.spid
					WHERE b.%s is not null
					AND b.gid = ANY(ARRAY(
										SELECT unnest(gid)
										FROM %s
										WHERE footprint_region = %s
									))
				) AS tab_b
				ORDER BY random()
			) as tab_a
		', grid, resolution, filter, res_celda_sp||'_'||region, grid, res_celda_snib_tb, region)
		into lista_grid_especie;
		
		
		execute format('
			select array_agg(cells) as cells 
			from 
			(
				select cells 
				from (	 
					select unnest(cells) as cells 
					 from (
						select cells - $1  as cells  
						from %s
						where footprint_region = %s
					) as tab_a
				) as tab_b
				order by random()
			) as tab_c
			group by true
		', res_celda_snib_tb, region)
		using lista_grid_especie
		into lista_grid_total;
		
		
		/*
		-- Datos ordenados
		execute format('
			select array_agg(%s) - $1  as cells  
			from %s
			group by true			
		', res_celda_snib, res_celda_snib_tb)
		using lista_grid_especie
		into lista_grid_total;*/
		
		raise notice 'lista_grid_especie: %', array_length(lista_grid_especie,1);
		raise notice 'lista_grid_total: %', array_length(lista_grid_total,1);
	  	
	  	
	  
	  	LOOP EXIT WHEN counter = iter;
 		 
	 		raise notice 'ITERACION %', (counter+1);
	 		
	 		select array_length(lista_grid_total,1) into array_size_tot;
			select array_length(lista_grid_especie,1) into array_size_sp;
		
			
			case when counter = 0 then
				select (lista_grid_total)[0:(array_size_tot/iter*(counter+1))-1] into lista_gridids;
				select (lista_grid_especie)[0:(array_size_sp/iter*(counter+1))-1] into lista_gridids_seccion_sp;
			else
				select (lista_grid_total)[((array_size_tot/iter)*counter):(array_size_tot/iter*(counter+1))-1] into lista_gridids;
				select (lista_grid_especie)[((array_size_sp/iter)*counter):(array_size_sp/iter*(counter+1))-1] into lista_gridids_seccion_sp;
			end case;
			
			raise notice 'lista_gridids: %',  array_length(lista_gridids,1) ;
			raise notice 'lista_grid_total: %', array_length(lista_gridids_seccion_sp,1);
			
			-- TODO: Incluir puntos descartados por eliminación
			-- lista_gridids := lista_gridids + in_erased_points
			
			
			execute format('
				insert into %s 
				select *, ''train'' as tipo_valor, ($1+1) as iter, FALSE as sp_obj 
				from unnest($2)', tblname)
				using counter, lista_grid_total - lista_gridids;
			
			execute format('
				insert into %s 
				select *, ''train'' as tipo_valor, ($1+1) as iter, TRUE as sp_obj
				from unnest($2)', tblname)
				using counter, lista_grid_especie - lista_gridids_seccion_sp;
			
			execute format('
				insert into %s 
				select *, ''test'' as tipo_valor, ($1+1) as iter, FALSE as sp_obj 
				from unnest($2)', tblname)
				using counter, lista_gridids;
				
			execute format('
				insert into %s 
				select *, ''test'' as tipo_valor, ($1+1) as iter, TRUE as sp_obj 
				from unnest($2)', tblname)
				using counter, lista_gridids_seccion_sp;
			
	 		
	 		counter := counter + 1 ;
			
     	END LOOP;

	 RETURN true;
	
end; $function$