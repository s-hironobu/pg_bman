/* contrib/pg_bman/pg_bman--0.1.sql */

-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION pg_bman" to load this file. \quit

-- Register the C function.
CREATE FUNCTION pg_get_archive(text)
RETURNS bytea
AS 'MODULE_PATHNAME', 'pg_get_archive'
LANGUAGE C STRICT;

CREATE FUNCTION pg_show_archives(text)
RETURNS SETOF text
AS 'MODULE_PATHNAME', 'pg_show_archives'
LANGUAGE C STRICT;

-- Don't want these to be available to public.
REVOKE ALL ON FUNCTION pg_get_archive(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION pg_show_archives(text) FROM PUBLIC;
