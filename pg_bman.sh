#!/bin/bash
#===========================================
# pg_bman.sh
#
# pg_bman.sh BACKUP {FULL|INCREMENTAL}
# pg_bman.sh SHOW
# pg_bman.sh RESOTRE fullbackup_no [incrementalbuckup_no]
#
# This software is released under the PostgreSQL Licence
# Author: suzuki hironobu (hironobu@interdb.jp)
# Copyright (C) 2014  suzuki hironobu
#===========================================
##-------------------------
## Backup Server
##-------------------------
# "absolute path only"
BASEDIR="/home/postgres/BACKUP"
PG_ARCHIVEBACKUP="/usr/local/bin/pg_archivebackup"
PGHOME="/usr/local/pgsql"
PG_BASEBACKUP=$PGHOME/bin/pg_basebackup
RECOVERY_CONF_SAMPLE=$PGHOME/share/recovery.conf.sample

##-------------------------
## PostgreSQL Server
##-------------------------
# "absolute path only"
ARCHIVINGLOG_DIR="/home/postgres/archives"

HOST="127.0.0.1"
DB="sampledb"
USER="postgres"
PORT="5432"

RESTORE_ARICHIVINGLOG_DIR="/home/postgres/restore_archives"

##===========================================
## Global Variables
##===========================================
declare -i VERBOSE
VERBOSE=1
GZIP_MODE="ON"

ARCHIVINGLOGS=""
BASE_TIMELINE=""
CURRENT_ARCHVINGLOGS=""
CURRENT_TIMELINES=""

declare -i BB
declare -i IB

TIMESTAMP=`date '+%Y%m%d-%H%M%S'`
PGNAME="pg_bman.sh"

##===========================================
## utils
##===========================================

usage () {
    echo "Usage: $PGNAME command [options]"
    echo "   command:"
    echo "       BACKUP"
    echo "         $PGNAME BACKUP {FULL|INCREMENTAL}"
    echo "       SHOW"
    echo "         $PGNAME SHOW"
    echo "       RESTORE"
    echo "         $PGNAME RESTORE full_backup_no [incremental_buckup_no]"
}

get_basebackups () {
    basebackups=`ls -d $BASEDIR/Basebackup* | sort`
    if [[ ! $basebackups ]]; then
	echo "Error: Basebackup not found."
	exit -1
    fi
    echo $basebackups
}

##===========================================
## Full backup
##===========================================
full_backup () {
    v=""
    basebackup_dir=${BASEDIR}/Basebackup${TIMESTAMP}
    mkdir -p $basebackup_dir/fullbackup
    if [[ $VERBOSE -gt 0 ]]; then
	echo "INFO: Make directory:$basebackup_dir/fullbackup"
	v="-v"
    fi

    ## execute pg_basebackup
    if [[ $VERBOSE -gt 0 ]]; then
	echo "INFO: Execute pg_basebackup"
    fi
    $PG_BASEBACKUP -h $HOST -U $USER -F t -X fetch -D $basebackup_dir/fullbackup $v

    ## write pg_xlog contents.
    tar tf $basebackup_dir/fullbackup/base.tar | grep pg_xlog | \
	awk -F/ '{if ($2 != "") print $2}'  > $basebackup_dir/fullbackup/.pg_xlog

    ## gzip
    if [[ $GZIP_MODE = "ON" ]]; then
	if [[ $VERBOSE -gt 0 ]]; then
	    echo "INFO: Compressing $basebackup_dir/fullbackup/base.tar using gzip."
	fi
	gzip $basebackup_dir/fullbackup/base.tar
    fi

    echo "MESSAGE: FULL BACKUP done."
}

##===========================================
## Incremental backup
##===========================================
listup_archivinglogs () {
    latest_basebackup=$1
    # base backup
    base_archivinglogs=`cat $latest_basebackup/fullbackup/.pg_xlog`
    BASE_TIMELINE=`echo -e "$base_archivinglogs" | cut -c 1-8 | sort -r | uniq | head -1`

    # incremental backup
    inc_archivinglogs=`ls -1 -d $latest_basebackup/incrementalbackup*/* 2>/dev/null | awk -F/ '{print $NF}'`

    # merge all archiving logs
    ARCHIVINGLOGS=`echo -e "${base_archivinglogs}\n${inc_archivinglogs}" | sort | sed '/^$/d' | uniq`
}

listup_current_archivinglogs () {
    CURRENT_ARCHVINGLOGS=`$PG_ARCHIVEBACKUP -h $HOST -U $USER -d $DB \
	-c show -a $ARCHIVINGLOG_DIR | grep -v backup`
    if [[ $? -ne 0 ]]; then
	echo "Error: Could not execute pg_show_archives()"
	exit -1
    fi  
    CURRENT_TIMELINES=`echo -e "$CURRENT_ARCHVINGLOGS" | cut -c 1-8 | sort | uniq`
}

get_archivinglog () {
    num_log=$1
    incrementalbackupdir=$2
    segment=$3

    ${PG_ARCHIVEBACKUP} -h ${HOST} -U ${USER} -d ${DB} -c get \
	-a ${ARCHIVINGLOG_DIR} -w ${segment} -f ${incrementalbackupdir}/${segment}
    if [[ $? -ne 0 ]]; then
	echo "ERROR: Could not get $segment"
	exit -1
    else
	num_log=$num_log+1
	if [[ $VERBOSE -gt 0 ]]; then
	    echo "INFO:backup $segment to $incrementalbackupdir"
	fi
    fi
    return $num_log
}

make_incremantal_backup_dir () {
    incrementalbackupdir=$1

    if [[ ! -d $incrementalbackupdir ]]; then
	mkdir -p $incrementalbackupdir
	if [[ $VERBOSE -gt 0 ]]; then
	    echo "INFO: make directory:$incrementalbackupdir"
	fi
    fi
}

incremental_backup () {
    declare -i num_log
    num_log=0
    ## Latest Basebackup directory
    latest_basebackup=`ls -d $BASEDIR/Basebackup* | sort -r | head -1`
    if [[ ! $latest_basebackup ]]; then
	echo "Error: Basebackup not found."
	exit -1
    fi
    incrementalbackupdir=${latest_basebackup}/incrementalbackup${TIMESTAMP}    

    ## list up stored WAL segments.
    listup_archivinglogs $latest_basebackup

    ## execute pg_switch_xlog()
    $PG_ARCHIVEBACKUP -h $HOST -U $USER -d $DB -c switch
    if [[ $? -ne 0 ]]; then
	echo "Error: Could not execute pg_switch_xlog()"
	exit -1
    fi  

    ## list up current archiveing logs
    listup_current_archivinglogs

    ## get new archiving logs
    for current_tl in $CURRENT_TIMELINES ;do
	if [[ $current_tl -eq $BASE_TIMELINE ]]; then
	    latest_segment=`echo -e "$ARCHIVINGLOGS" | grep ^$current_tl | sort -r | head -1`
	    for segment in `echo -e "$CURRENT_ARCHVINGLOGS" | grep ^$current_tl | sort -r` ; do
		if [[ $latest_segment < $segment ]]; then

		    make_incremantal_backup_dir $incrementalbackupdir

		    get_archivinglog $num_log $incrementalbackupdir $segment
		    num_log=$?
		fi
	    done
	fi
    done
    
    if [[ $VERBOSE -gt 0 ]]; then
	if [[ $num_log = 0 ]]; then
	    echo "INFO: There is no new archivinglog. Nothing done."
	else
	    echo "INFO: Back up $num_log archiving logs."
	fi
    fi    
    echo "MESSAGE: INCREMENTAL BACKUP done."
}

##===========================================
## SHOW
##===========================================
show () {
    BB=1
    ## find Basebackup directories
    basebackups=`get_basebackups`

    ## show all directories
    for basedir in `echo -e "$basebackups"`; do
	timeline=`cat $basedir/fullbackup/.pg_xlog | cut -c 1-8 | sort -r | uniq | head -1`
	base=`echo $basedir | awk -F/ '{print $NF}'`
	echo "$BB:$base (TimeLineID=$timeline)"
	echo "       0:Fullbackup"
	IB=1
	incbackups=`ls -1 -d $basedir/incrementalbackup*  2>/dev/null | sort`
	if [[ $incbackups ]]; then
	    echo "  Incremental:"
	    for incdir in `echo -e "$incbackups"`; do
		inc=`echo $incdir | awk -F/ '{print $NF}'| sed s/incrementalbackup//`
		echo "       $IB:$inc"
		IB=$IB+1
	    done
	fi
	BB=$BB+1
    done
}

##===========================================
## RESTORE
##===========================================
prepare_base_backup () {
    basedir=$1

    if [[ -f $basedir/fullbaskup/base.tar ]]; then
	ln -s $basedir/fullbackup/base.tar $BASEDIR/Restore/basebackup/
    elif [[ -f $basedir/fullbackup/base.tar.gz ]]; then
	ln -s $basedir/fullbackup/base.tar.gz $BASEDIR/Restore/basebackup/
    else
	echo "ERROR: There is no base backup in $basedir/fullbackup/"
	exit -1
    fi
}

prepare_incremental_backup () {
    basedir=$1
    incremental_backup_no=$2

    if [[ $incremental_backup_no -ne 0 ]]; then
	IB=1
	for incdir in `ls -1 -d $basedir/incrementalbackup*  2>/dev/null | sort`; do
	    if [[ $IB -le $incremental_backup_no ]]; then
		for file in `ls $incdir/*`; do
		    ln -s $file $BASEDIR/Restore/incrementalbackup/
		done
	    fi
	    IB=$IB+1
	done
    fi
}

init_restore_dir () {
    if [[ ! -d $BASEDIR/Restore/basebackup ]]; then
	mkdir -p $BASEDIR/Restore/basebackup
    fi
    if [[ ! -d $BASEDIR/Restore/incrementalbackup ]]; then
	mkdir -p $BASEDIR/Restore/incrementalbackup
    fi

    rm -f $BASEDIR/Restore/basebackup/*
    rm -f $BASEDIR/Restore/recovery.conf
    rm -f $BASEDIR/Restore/incrementalbackup/*
}

make_recovery_conf () {
    if [[ ! -f $RECOVERY_CONF_SAMPLE ]]; then
	echo "WARNING: recovery.conf.sample no found"
    else
	cat $RECOVERY_CONF_SAMPLE \
	    | sed -e "s@\#restore_command =@restore_command = \'cp $RESTORE_ARICHIVINGLOG_DIR/%f %p\' \#@g" \
	    > $BASEDIR/Restore/recovery.conf
    fi
}

how_to_restore () {
    echo "How to restore:"
    echo "  (1) make \$PGDATA"
    echo "        mkdir \$PGDATA && chmod 700 \$PGDATA"
    echo "        cd \$GPDATA"
    if [[ $GZIP_MODE = "ON" ]]; then
	echo "        tar xvfz $BASEDIR/Restore/basebackup/base.tar.gz"
    else
	echo "        tar xvf $BASEDIR/Restore/basebackup/base.tar"
    fi
    echo "  (2) copy recovery.conf"
    echo "        cp $BASEDIR/Restore/recovery.conf"
    echo "  (3) set archiving logs"
    echo "        mkdir $RESTORE_ARICHIVINGLOG_DIR"
    echo "        cp  $BASEDIR/Restore/incrementalbackup/* $RESTORE_ARICHIVINGLOG_DIR"
}

restore () {
    declare -i base_backup_no
    declare -i incremental_backup_no

    base_backup_no=$1
    incremental_backup_no=$2
    BB=1
    
    ## init
    init_restore_dir

    ## find base backup
    basebackups=`get_basebackups`

    for basedir in `echo -e "$basebackups"`; do
	if [[ $base_backup_no -eq $BB ]]; then
	    prepare_base_backup $basedir
	    prepare_incremental_backup $basedir $incremental_backup_no
	    make_recovery_conf

	    echo "MESSAGE: RESTORE preparation done"
	    how_to_restore
	    exit 0
	fi
	BB=$BB+1
    done

    echo "ERROR: BASEBACKUP No.$base_backup_no not exist."
    exit -1
}

##===========================================
## Main
##===========================================
COMMAND=$1

if [[ $COMMAND = "BACKUP" ]]; then
    if [[ $# -eq 2 ]]; then
	if [[ $2 = "FULL" ]]; then
	    full_backup	
	elif [[ $2 = "INCREMENTAL" ]]; then
	    incremental_backup
	else
	    echo "SYNTAX ERROR"
	    usage
	    exit -1
	fi
    else
	echo "SYNTAX ERROR"
	usage
	exit -1
    fi
    
elif [[ $COMMAND = "SHOW" ]]; then
    show

elif [[ $COMMAND = "RESTORE" ]]; then
    if [[ $# -eq 3 ]]; then
	# $2=FULL_BACKUP_NO, $3=INCREMENTAL_BACKUP_NO
	restore $2 $3
    elif [[ $# -eq 2 ]]; then
	restore $2 0
    else
	echo "SYNTAX ERROR"
	usage
	exit -1
    fi
else
    echo "SYNTAX ERROR"
    usage
    exit -1
fi

exit 0
