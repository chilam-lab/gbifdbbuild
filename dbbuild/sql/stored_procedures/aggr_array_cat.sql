-- Funcion usanda en la generacion de la minformacion abiotica
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_aggregate a
        JOIN pg_proc p ON a.aggfnoid = p.oid
        WHERE p.proname = 'aggr_array_cat'
    ) THEN
        EXECUTE '
        CREATE AGGREGATE aggr_array_cat (integer[])
        (
          sfunc = array_cat,
          stype = integer[],
          initcond = ''{}''
        )';
    END IF;
END $$;
