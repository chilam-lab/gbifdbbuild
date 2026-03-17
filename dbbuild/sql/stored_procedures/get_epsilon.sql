CREATE OR REPLACE FUNCTION get_epsilon(double precision, integer, integer, integer, integer)
  RETURNS double precision
  LANGUAGE sql
  AS $function$
    SELECT $2*(((cast($3 as float)+($1/2))/(cast($2 as float)+$1))-((cast($4 as float)+$1)/(cast($5 as float)+(2*$1))))/(|/($2*((cast($4 as float)+$1)/(cast($5 as float)+2*$1))*(1-((cast($4 as float)+$1)/(cast($5 as float)+(2*$1))))));
  $function$;
