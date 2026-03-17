/*******************************************************************
* El siguiente tipo y las dos funciones son para generar la malla. *
* Se basa en el codigo que se encuentra en:                        *
* https://spatialdbadvisor.com/postgis_tips_tricks/?pg=2           *
********************************************************************/



DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_type 
        WHERE typname = 't_grid'  -- Nombre del tipo (siempre en minúsculas)
    ) THEN
        EXECUTE '
        CREATE TYPE T_Grid AS (gcol int4,grow int4,gridid int4,geom geometry)';
    END IF;
END $$;

-- CREATE TYPE T_Grid AS (gcol int4,grow int4,gridid int4,geom geometry);


CREATE OR REPLACE FUNCTION ST_RegularGrid(p_geometry   geometry,
                                          p_TileSizeX  NUMERIC,
                                          p_TileSizeY  NUMERIC,
                                          p_point      BOOLEAN DEFAULT TRUE)
  RETURNS SETOF T_Grid AS
$BODY$
DECLARE
   v_mbr   geometry;
   v_srid  int4;
   v_halfX NUMERIC := p_TileSizeX / 2.0;
   v_halfY NUMERIC := p_TileSizeY / 2.0;
   v_loCol int4;
   v_hiCol int4;
   v_loRow int4;
   v_hiRow int4;
   v_grid  T_Grid;
BEGIN
   IF ( p_geometry IS NULL ) THEN
      RETURN;
   END IF;
   v_srid  := ST_SRID(p_geometry);
   v_mbr   := ST_Envelope(p_geometry);
   v_loCol := trunc((ST_XMIN(v_mbr) / p_TileSizeX)::NUMERIC );
   v_hiCol := CEIL( (ST_XMAX(v_mbr) / p_TileSizeX)::NUMERIC ) - 1;
   v_loRow := trunc((ST_YMIN(v_mbr) / p_TileSizeY)::NUMERIC );
   v_hiRow := CEIL( (ST_YMAX(v_mbr) / p_TileSizeY)::NUMERIC ) - 1;
   FOR v_col IN v_loCol..v_hiCol Loop
     FOR v_row IN v_loRow..v_hiRow Loop
         v_grid.gcol := v_col;
         v_grid.grow := v_row;
         IF ( p_point ) THEN
           v_grid.geom := ST_SetSRID(
                             ST_MakePoint((v_col * p_TileSizeX) + v_halfX,
                                          (v_row * p_TileSizeY) + v_halfY),
                             v_srid);
         ELSE
           v_grid.geom := ST_SetSRID(
                             ST_MakeEnvelope((v_col * p_TileSizeX),
                                             (v_row * p_TileSizeY),
                                             (v_col * p_TileSizeX) + p_TileSizeX,
                                             (v_row * p_TileSizeY) + p_TileSizeY),
                             v_srid);
         END IF;
         RETURN NEXT v_grid;
     END Loop;
   END Loop;
END;
$BODY$
  LANGUAGE plpgsql IMMUTABLE
  COST 100
  ROWS 1000;


/*Genera celdas cuyos lados se encuentran segmentados en varios arcos.*/

CREATE OR REPLACE FUNCTION ST_RegularRefinedGrid(p_geometry   geometry,
                                          p_TileSizeX  NUMERIC,
                                          p_TileSizeY  NUMERIC,
                                          p_nsegs     NUMERIC,
                                          p_point      BOOLEAN DEFAULT TRUE)
  RETURNS SETOF T_Grid AS
$BODY$
DECLARE
   v_mbr   geometry;
   v_srid  int4;
   v_halfX NUMERIC := p_TileSizeX / 2.0;
   v_halfY NUMERIC := p_TileSizeY / 2.0;
   v_loCol int4;
   v_hiCol int4;
   v_loRow int4;
   v_hiRow int4;
   polyLine text;
   v_grid  T_Grid;
BEGIN
   IF ( p_geometry IS NULL ) THEN
      RETURN;
   END IF;
   v_srid  := ST_SRID(p_geometry);
   v_mbr   := ST_Envelope(p_geometry);
   v_loCol := trunc((ST_XMIN(v_mbr) / p_TileSizeX)::NUMERIC );
   v_hiCol := CEIL( (ST_XMAX(v_mbr) / p_TileSizeX)::NUMERIC ) - 1;
   v_loRow := trunc((ST_YMIN(v_mbr) / p_TileSizeY)::NUMERIC );
   v_hiRow := CEIL( (ST_YMAX(v_mbr) / p_TileSizeY)::NUMERIC ) - 1;
   FOR v_col IN v_loCol..v_hiCol Loop
     FOR v_row IN v_loRow..v_hiRow Loop
         polyLine := 'LINESTRING(';
         v_grid.gcol := v_col;
         v_grid.grow := v_row;
         IF ( p_point ) THEN
           v_grid.geom := ST_SetSRID(
                             ST_MakePoint((v_col * p_TileSizeX) + v_halfX,
                                          (v_row * p_TileSizeY) + v_halfY),
                             v_srid);
         ELSE
           FOR nseg IN 0..(p_nsegs) Loop
               polyLine := polyLine||CAST((v_col*p_TileSizeX)+(p_TileSizeX/p_nsegs)*nseg AS text)||' '||CAST((v_row*p_TileSizeY) AS text)||',';
               
           END Loop;
               
           FOR nseg IN 1..(p_nsegs) Loop
               polyLine := polyLine||CAST((v_col*p_TileSizeX)+p_TileSizeX AS text)||' '||CAST((v_row*p_TileSizeY)+(p_TileSizeY/p_nsegs)*nseg AS text)||',';
           END Loop;

           FOR nseg IN 1..(p_nsegs) Loop
               polyLine := polyLine||CAST((v_col*p_TileSizeX)+(p_TileSizeX/p_nsegs)*(p_nsegs-nseg) AS text)||' '||CAST((v_row*p_TileSizeY)+p_TileSizeY AS text)||',';
           END Loop;

           FOR nseg IN 1..(p_nsegs) Loop
               IF ( nseg = p_nsegs ) THEN
                  polyLine := polyLine||CAST((v_col*p_TileSizeX) AS text)||' '||CAST((v_row*p_TileSizeY)+(p_TileSizeY/p_nsegs)*(p_nsegs-nseg) AS text)||')';
               ELSE
                  polyLine := polyLine||CAST((v_col*p_TileSizeX) AS text)||' '||CAST((v_row*p_TileSizeY)+(p_TileSizeY/p_nsegs)*(p_nsegs-nseg) AS text)||',';
               END IF;
           END Loop;

           v_grid.geom := ST_SetSRID(ST_MakePolygon(ST_GeomFromText(polyLine)),v_srid);

         END IF;
         RETURN NEXT v_grid;
     END Loop;
   END Loop;
END;
$BODY$
  LANGUAGE plpgsql IMMUTABLE
  COST 100
  ROWS 1000;

