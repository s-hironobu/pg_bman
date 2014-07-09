# contrib/pg_bman/Makefile

MODULE_big = pg_bman
OBJS = pg_bman.o

EXTENSION = pg_bman
DATA = pg_bman--0.1.sql pg_bman--unpackaged--0.1.sql

ifdef USE_PGXS
PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
else
subdir = contrib/pg_bman
top_builddir = ../..
include $(top_builddir)/src/Makefile.global
include $(top_srcdir)/contrib/contrib-global.mk
endif

override CPPFLAGS := -I$(libpq_srcdir) $(CPPFLAGS)
override LDLIBS := $(libpq_pgport) $(LDLIBS)
PROGRAM = pg_archivebackup pg_bman.so

all: $(PROGRAM)

clean:
	rm -f $(PROGRAM) *~ *.o *.so
