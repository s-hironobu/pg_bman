pg_bman
=======

Yet another hot back up tool for PostgreSQL. 


`pg_bman` is similar to [pg_rman](http://sourceforge.net/projects/pg-rman/), but can take a backup from a remote server.
`pg_bman` is similar to [pgbarman](http://www.pgbarman.org/), but requires neither ssh nor rsync for take a backup.

>Notice: To restore a database, ftp or scp is required.

リモートホストにバックアップできるpg_rmanみたいなツール。
標準の通信プロトコル(libpq)だけでオンラインのフルバックアップとインクリメンタルバックアップができます。sshもrsyncもftpも不要です。

## SETUP

      PostgreSQL    BackupServer
    192.168.1.100   192.168.1.200
      +---+    libpq    +---+
      |   |============>|   |
      +---+             +---+


### on PostgreSQL Server

#### Step1: Make an archiving log directory.

If you can make an archiving log directory under $PGDATA, make there.

    $ mkdir /usr/local/pgsql/data/archives

If you cannot make it under $PGDATA, make a directory where you can, and link to under $PGDATA.

    $ mkdir /home/postgres/archives
    $ ln -s /home/postgres/archives /usr/local/pgsql/data/archives

If you cannot link to a directory under $PGDATA, make a directory where you can, and install the pg_bman extension.

    $ mkdir /home/postgres/archives

Unzip `pg_bman.zip` to the contrib directory, make && make install.

    $ cd ~/contrib/
    $ unzip pg_bman.zip
    $ cd pg_bman
    $ make && make install
    
    $ psql sampledb
    psql (9.3.0)
    Type "help" for help.
    
    sampledb=# CREATE EXTENSION pg_bman;

#### Step2: Edit "postgresql.conf".

    max_wal_senders = 5
    wal_level = archive
    archive_mode = on
    archive_command = 'cp %p /usr/local/pgsql/data/archives/%f'

#### Step3: Edit "pg_hba.conf".

    host    all             all  192.168.1.200/32       trust
    host    replication     all  192.168.1.200/32       trust

### on Backup Server

#### Step1: Install programs.
Assume that the PostgreSQL binary and the source code installed (here, installation directories are "/usr/local/pgsql/" and "/usr/local/src/postgresql/").

Unzip `pg_bman` to the contrib directory, make.

    $ cd /usr/local/src/postgresql/contrib/
    $ unzip pg_bman.zip
    $ cd pg_bman
    $ make

Copy `pg_bman` and `pg_arcivebackup` to a directory where you like (here, installation directory is "/usr/local/bin").

    $ cp pg_archivebackup /usr/local/bin
    $ cp pg_bman /usr/local/bin
    $ chmod +x /usr/local/bin/pg_bman

#### Step2: Create a backup repository.
Here, "home/postgres/BACKUP" is a repository directory.

    $ mkdir /home/postgres/BACKUP

#### Step3: Set parameters on `pg_bman`.
Absolute paths only. Do not forget to check "EXTENSION_MODE".

    ##-------------------------
    ## Global Options
    ##-------------------------
    # If you installed the pg_bman extension on the PostgreSQL, set "ON"
    EXTENSION_MODE="OFF"
    GZIP_MODE="ON"

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
    PGDATA="/usr/local/pgsql/data"
    ARCHIVINGLOG_DIR=$PGDATA/archives
    
    HOST="127.0.0.1"
    DB="sampledb"
    USER="postgres"
    PORT="5432"
    PASSWORD=""

    # This directory is written to the restore_command on a recovery.conf.
    ARCHIVAL_STORAGE_DIR="/home/postgres/restore_archives"


## HOW TO USE

### BACKUP
#### FULL BACKUP

    $ pg_bman BACKUP FULL

#### INCREMENTAL BACKUP

    $ pg_bman BACKUP INCREMENTAL

### SHOW BACKUP LIST

    $ pg_bman SHOW

### RESTORE

#### step1: Choose `Basebackup_no` and `Incrementalbackup_no`.

    $ pg_bman SHOW
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

#### step2: Execute pg_bman RESTORE.

RESTORE command sets up a base backup, archive logs you need, and a recovery.conf file under the "$REPOSITORY/Restore" directory.

    $ pg_bman RESTORE 3 2

#### step3: Restore on the PostgreSQL server.

    How to restore your PostgreSQL:
      (1) Make a database cluster.
            mkdir $PGDATA && chmod 700 $PGDATA
            cd $PGDATA
            scp BackupServer:$REPOSITORY/Restore/basebackup/base.tar.gz .
            tar xvfz base.tar.gz
      (2) Copy the recovery.conf file.
            scp BackupServer:$REPOSITORY/Restore/recovery.conf $PGDATA
      (3) Copy archive logs.
            mkdir $ARCHIVAL_STORAGE_DIR
            cd $ARCHIVAL_STORAGE_DIR
            scp  BackupServer:$REPOSITORY/Restore/incrementalbackup/* .
      (4) Start!
