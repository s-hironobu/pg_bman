/*-------------------------------------------------------------------------
 *
 * pg_bman
 *
 * This software is released under the PostgreSQL Licence
 *
 * Author: suzuki hironobu (hironobu@interdb.jp)
 *
 * Copyright (C) 2014  suzuki hironobu
 *-------------------------------------------------------------------------
 */
#include "postgres.h"
#include <sys/stat.h>
#include "utils/memutils.h"
#include "utils/builtins.h"
#include "funcapi.h"
#include "storage/fd.h"
#include "miscadmin.h"
#include <regex.h>

PG_MODULE_MAGIC;

PG_FUNCTION_INFO_V1(pg_get_archive);
PG_FUNCTION_INFO_V1(pg_show_archives);


#define WALSEGMENT_LEN 24

static bytea *read_archive_file(const char *, int64);
static bool check_walsegment_name(char *, int);
static char *convert_and_check_pathname(text *);

Datum		pg_get_archive(PG_FUNCTION_ARGS);
Datum		pg_show_archives(PG_FUNCTION_ARGS);

typedef struct
{
	char	   *location;
	DIR		   *dirdesc;
} directory_fctx;


/*
 *
 */
static bool
check_walsegment_name(char *filename, int offset)
{
    int i;
    for (i = offset; i < offset + WALSEGMENT_LEN; i++)
        if (isxdigit(filename[i]) == 0)
            return false;
    return true;
}

/*
 *
 */
static bytea *
read_archive_file(const char *filename, int64 bytes_to_read)
{
	bytea	   *buf;
	size_t		nbytes;
	FILE	   *file;

	if (bytes_to_read > (MaxAllocSize - VARHDRSZ))
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("requested length too large")));

	if ((file = AllocateFile(filename, PG_BINARY_R)) == NULL)
		ereport(ERROR,
				(errcode_for_file_access(),
				 errmsg("could not open file \"%s\" for reading: %m",
						filename)));

	buf = (bytea *) palloc((Size) bytes_to_read + VARHDRSZ);

	nbytes = fread(VARDATA(buf), 1, (size_t) bytes_to_read, file);

	if (ferror(file))
		ereport(ERROR,
				(errcode_for_file_access(),
				 errmsg("could not read file \"%s\": %m", filename)));

	SET_VARSIZE(buf, nbytes + VARHDRSZ);

	FreeFile(file);

	return buf;
}

/*
 *
 */
static char *
convert_and_check_pathname(text *arg)
{
	char	   *filename;

	filename = text_to_cstring(arg);
	canonicalize_path(filename);	/* filename can change length here */

	if (is_absolute_path(filename))
	{
		/* Disallow '/a/b/data/..' */
		if (path_contains_parent_reference(filename))
			ereport(ERROR,
					(errcode(ERRCODE_INSUFFICIENT_PRIVILEGE),
			(errmsg("reference to parent directory (\"..\") not allowed"))));

	}
	else if (!path_is_relative_and_below_cwd(filename))
		ereport(ERROR,
				(errcode(ERRCODE_INSUFFICIENT_PRIVILEGE),
				 (errmsg("path must be in or below the current directory"))));
	
	return filename;
}

/*
 *
 */
Datum
pg_get_archive(PG_FUNCTION_ARGS)
{
	text	   *filename_t = PG_GETARG_TEXT_P(0);
	char	   *filename;

	if (!superuser())
		ereport(ERROR,
				(errcode(ERRCODE_INSUFFICIENT_PRIVILEGE),
				 (errmsg("must be superuser to read files"))));
	
	filename = convert_and_check_pathname(filename_t);

	if (check_walsegment_name(filename, (strlen(filename) - WALSEGMENT_LEN)) == false)
		ereport(ERROR,
				(errcode(ERRCODE_INSUFFICIENT_PRIVILEGE),
				 (errmsg("read only archiving log segment"))));
	
	PG_RETURN_BYTEA_P(read_archive_file(filename, XLOG_SEG_SIZE));
}


/*
 *
 */
Datum
pg_show_archives(PG_FUNCTION_ARGS)
{
	FuncCallContext *funcctx;
	struct dirent *de;
	directory_fctx *fctx;

	if (!superuser())
		ereport(ERROR,
				(errcode(ERRCODE_INSUFFICIENT_PRIVILEGE),
				 (errmsg("must be superuser to get directory listings"))));

	if (SRF_IS_FIRSTCALL())
	{
		MemoryContext oldcontext;

		funcctx = SRF_FIRSTCALL_INIT();
		oldcontext = MemoryContextSwitchTo(funcctx->multi_call_memory_ctx);

		fctx = palloc(sizeof(directory_fctx));
		fctx->location = convert_and_check_pathname(PG_GETARG_TEXT_P(0));

		fctx->dirdesc = AllocateDir(fctx->location);

		if (!fctx->dirdesc)
			ereport(ERROR,
					(errcode_for_file_access(),
					 errmsg("could not open directory \"%s\": %m",
							fctx->location)));

		funcctx->user_fctx = fctx;
		MemoryContextSwitchTo(oldcontext);
	}

	funcctx = SRF_PERCALL_SETUP();
	fctx = (directory_fctx *) funcctx->user_fctx;

	while ((de = ReadDir(fctx->dirdesc, fctx->location)) != NULL)
	{
		if (check_walsegment_name(de->d_name, 0) == false)
			continue;
		SRF_RETURN_NEXT(funcctx, CStringGetTextDatum(de->d_name));
	}

	FreeDir(fctx->dirdesc);

	SRF_RETURN_DONE(funcctx);
}
