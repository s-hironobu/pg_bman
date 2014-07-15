/*-------------------------------------------------------------------------
 *
 * pg_archivebackup.c
 *
 * This software is released under the PostgreSQL Licence
 *
 * Author: suzuki hironobu (hironobu@interdb.jp)
 *
 * Copyright (C) 2014  suzuki hironobu
 *-------------------------------------------------------------------------
 */
#include "postgres.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <ctype.h>
#include <libpq-fe.h>
#include <unistd.h>
#include <fcntl.h>
#include <assert.h>

static void	exit_nicely(PGconn *);
static bool	write_walsegment(PGresult *, const char *);
static bool	check_walsegment_name(char *, int);
static int	str_cmp(const char *, const char *);
static void	init_sysval(void);
static void	set_params(int, char **);
static bool	check_params(void);
static void	free_sysval(void);
static void	usage(void);


#define DEFAULT_USER "postgres"
#define DEFAULT_DB "postgres"
#define DEFAULT_PORT 5432
#define BUFF_SIZE 256
#define WALSEGMENT_LEN 24

#define GET_CMD 0x01
#define SHOW_CMD 0x02
#define SWITCH_CMD 0x04


typedef struct {
	char           *host;
	int		port;
	char           *user;
	char           *password;
	char           *db;
	char           *archivinglog_dir;
	int		command;
	char           *walsegment;
	char           *filename;
	bool		original;
}		sysval_t;


static sysval_t	sysval;


/*
 */
static void
exit_nicely(PGconn * conn)
{
	PQfinish(conn);
	exit(1);
}

/*
 */
static		bool
write_walsegment(PGresult * res, const char *file)
{
	char           *bptr;
	int		blen;
	int		fd;

	if (PQntuples(res) != 1) {
		fprintf(stderr, "Error: \n");
		return false;
	}
	bptr = PQgetvalue(res, 0, 0);
	blen = PQgetlength(res, 0, 0);

#ifdef _DEBUG_
	printf(" b = (%d bytes) \n", blen);
#endif
	if ((fd = open(file, O_WRONLY | O_TRUNC | O_CREAT | S_IRUSR)) == -1) {
		fprintf(stderr, "ERROR: could not open %s\n", file);
		return false;
	}
	if (write(fd, bptr, blen) == -1) {
		fprintf(stderr, "ERROR: could not write in %s\n", file);
		close(fd);
		return false;
	}
	chmod(file, S_IRUSR | S_IWUSR);
	close(fd);
	return true;
}

/*
 */
static		bool
check_walsegment_name(char *filename, int offset)
{
	int		i;
	for (i = offset; i < offset + WALSEGMENT_LEN; i++)
		if (isxdigit(filename[i]) == 0)
			return false;
	return true;
}

/*
 */
static int
str_cmp(const char *s1, const char *s2)
{
	int		i = 0;
	while (toupper((unsigned char)s1[i]) == toupper((unsigned char)s2[i])) {
		if (s1[i] == '\0')
			return 0;
		i++;
	}
	return toupper((unsigned char)s1[i]) - toupper((unsigned char)s2[i]);
}

/*
 */
static void
init_sysval(void)
{
	sysval.host = NULL;
	sysval.port = DEFAULT_PORT;
	sysval.user = NULL;
	sysval.password = NULL;
	sysval.db = NULL;

	sysval.archivinglog_dir = NULL;
	sysval.command = 0;
	sysval.walsegment = NULL;
	sysval.filename = NULL;

	sysval.original = false;
}

/*
 */
static void
set_params(int argc, char **argv)
{
	int		i;
	char		c;

	for (i = 0; i < argc; i++)
		if (strcmp(argv[i], "--help") == 0) {
			usage();
			exit(0);
		}
	while ((c = getopt(argc, argv, "h:p:U:W:d:c:a:w:f:o")) != -1) {
		switch (c) {
		case 'h':	/* host */
			if ((sysval.host =
			     (char *)calloc(1, strlen(optarg) + 1)) == NULL
			    || strcpy(sysval.host, optarg) == NULL
			    || strlen(sysval.host) <= 0) {
				fprintf(stderr, "Error: host(NULL) is not valid\n");
				exit(-1);
			}
			break;

		case 'p':	/* port */
			sysval.port = strtol(optarg, NULL, 10);
			if (sysval.port <= 0) {
				fprintf(stderr, "Error: port number %d is not valid\n",
					sysval.port);
				exit(-1);
			}
			break;

		case 'U':	/* user */
			if ((sysval.user =
			     (char *)calloc(1, strlen(optarg) + 1)) == NULL
			    || strcpy(sysval.user, optarg) == NULL
			    || strlen(sysval.user) <= 0) {
				fprintf(stderr, "Error: user(NULL) is not valid\n");
				exit(-1);
			}
			break;

		case 'W':	/* password */
			if ((sysval.password =
			     (char *)calloc(1, strlen(optarg) + 1)) == NULL
			    || strcpy(sysval.password, optarg) == NULL
			    || strlen(sysval.password) <= 0) {
				fprintf(stderr, "Error: password(NULL) is not valid\n");
				exit(-1);
			}
			break;

		case 'd':	/* db */
			if ((sysval.db =
			     (char *)calloc(1, strlen(optarg) + 1)) == NULL
			    || strcpy(sysval.db, optarg) == NULL
			    || strlen(sysval.db) <= 0) {
				fprintf(stderr, "Error: db(NULL) is not valid\n");
				exit(-1);
			}
			break;

		case 'c':	/* command type */
			if (str_cmp(optarg, "get") == 0)
				sysval.command = GET_CMD;
			else if (str_cmp(optarg, "show") == 0)
				sysval.command = SHOW_CMD;
			else if (str_cmp(optarg, "switch") == 0)
				sysval.command = SWITCH_CMD;
			else {
				fprintf(stderr, "ERROR: option error: -%c is not valid\n",
					optopt);
				usage();
				exit(-1);
			}
			break;

		case 'a':	/* archiving log directory */
			if ((sysval.archivinglog_dir =
			     (char *)calloc(1, strlen(optarg) + 1)) == NULL
			  || strcpy(sysval.archivinglog_dir, optarg) == NULL
			    || strlen(sysval.archivinglog_dir) <= 0) {
				fprintf(stderr, "Error: db(NULL) is not valid\n");
				exit(-1);
			}
			break;

		case 'w':	/* wal segment */
			if ((sysval.walsegment =
			     (char *)calloc(1, strlen(optarg) + 1)) == NULL
			    || strcpy(sysval.walsegment, optarg) == NULL
			    || strlen(sysval.walsegment) != WALSEGMENT_LEN
			    || check_walsegment_name(sysval.walsegment, 0) == false) {
				fprintf(stderr, "Error: wal segment %s is not valid\n",
					optarg);
				exit(-1);
			}
			break;

		case 'f':	/* filename */
			if ((sysval.filename =
			     (char *)calloc(1, strlen(optarg) + 1)) == NULL
			    || strcpy(sysval.filename, optarg) == NULL
			    || strlen(sysval.filename) <= 0) {
				fprintf(stderr, "Error: filename %s is not valid\n", optarg);
				exit(-1);
			}
			break;

		case 'o':	/* original mode */
			sysval.original = true;
			break;

		default:
			fprintf(stderr, "ERROR: option error: -%c is not valid\n", optopt);
			usage();
			exit(-1);
		}
	}
}

/*
 */
static		bool
check_params(void)
{
	if (sysval.user == NULL) {
		if ((sysval.user =
		     (char *)calloc(1, strlen(DEFAULT_USER) + 1)) == NULL) {
			fprintf(stderr, "Error: calloc(%s,%d)\n", __FILE__, __LINE__);
			return false;
		}
		strcpy(sysval.user, DEFAULT_USER);
	}
	if (sysval.db == NULL) {
		if ((sysval.db = (char *)calloc(1, strlen(DEFAULT_DB) + 1)) == NULL) {
			fprintf(stderr, "Error: calloc(%s,%d)\n", __FILE__, __LINE__);
			return false;
		}
		strcpy(sysval.user, DEFAULT_USER);
	}
	if (sysval.host == NULL)
		return false;

	if (sysval.command == GET_CMD) {
		if (sysval.walsegment == NULL
		    || sysval.filename == NULL
		    || sysval.archivinglog_dir == NULL)
			return false;
	} else if (sysval.command == SHOW_CMD) {
		if (sysval.archivinglog_dir == NULL)
			return false;
	} else if (sysval.command == SWITCH_CMD) {
		;
	} else {
		return false;
	}

	return true;
}

/*
 */
static void
free_sysval(void)
{
	free(sysval.host);
	free(sysval.user);
	if (sysval.password != NULL)
		free(sysval.password);
	free(sysval.db);
	if (sysval.archivinglog_dir != NULL)
		free(sysval.archivinglog_dir);
	if (sysval.walsegment != NULL)
		free(sysval.walsegment);
	if (sysval.filename != NULL)
		free(sysval.filename);
}

/*
 */
static void
make_conninfo(char *conninfo)
{

	sprintf(conninfo, "host=%s port=%d user=%s dbname=%s",
		sysval.host, sysval.port, sysval.user, sysval.db);

	if (sysval.password != NULL) {
		strcat(conninfo, " password=");
		strcat(conninfo, sysval.password);
	}
}

/*
 */
static void
usage(void)
{
	fprintf(stderr, "Usage:\n");
	fprintf(stderr, "\tpg_archivebackup [OPTIONS] -c get -a archivinglog_dir -w archivinglog -f filename\n");
	fprintf(stderr, "\tpg_archivebackup [OPTIONS] -c show -a archivinglog_dir \n");
	fprintf(stderr, "\tpg_archivebackup [OPTIONS] -c switch\n");
	fprintf(stderr, "\n");
	fprintf(stderr, "\tOPTIONS:\n");
	fprintf(stderr, "\t-h host\n");
	fprintf(stderr, "\t-U user       (default=postgres)\n");
	fprintf(stderr, "\t-p port       (default=5432)\n");
	fprintf(stderr, "\t-d db         (default=postgres)\n");
	fprintf(stderr, "\t-W password   (optional)\n");
	fprintf(stderr, "\n");
	fprintf(stderr, "\t-a archivinglog_dir\n");
	fprintf(stderr, "\t-w archivinglog\n");
	fprintf(stderr, "\t-f filename\n");
	fprintf(stderr, "\n");
	fprintf(stderr, "\t-o            (use original functions[pg_ls_dir|pg_read_binary_file])\n");
	fprintf(stderr, "\t--help\n");
}

/*
 */
static		bool
get_archivelog(PGconn * conn)
{
	PGresult       *res;
	char           *buff;
	const char     *paramValues[1];

	assert(strlen(sysval.archivinglog_dir) > 0);
	assert(strlen(sysval.walsegment) > 0);
	buff = (char *)calloc(1, strlen(sysval.archivinglog_dir) + strlen(sysval.walsegment) + 2);
	sprintf(buff, "%s/%s", sysval.archivinglog_dir, sysval.walsegment);
	paramValues[0] = buff;

	if (sysval.original)
		res = PQexecParams(conn, "SELECT pg_read_binary_file($1)", 1, NULL,
				   paramValues, NULL, NULL, 1);
	else
		res = PQexecParams(conn, "SELECT pg_get_archive($1)", 1, NULL,
				   paramValues, NULL, NULL, 1);


	if (PQresultStatus(res) != PGRES_TUPLES_OK) {
		fprintf(stderr, "SELECT failed: %s", PQerrorMessage(conn));
		PQclear(res);
		exit_nicely(conn);
		return false;
	}
	if (write_walsegment(res, sysval.filename) == false)
		return false;

	PQclear(res);
	free(buff);
	return true;
}

/*
 */
static		bool
show_archivelogs(PGconn * conn)
{
	PGresult       *res;
	int		i;
	const char     *paramValues[1];

	paramValues[0] = sysval.archivinglog_dir;

	if (sysval.original)
		res =
			PQexecParams(conn, "SELECT pg_ls_dir($1)AS list ORDER BY list",
				     1, NULL, paramValues, NULL, NULL, 1);
	else
		res =
			PQexecParams(conn,
			"SELECT pg_show_archives($1) AS list ORDER BY list",
				     1, NULL, paramValues, NULL, NULL, 1);


	if (PQresultStatus(res) != PGRES_TUPLES_OK) {
		fprintf(stderr, "SELECT failed: %s", PQerrorMessage(conn));
		PQclear(res);
		exit_nicely(conn);
		return false;
	}
	for (i = 0; i < PQntuples(res); i++) {
		char           *tptr;
		tptr = PQgetvalue(res, i, 0);

		if (check_walsegment_name(tptr, 0) == true
		    && strlen(tptr) == WALSEGMENT_LEN)
			printf("%s\n", tptr);
	}

	PQclear(res);
	return true;
}

/*
 */
static		bool
switch_xlog(PGconn * conn)
{
	PGresult       *res;

	res = PQexecParams(conn, "SELECT pg_switch_xlog()", 0, NULL,
			   NULL, NULL, NULL, 1);

	if (PQresultStatus(res) != PGRES_TUPLES_OK) {
		fprintf(stderr, "SELECT failed: %s", PQerrorMessage(conn));
		PQclear(res);
		exit_nicely(conn);
		return false;
	}
	PQclear(res);
	return true;
}

/*
 */
int
main(int argc, char **argv)
{
	char		conninfo  [BUFF_SIZE];
	PGconn         *conn;

	init_sysval();
	set_params(argc, argv);

	if (check_params() == false) {
		fprintf(stderr, "Syntax error:\n");
		usage();
		exit(-1);
	}
	make_conninfo(conninfo);
	conn = PQconnectdb(conninfo);

	if (PQstatus(conn) != CONNECTION_OK) {
		fprintf(stderr, "Connection to database failed: %s",
			PQerrorMessage(conn));
		exit_nicely(conn);
	}
	switch (sysval.command) {
	case GET_CMD:
		get_archivelog(conn);
		break;
	case SHOW_CMD:
		show_archivelogs(conn);
		break;
	case SWITCH_CMD:
		switch_xlog(conn);
		break;
	default:
		usage();
		exit(-1);
	}

	PQfinish(conn);
	free_sysval();

	return 0;
}
