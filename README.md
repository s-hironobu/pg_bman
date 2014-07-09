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


pg_bman.shにいくつかのパラメータを設定。

    ##-------------------------
    ## Backup Server 
    ##-------------------------

    BASEDIR="/home/postgres/BACKUP"
    PG_BASEBACKUP="/usr/local/pgsql/bin/pg_basebackup"
    PG_ARCHIVEBACKUP="/usr/local/bin/pg_archivebackup"
    
    ##-------------------------
    ## PostgreSQL Server
    ##-------------------------
    ARCHIVINGLOG_DIR="/usr/local/pgsql/data/archives"
    
    HOST="127.0.0.1"
    DB="sampledb"
    USER="postgres"
    PORT="5432"



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

未実装。


