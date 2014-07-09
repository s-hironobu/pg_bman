#!/bin/bash
#===========================================
# pg_bman.sh
#
# pg_bman.sh BACKUP FULL
# pg_bman.sh BACKUP INCREMENTAL
# pg_bman.sh SHOW
#
# pg_bman.sh RESOTRE (Not Implemented)
#
# This software is released under the PostgreSQL Licence
# Author: suzuki hironobu (hironobu@interdb.jp)
# Copyright (C) 2014  suzuki hironobu
#===========================================
declare -i VERBOSE
VERBOSE=1
GZIP_MODE="ON"

##-------------------------
## Backup Server
##-------------------------
BASEDIR="/home/postgres/BACKUP/"
PG_BASEBACKUP="/usr/local/pgsql/bin/pg_basebackup"
PG_ARCHIVEBACKUP="/usr/local/bin/pg_archivebackup"

##-------------------------
## PostgreSQL Server
##-------------------------
ARCHIVINGLOG_DIR="/home/postgres/archives"

HOST="127.0.0.1"
DB="sampledb"
USER="postgres"
PORT="5432"

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
    base_archivinglogs=`tar tf $basebackup_dir/fullbackup/base.tar \
	| grep pg_xlog | awk -F/ '{if ($2 != "") print $2}'`
    echo "$base_archivinglogs" > $basebackup_dir/fullbackup/.pg_xlog

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
ARCHIVINGLOGS=""
BASE_TIMELINE=""
CURRENT_ARCHVINGLOGS=""
CURRENT_TIMELINES=""

listup_archivinglogs () {
    latest_basebackup=$1
    # base backup
    base_archivinglogs=`cat $latest_basebackup/fullbackup/.pg_xlog`
    BASE_TIMELINE=`echo -e "$base_archivinglogs" | cut -c 1-8 | sort | uniq | head -1`

    # incremental backup
    incbackup_archivinglogs=`ls -1 -d $latest_basebackup/incrementalbackup*/* 2>/dev/null`
    inc_archivinglogs=""
    if [[ $incbackup_archivinglogs ]]; then
	inc_archivinglogs=`echo "$incbackup_archivinglogs" | awk -F/ '{print $NF}'`
    fi
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

incremental_backup () {
    declare -i num_log
    num_log=0
## Latest Basebackup directory
    LATEST_BASEBACKUP=`ls -d $BASEDIR/Basebackup* | sort -r | head -1`
    if [[ ! $LATEST_BASEBACKUP ]]; then
	echo "Error: Basebackup not found."
	exit -1
    fi
    INCREMENTALBACKUPDIR=${LATEST_BASEBACKUP}/incrementalbackup${TIMESTAMP}    
    
## list up stored WAL segments.
    listup_archivinglogs $LATEST_BASEBACKUP
    
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
	    LATEST_SEGMENT=`echo -e "$ARCHIVINGLOGS" | grep ^$current_tl | sort -r | head -1`
	    for SEGMENT in `echo -e "$CURRENT_ARCHVINGLOGS" | grep ^$current_tl | sort -r` ; do
		if [[ $LATEST_SEGMENT < $SEGMENT ]]; then
		    if [[ ! -d $INCREMENTALBACKUPDIR ]]; then
			mkdir $INCREMENTALBACKUPDIR
			if [[ $VERBOSE -gt 0 ]]; then
			    echo "INFO: make directory:$INCREMENTALBACKUPDIR"
			fi
		    fi
		    # get ArchivingLog
		    ${PG_ARCHIVEBACKUP} -h ${HOST} -U ${USER} -d ${DB} -c get \
			-a ${ARCHIVINGLOG_DIR} -w ${SEGMENT} -f ${INCREMENTALBACKUPDIR}/${SEGMENT}
		    if [[ $? -ne 0 ]]; then
			echo "ERROR: Could not get $SEGMENT"
			exit -1
		    else
			num_log=$num_log+1
			if [[ $VERBOSE -gt 0 ]]; then
			    echo "INFO:backup $SEGMENT to $INCREMENTALBACKUPDIR"
			fi
		    fi
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
declare -i BB
declare -i IB

show () {
    BB=1
## find Basebackup directories
    BASEBACKUPS=`ls -d $BASEDIR/Basebackup* | sort`
    if [[ ! $BASEBACKUPS ]]; then
	echo "Error: Basebackup not found."
	exit -1
    fi
## show all directories
    for basedir in `echo -e "$BASEBACKUPS"`; do
	base=`echo $basedir | awk -F/ '{print $NF}'`
	echo "$BB:$base"
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
## Other functions
##===========================================
PGNAME="pg_bman.sh"

usage () {
    echo "Usage:"
    echo "  $PGNAME [BACKUP|SHOW|RESTORE] {FULL|INCREMENTAL}"
}

##===========================================
## Main
##===========================================
TIMESTAMP=`date '+%Y%m%d-%H%M%S'`

COMMAND=$1
MODE=""
if [[ $# -eq 2 ]]; then
    MODE=$2
fi

if [[ $COMMAND = "BACKUP" ]]; then
    if [[ $MODE = "FULL" ]]; then
	full_backup	
    elif [[ $MODE = "INCREMENTAL" ]]; then
	incremental_backup
    else
	echo "SYNTAX ERROR"
	usage
	exit -1
    fi

elif [[ $COMMAND = "SHOW" ]]; then
    show
elif [[ $COMMAND = "RESTORE" ]]; then
    echo "RESORE: Not Implemented"
else
    echo "SYNTAX ERROR"
    usage
    exit -1
fi

exit 0
