CREATE OR REPLACE FUNCTION public.get_score(double precision, integer, integer, integer, integer)
  RETURNS double precision
  LANGUAGE sql
    AS $function$
      SELECT ((cast($3 as float)+($1/2))/(cast($4 as float)+$1))/(((cast($2 as float)-cast($3 as float))+($1/2))/((cast($5 as float)-cast($4 as float))+$1));
    $function$;
