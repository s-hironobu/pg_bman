pg_bman
=======

Yet another backup tool for PostgreSQL

リモートホストにバックアップできるpg_rmanみたいなツール。

sshを使わず、標準の通信手段(libpq)だけでオンラインのフルバックアップとインクリメンタルバックアップするにはどうすべきか、検討するため、とりあえず大急ぎで作ってみた。


## SETUP

### PostgreSQL Server側

アーカイブログ領域を作成。

    $ mkdir /home/postgres/archives


postgresql.confを編集。

    max_wal_senders = 5
    wal_level = hot_standby # or archive
    archive_mode = on
    archive_command = 'cp %p /home/postgres/archives/%f'


pg_hba.confの編集。

    host    all             all  xxx.xxx.xxx.0/24       trust # バックアップServerからアクセス
    host    replication     all  xxx.xxx.xxx.0/24       trust #　バックアップServerからアクセス


Extensionのインストール。アーカイブログ領域を$PGDATA以下にする場合は、このExtensionのインストールは不要。

    $ cd ~/contrib/
    $ unzip pg_bman.zip
    $ cd pg_bman
    $ make && make install


    $ psql sampledb
    psql (9.3.0)
    Type "help" for help.

    sampledb=# CREATE EXTENSION pg_bman;



### Backup Server側

PostgreSQLをインストールしておく。ここではインストール領域は/usr/local/pgsqlと仮定。
ソースコードも準備しておく。ここでは/usr/local/src/postgresqlと仮定。


pg_bmanをソースコードのcontribで展開し、makeを実行。

    $ cd ~/contrib/
    $ unzip pg_bman.zip
    $ cd pg_bman
    $ make

適当なディレクトリにpg_arcivebackupとpg_backup.shをcopy。

    $ cp pg_archivebackup /usr/local/bin
    $ cp pg_bman.sh /usr/local/bin
    $ chmod +x /usr/local/bin/pg_bman.sh

バックアップ領域を決めてディレクトリを作成。ここでは/home/postgres/BACKUPとする。

    $ mkdir /home/postgres/BACKUP


pg_bman.shにいくつかのパラメータを設定。pathはabsolute pathのみ。

    ##-------------------------
    ## Backup Server 
    ##-------------------------
    BASEDIR="/home/postgres/BACKUP"
    PG_ARCHIVEBACKUP="/usr/local/bin/pg_archivebackup"
    PGHOME="/usr/local/pgsql93"
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

    # restoreのときに使うアーカイブログを置くディレクトリ。この値をrecovery.confのrestore_commandに書き込む。
    RESTORE_ARICHIVINGLOG_DIR="/home/postgres/restore_archives"

もしもアーカイブログ領域が$PGDATA内なら、pg_archivebackupコマンドに-oオプションをつけてもよい。"-o"オプションはpg_ls_dir()とpg_read_binary_file()を使う(よってExtensionが不要)。

    PG_ARCHIVEBACKUP="/usr/local/bin/pg_archivebackup -o "


## 使い方

### FULL BACKUP

    $ pg_bman.sh BACKUP FULL


#### INCREMENTAL BACKUP


    $ pg_bman.sh BACKUP INCREMENTAL


### SHOW BACKUP LIST

    $ pg_bman.sh SHOW


### RESTORE

#### 調査
SHOWコマンドで、リストアするベースバックアップとインクリメントバックアップの番号を選ぶ。

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
           2:20140711-222023
           3:20140711-223011
           4:20140711-224041

#### 準備
BaseBackup=3, Incrementalbackup=2  (timestamp=20140711-222023)にPITRする。

    $ pg_bman.sh RESTORE 3 2
    MESSAGE: RESTORE preparation done

#### リストア
RESTOREコマンドを実行すると、ベースバックアップ、recovery.conf、必要なアーカイブログが"$BASEDIR/Restore"以下に生成するので、指示に従ってリカバリする。

    How to restore:
      (1) make $PGDATA
            mkdir $PGDATA && chmod 700 $PGDATA
            cd $GPDATA
            tar xvfz $BASEDIR/Restore/basebackup/base.tar.gz
      (2) copy recovery.conf
            cp $BASEDIR/Restore/recovery.conf
      (3) set archiving logs
            mkdir /home/postgres/restore_archives
            cp  $BASEDIR/Restore/incrementalbackup/* $RESTORE_ARICHIVINGLOG_DIR
