#!/usr/bin/env bash
#
# Auto backup database to Google Drive script
#
# Copyright (C) 2018 DcTo
#
# URL: https://github.com/dcto/Backup2GDrive
#
# You must to modify the config before run it!!!
# Backup MySQL/MariaDB/Percona datebases, files and directories
# Backup file is encrypted with AES256-cbc with SHA1 message-digest (option)
# Auto transfer backup file to Google Drive (need install gdrive command) (option)
# Auto transfer backup file to FTP server (option)
# Auto delete Google Drive's or FTP server's remote file (option)
#

[[ $EUID -ne 0 ]] && echo "Error: This script must be run as root!" && exit 1

########## START OF CONFIG ##########

# Encrypt flag (true: encrypt, false: not encrypt)
# 是否加密
Encrypt=false

# WARNING: KEEP THE PASSWORD SAFE!!!
# The password used to encrypt the backup
# To decrypt backups made by this script, run the following command:
# openssl enc -aes256 -in [encrypted backup] -out decrypted_backup.tgz -pass pass:[backup password] -d -md sha1
# 加密密码
Password="backup_password"

# Directory to store backups
# 本地备份路径
LocalDir="/home/backup/"

# Temporary directory used during backup creation
# 临时备份路径
TempDir="/home/backup/tmp/"

# File to log the outcome of backups
# 日志文件
LogFile="/home/backup/RunTime.log"

# upload to google drive dir
# 保存到Google drive指定目录，留空为根目录
# ID 可通过 gdrive list -q "name contains 'test'" 获取
Google_Drive_Dir_ID=""

# OPTIONAL: If you want backup MySQL database, enter the MySQL root password below
# MYSQL ROOT 密码
MYSQL_ROOT_PASSWORD=""

# Below is a list of MySQL database name that will be backed up
# If you want backup ALL databases, leave it blank.
# 需要备份的数据库，留空备份全部
MYSQL_DATABASE_NAME[0]=""

# Below is a list of files and directories that will be backed up in the tar backup
# For example:
# File: /data/www/default/test.php
# Directory: /data/www/default/test

BACKUP[0]=""

# Number of days to store daily local backups (default 7 days)
# 保留本地备份文件
LocalSaveDays="7"

# Delete Google Drive's & FTP server's remote file flag (true: delete, false: not delete)
# 删除Google Drive 同名文件
DELETE_REMOTE_FILE=false

# Upload to FTP server flag (true: upload, false: not upload)
# 上传到FTP
FTP=false

# FTP server
# OPTIONAL: If you want upload to FTP server, enter the Hostname or IP address below
# FTP IP地址
FTP_HOST=""

# FTP username
# OPTIONAL: If you want upload to FTP server, enter the FTP username below
# FTP帐号
FTP_USER=""

# FTP password
# OPTIONAL: If you want upload to FTP server, enter the username's password below
FTP_PASS=""

# FTP server remote folder
# OPTIONAL: If you want upload to FTP server, enter the FTP remote folder below
# For example: public_html
FTP_DIR=""

########## END OF CONFIG ##########





# Date & Time
DAY=$(date +%d)
MONTH=$(date +%m)
YEAR=$(date +%C%y)
BACKUPDATE=$(date +%Y%m%d%H%M%S)
# Backup file name
TARFILE="${LocalDir}""$(hostname)"_"${BACKUPDATE}".tgz
# Encrypted backup file name
ENC_TARFILE="${TARFILE}.enc"
# Backup MySQL dump file name
SQLFILE="${TempDir}mysql_${BACKUPDATE}.sql"

log() {
    echo "$(date "+%Y-%m-%d %H:%M:%S")" "$1"
    echo -e "$(date "+%Y-%m-%d %H:%M:%S")" "$1" >> ${LogFile}
}

# Check for list of mandatory binaries
check_commands() {
    # This section checks for all of the binaries used in the backup
    BINARIES=( cat cd du date dirname echo openssl mysql mysqldump pwd rm tar )

    # Iterate over the list of binaries, and if one isn't found, abort
    for BINARY in "${BINARIES[@]}"; do
        if [ ! "$(command -v "$BINARY")" ]; then
            log "$BINARY is not installed. Install it and try again"
            exit 1
        fi
    done

    # check gdrive command
    GDrive_Command=false
    if [ "$(command -v "gdrive")" ]; then
        GDrive_Command=true
    fi

    # check ftp command
    if ${FTP}; then
        if [ ! "$(command -v "ftp")" ]; then
            log "ftp is not installed. Install it and try again"
            exit 1
        fi
    fi
}

calculate_size() {
    local file_name=$1
    local file_size=$(du -h $file_name 2>/dev/null | awk '{print $1}')
    if [ "x${file_size}" = "x" ]; then
        echo "unknown"
    else
        echo "${file_size}"
    fi
}

# Backup MySQL databases
mysql_backup() {
    if [ -z ${MYSQL_ROOT_PASSWORD} ]; then
        log "MySQL root password not set, MySQL backup skipped"
    else
        log "MySQL dump start"
        mysql -u root -p"${MYSQL_ROOT_PASSWORD}" 2>/dev/null <<EOF
exit
EOF
        if [ $? -ne 0 ]; then
            log "MySQL root password is incorrect. Please check it and try again"
            exit 1
        fi

        if [ "${MYSQL_DATABASE_NAME[*]}" == "" ]; then
            mysqldump -u root -p"${MYSQL_ROOT_PASSWORD}" --all-databases > "${SQLFILE}" 2>/dev/null
            if [ $? -ne 0 ]; then
                log "MySQL all databases backup failed"
                exit 1
            fi
            log "MySQL all databases dump file name: ${SQLFILE}"
            #Add MySQL backup dump file to BACKUP list
            BACKUP=(${BACKUP[*]} ${SQLFILE})
        else
            for db in ${MYSQL_DATABASE_NAME[*]}
            do
                unset DBFILE
                DBFILE="${TempDir}${db}_${BACKUPDATE}.sql"
                mysqldump -u root -p"${MYSQL_ROOT_PASSWORD}" ${db} > "${DBFILE}" 2>/dev/null
                if [ $? -ne 0 ]; then
                    log "MySQL database name [${db}] backup failed, please check database name is correct and try again"
                    exit 1
                fi
                log "MySQL database name [${db}] dump file name: ${DBFILE}"
                #Add MySQL backup dump file to BACKUP list
                BACKUP=(${BACKUP[*]} ${DBFILE})
            done
        fi
        log "MySQL dump completed"
    fi
}

start_backup() {
    [ "${BACKUP[*]}" == "" ] && echo "Error: You must to modify the [$(basename $0)] config before run it!" && exit 1

    log "Tar backup file start"
    tar -zcPf ${TARFILE} ${BACKUP[*]}
    if [ $? -gt 1 ]; then
        log "Tar backup file failed"
        exit 1
    fi
    log "Tar backup file completed"

    # Encrypt tar file
    if ${Encrypt}; then
        log "Encrypt backup file start"
        openssl enc -aes256 -in "${TARFILE}" -out "${ENC_TARFILE}" -pass pass:"${Password}" -md sha1
        log "Encrypt backup file completed"

        # Delete unencrypted tar
        log "Delete unencrypted tar file: ${TARFILE}"
        rm -f ${TARFILE}
    fi

    # Delete MySQL temporary dump file
    for sql in `ls ${TempDir}*.sql`
    do
        log "Delete MySQL temporary dump file: ${sql}"
        rm -f ${sql}
    done

    if ${Encrypt}; then
        OUT_FILE="${ENC_TARFILE}"
    else
        OUT_FILE="${TARFILE}"
    fi
    log "File name: ${OUT_FILE}, File size: `calculate_size ${OUT_FILE}`"
}

# Transfer backup file to Google Drive
# If you want to install gdrive command, please visit website:
# https://github.com/prasmussen/gdrive
# of cause, you can use below command to install it
# For x86_64: wget -O /usr/bin/gdrive http://dl.lamp.sh/files/gdrive-linux-x64; chmod +x /usr/bin/gdrive
# For i386: wget -O /usr/bin/gdrive http://dl.lamp.sh/files/gdrive-linux-386; chmod +x /usr/bin/gdrive
gdrive_upload() {
    if ${GDrive_Command}; then
        log "Uploading backup file to Google Drive."
        if ["${Google_Drive_Dir_ID}" == ""]; then
            gdrive upload  --no-progress ${OUT_FILE} >> ${LogFile}
        else
            gdrive upload  --parent ${Google_Drive_Dir_ID} --no-progress ${OUT_FILE} >> ${LogFile}
        fi

        if [ $? -ne 0 ]; then
            log "Error: upload backup file to Google Drive failed."
            exit 1
        fi
        log "Upload backup file to Google Drive completed."
    fi
}

# Tranferring backup file to FTP server
ftp_upload() {
    if ${FTP}; then
        [ -z ${FTP_HOST} ] && log "Error: FTP_HOST can not be empty!" && exit 1
        [ -z ${FTP_USER} ] && log "Error: FTP_USER can not be empty!" && exit 1
        [ -z ${FTP_PASS} ] && log "Error: FTP_PASS can not be empty!" && exit 1
        [ -z ${FTP_DIR} ] && log "Error: FTP_DIR can not be empty!" && exit 1

        local FTP_OUT_FILE=$(basename ${OUT_FILE})
        log "Tranferring backup file to FTP server"
        ftp -inp ${FTP_HOST} 2>&1 >> ${LogFile} <<EOF
user $FTP_USER $FTP_PASS
binary
lcd $LOCALDIR
cd $FTP_DIR
put $FTP_OUT_FILE
quit
EOF
        log "Tranferring backup file to FTP server completed"
    fi
}

# Get file date
get_file_date() {
    #Approximate a 30-day month and 365-day year
    DAYS=$(( $((10#${YEAR}*365)) + $((10#${MONTH}*30)) + $((10#${DAY})) ))

    unset FileYear FileMonth FILEDAY FileDays FileTime
    FileYear=$(echo "$1" | cut -d_ -f2 | cut -c 1-4)
    FileMonth=$(echo "$1" | cut -d_ -f2 | cut -c 5-6)
    FileDay=$(echo "$1" | cut -d_ -f2 | cut -c 7-8)

    if [[ "${FileYear}" && "${FileMonth}" && "${FileDay}" ]]; then
        #Approximate a 30-day month and 365-day year
        FileDays=$(( $((10#${FileYear}*365)) + $((10#${FileMonth}*30)) + $((10#${FileDay})) ))
        FileTime=$(( 10#${DAYS} - 10#${FileDays} ))
        return 0
    fi

    return 1
}

# Delete Google Drive's old backup file
delete_gdrive_file() {
    local FileName=$1
    if ${DELETE_REMOTE_FILE} && ${GDrive_Command}; then
        local FileID=$(gdrive list -q "name = '${FileName}'" --no-header | awk '{print $1}')
        if [ -n ${FileID} ]; then
            gdrive delete ${FileID} >> ${LogFile}
            log "Google Drive's old backup file name: ${FileName} has been deleted"
        fi
    fi
}

# Delete FTP server's old backup file
delete_ftp_file() {
    local FileName=$1
    if ${DELETE_REMOTE_FILE} && ${FTP}; then
        ftp -in ${FTP_HOST} 2>&1 >> ${LogFile} <<EOF
user $FTP_USER $FTP_PASS
cd $FTP_DIR
del $FileName
quit
EOF
        log "FTP server's old backup file name: ${FileName} has been deleted"
    fi
}

# Clean up old file
clean_up_files() {
    cd ${LocalDir} || exit

    if ${Encrypt}; then
        LS=($(ls *.enc))
    else
        LS=($(ls *.tgz))
    fi

    for f in ${LS[@]}
    do
        get_file_date ${f}
        if [ $? == 0 ]; then
            if [[ ${FileTime} -gt ${LocalSaveDays} ]]; then
                rm -f ${f}
                log "Old backup file name: ${f} has been deleted"
                delete_gdrive_file ${f}
                delete_ftp_file ${f}
            fi
        fi
    done
}

# Main progress
StartTime=$(date +%s)

# Check if the backup folders exist and are writeable
if [ ! -d "${LocalDir}" ]; then
    mkdir -p ${LocalDir}
fi
if [ ! -d "${TempDir}" ]; then
    mkdir -p ${TempDir}
fi

log "Backup progress start"
check_commands
mysql_backup
start_backup
log "Backup progress complete"

log "Upload progress start"
gdrive_upload
ftp_upload
log "Upload progress complete"

clean_up_files

OverTime=$(date +%s)
DURATION=$((OverTime - StartTime))
log "All done"
log "Backup and transfer completed in ${DURATION} seconds"
log "=======================END=========================="
log "\r\n"