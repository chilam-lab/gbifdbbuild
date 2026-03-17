CREATE OR REPLACE FUNCTION Man_InsertRasterCells(_raster regclass, 
  _grid regclass, 
  _ttable regclass, 
  _grididcol varchar, 
  _cellcol varchar, 
  _layer varchar)
  RETURNS integer AS
$func$
BEGIN
  EXECUTE 'UPDATE '||_ttable||' t0 SET '||_cellcol||' = array_remove(uniq(sort(t1.cells)),NULL) FROM (SELECT foo.icat as icat,aggr_array_cat(ARRAY[foo.'||_grididcol||']::integer[]) AS cells FROM (SELECT (foo1.pvc).value as icat,foo1.'||_grididcol||' FROM (SELECT ST_ValueCount(runion.urast,1) as pvc, '||_grididcol||' FROM (SELECT ST_Clip(rast,the_geom) as urast,'||_grididcol||' FROM '||_raster||','||_grid||' WHERE ST_Intersects(rast,the_geom)) as runion) as foo1) AS foo GROUP BY foo.icat ) AS t1 WHERE t1.icat = t0.icat AND t0.layer = '''||_layer||'''';

  RETURN 1;
EXCEPTION WHEN OTHERS then
  RAISE NOTICE 'The transaction is in an uncommittable state. '
               'Transaction was rolled back';

  RAISE NOTICE '% %', SQLERRM, SQLSTATE;
  RETURN 0;
END
$func$  LANGUAGE plpgsql;
