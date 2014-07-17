pg_bman
=======

Yet another hot back up tool for PostgreSQL. 


`pg_bman` is similar to [pg_rman](http://sourceforge.net/projects/pg-rman/), but can take backup from a remote server.
`pg_bman` is similar to [pgbarman](http://www.pgbarman.org/), but requires neither ssh nor rsync for take backup.

>To restore a database, ftp or scp is required.

リモートホストにバックアップできるpg_rmanみたいなツール。
標準の通信プロトコル(libpq)だけでオンラインのフルバックアップとインクリメンタルバックアップができます。sshもrsyncもftpも不要です。

## SETUP

      PostgreSQL    BackupServer
    192.168.1.100   192.168.1.200
      +---+    libpq    +---+
      |   |============>|   |
      +---+             +---+

### on PostgreSQL Server

Make Arichiving Log directory.

    $ mkdir /home/postgres/archives

Edit "postgresql.conf".

    max_wal_senders = 5
    wal_level = archive
    archive_mode = on
    archive_command = 'cp %p /home/postgres/archives/%f'

Edit "pg_hba.conf".

    host    all             all  192.168.1.200/32       trust
    host    replication     all  192.168.1.200/32       trust


Extract `pg_bman` to contrib directory, and run make and make install.

    $ cd ~/contrib/
    $ unzip pg_bman.zip
    $ cd pg_bman
    $ make && make install
    
    $ psql sampledb
    psql (9.3.0)
    Type "help" for help.
    
    sampledb=# CREATE EXTENSION pg_bman;

### on Backup Server

Install PostgreSQL binary and the source code (here, installation directories are "/usr/local/pgsql/" and "/usr/local/src/postgresql/").

Extract `pg_bman` to contrib directory, and run make.

    $ cd /usr/local/src/postgresql/contrib/
    $ unzip pg_bman.zip
    $ cd pg_bman
    $ make

Copy `pg_backup.sh` and `pg_arcivebackup` to the directory you like (here, installation directory is "/usr/local/bin").

    $ cp pg_archivebackup /usr/local/bin
    $ cp pg_bman.sh /usr/local/bin
    $ chmod +x /usr/local/bin/pg_bman.sh


Create backup repository (here, "home/postgres/BACKUP").

    $ mkdir /home/postgres/BACKUP

Set the parameters on `pg_bman.sh`. Absolute paths only.

    ##-------------------------
    ## Backup Server 
    ##-------------------------
    REPOSITORY="/home/postgres/BACKUP"
    PG_ARCHIVEBACKUP="/usr/local/bin/pg_archivebackup"
    PGHOME="/usr/local/pgsql"
    PG_BASEBACKUP=$PGHOME/bin/pg_basebackup
    RECOVERY_CONF_SAMPLE=$PGHOME/share/recovery.conf.sample
    
    ##-------------------------
    ## PostgreSQL Server
    ##-------------------------
    ARCHIVINGLOG_DIR="/usr/local/pgsql/data/archives"
    
    HOST="127.0.0.1"
    DB="sampledb"
    USER="postgres"
    PORT="5432"

    # archival storage directory which to be written to the restore_command on recovery.conf
    ARCHIVAL_STORAGE_DIR="/home/postgres/restore_archives"


## HOW TO USE

### FULL BACKUP

    $ pg_bman.sh BACKUP FULL

#### INCREMENTAL BACKUP

    $ pg_bman.sh BACKUP INCREMENTAL

### SHOW BACKUP LIST

    $ pg_bman.sh SHOW

### RESTORE

#### step1: Choose `Basebackup_no` and `Incrementalbackup_no`.

Choose `Basebackup_no` and `Incrementalbackup_no` for doing PITR.

    $ pg_bman.sh SHOW
    1:Basebackup20140710-200012 (TimeLineID=00000001)
           0:Fullbackup
     Incremental:
           1:20140710-201046
           2:20140710-202041
    2:Basebackup20140710-210018 (TimeLineID=00000001)
           0:Fullbackup
      Incremental:
           1:20140710-212040
    3:Basebackup20140710-220009 (TimeLineID=00000001)
           0:Fullbackup
      Incremental:
           1:20140711-221013
           2:20140711-222023  <-- Our choice.
           3:20140711-223011
           4:20140711-224041

Here, we choose `basebackup_no = 3`, and `incrementalbackup_no = 2` (timestamp=20140711-222023).

#### step2: Prepare BaseBackup, archivinglogs, and recovery.conf

RESTORE command sets up base backup, archiving logs you need, and recovery.conf under "$REPOSITORY/Restore" directory.

    $ pg_bman.sh RESTORE 3 2
    MESSAGE: RESTORE preparation done

#### step3: Restore

    How to restore:
      (1) make $PGDATA
            mkdir $PGDATA && chmod 700 $PGDATA
            cd $PGDATA
            tar xvfz $REPOSITORY/Restore/basebackup/base.tar.gz
      (2) copy recovery.conf
            cp $REPOSITORY/Restore/recovery.conf $PGDATA
      (3) set archiving logs
            mkdir $RESTORE_ARICHIVINGLOG_DIR
            cp  $REPOSITORY/Restore/incrementalbackup/* $RESTORE_ARICHIVINGLOG_DIR
