CREATE OR REPLACE FUNCTION public.deletetemptableforvalidation(tblname text)
 RETURNS boolean
 LANGUAGE plpgsql
AS $function$  
begin
	  raise notice 'INICIA STORE';
	  execute format('DROP TABLE IF exists %s;',tblname);
	  
	 RETURN true;
	
end; $function$