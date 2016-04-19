﻿CREATE OR REPLACE FUNCTION st_createoverview_qgiscloud(
    tab regclass,
    col name,
    factor integer,
    algo text DEFAULT 'NearestNeighbour'::text)
  RETURNS regclass AS
$BODY$
DECLARE
  sinfo RECORD; -- source info
  sql TEXT;
  ttab TEXT;
BEGIN

  -- 0. Check arguments, we need to ensure:
  --    a. Source table has a raster column with given name
  --    b. Source table has a fixed scale (or "factor" would have no meaning)
  --    c. Source table has a known extent ? (we could actually compute it)
  --    d. Source table has a fixed tile size (or "factor" would have no meaning?)
  -- # all of the above can be checked with a query to raster_columns
  sql := 'SELECT r.r_table_schema sch, r.r_table_name tab, '
      || 'r.scale_x sfx, r.scale_y sfy, r.blocksize_x tw, '
      || 'r.blocksize_y th, r.extent ext, r.srid FROM raster_columns r, '
      || 'pg_class c, pg_namespace n WHERE r.r_table_schema = n.nspname '
      || 'AND r.r_table_name = c.relname AND r_raster_column = $2 AND '
      || ' c.relnamespace = n.oid AND c.oid = $1'
  ;
  EXECUTE sql INTO sinfo USING tab, col;
  IF sinfo IS NULL THEN
      RAISE EXCEPTION '%.% raster column does not exist', tab::text, col;
  END IF;
  IF sinfo.sfx IS NULL or sinfo.sfy IS NULL THEN
    RAISE EXCEPTION 'cannot create overview without scale constraint, try select AddRasterConstraints(''%'', ''%'');', tab::text, col;
  END IF;
  IF sinfo.tw IS NULL or sinfo.tw IS NULL THEN
    RAISE EXCEPTION 'cannot create overview without tilesize constraint, try select AddRasterConstraints(''%'', ''%'');', tab::text, col;
  END IF;
  IF sinfo.ext IS NULL THEN
    RAISE EXCEPTION 'cannot create overview without extent constraint, try select AddRasterConstraints(''%'', ''%'');', tab::text, col;
  END IF;


  ttab := 'o_' || factor || '_' || sinfo.tab;
  sql := 'CREATE TABLE ' || quote_ident(sinfo.sch)
      || '.' || quote_ident(ttab)
      || ' AS SELECT ST_Retile_qgiscloud($1, $2, $3, $4, $5, $6, $7) '
      || quote_ident(col);
  EXECUTE sql USING tab, col, sinfo.ext,
                    sinfo.sfx * factor, sinfo.sfy * factor,
                    sinfo.tw, sinfo.th, algo;

  PERFORM AddRasterConstraints(sinfo.sch, ttab, col);

  PERFORM AddOverviewConstraints(sinfo.sch, ttab, col,
                                 sinfo.sch, sinfo.tab, col, factor);

  RETURN ttab;
END;
$BODY$
  LANGUAGE plpgsql VOLATILE STRICT
  COST 100;



CREATE OR REPLACE FUNCTION st_retile_qgiscloud(
    tab regclass,
    col name,
    ext geometry,
    sfx double precision,
    sfy double precision,
    tw integer,
    th integer,
    algo text DEFAULT 'NearestNeighbour'::text)
  RETURNS SETOF raster AS
$BODY$
DECLARE
  rec RECORD;
  ipx FLOAT8;
  ipy FLOAT8;
  tx int;
  ty int;
  te GEOMETRY; -- tile extent
  ncols int;
  nlins int;
  srid int;
  sql TEXT;
BEGIN

  RAISE DEBUG 'Target coverage will have sfx=%, sfy=%', sfx, sfy;

  -- 2. Loop over each target tile and build it from source tiles
  ipx := st_xmin(ext);
  ncols := ceil((st_xmax(ext)-ipx)/sfx/tw);
  IF sfy < 0 THEN
    ipy := st_ymax(ext);
    nlins := ceil((st_ymin(ext)-ipy)/sfy/th);
  ELSE
    ipy := st_ymin(ext);
    nlins := ceil((st_ymax(ext)-ipy)/sfy/th);
  END IF;

  srid := ST_Srid(ext);

  FOR tx IN 0..ncols-1 LOOP
    FOR ty IN 0..nlins-1 LOOP
      te := ST_MakeEnvelope(ipx + tx     *  tw  * sfx,
                             ipy + ty     *  th  * sfy,
                             ipx + (tx+1) *  tw  * sfx,
                             ipy + (ty+1) *  th  * sfy,
                             srid);
      sql := 'SELECT count(*), ST_CLIP(ST_SnapToGrid(ST_Rescale(ST_Union(ST_Clip(' || quote_ident(col)
          || ', st_expand($3, greatest($1,$2)))),$1, $2, $6), $4, $5, $1, $2), $3) g FROM ' || tab::text
          || ' WHERE ST_Intersects(' || quote_ident(col) || ', $3)';

      FOR rec IN EXECUTE sql USING sfx, sfy, te, ipx, ipy, algo LOOP

        IF rec.g IS NULL THEN
          RAISE WARNING 'No source tiles cover target tile %,% with extent %',
            tx, ty, te::box2d;
        ELSE
          RETURN NEXT rec.g;
        END IF;
      END LOOP;
    END LOOP;
  END LOOP;

  RETURN;
END;
$BODY$
  LANGUAGE plpgsql STABLE STRICT
  COST 100
  ROWS 1000;
