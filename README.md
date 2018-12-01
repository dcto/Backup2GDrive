# Backup2GDrive
Backup the Mysql/MariaDB/Percona Database To Google Drive

This script fork from https://github.com/teddysun/across/raw/master/backup.sh

The script support

1、Support MySQL/MariaDB/Percona all database and part of database;

2、Backup to directory and file；

3、Support encrypt the backup files (@openssl);

4、Upload to Google Drive（@gdrive);

5、Delete of the old files in local and remote files in Google Drive;


### 1、下载脚本
````
git clone https://github.com/dcto/Backup2GDrive
chmod +x Backup2GDrive.sh
````


### 2、配置说明

Encrypt （加密FLG，true 为加密，false 为不加密，默认是加密）

Password （加密密码，重要，务必要修改）

SaveDir （备份目录，可自己指定）

TempDir （备份目录的临时目录，可自己指定）

LogsFile （脚本运行产生的日志文件路径）

Google_Drive_Dir_ID (备份到Google Drive 批定目录 *需要获得目录ID)

MYSQL_ROOT_PASSWORD （MySQL/MariaDB/Percona 的root用户密码）

MYSQL_DATABASE_NAME （指定 MySQL/MariaDB/Percona 的数据库名，留空则是备份所有数据库）

※ MYSQL_DATABASE_NAME 是一个数组变量，可以指定多个，举例如下：

````
MYSQL_DATABASE_NAME[0]="phpmyadmin"
MYSQL_DATABASE_NAME[1]="test"`
````

BACKUP_DIR_FILES （需要备份的指定目录或文件列表，留空就是不备份目录或文件）
※ BACKUP_DIR_FILES 是一个数组变量，可以指定多个,举例如下：

````
BACKUP[0]="/data/www/default/test.php"
BACKUP[1]="/data/www/default/test/"
BACKUP[2]="/data/www/default/test2/"
````

SaveTime （指定多少天之后删除本地旧的备份文件，默认为 7 天）

DELETE_REMOTE_FILE （删除 Google Drive 或 FTP 上的备份文件，true 为删除，false 为不删除）

FTP （上传文件至 FTP 的 FLG，true 为上传，false 为不上传）

FTP_HOST （连接的 FTP 域名或 IP 地址）

FTP_USER （连接的 FTP 的用户名）

FTP_PASS （连接的 FTP 的用户的密码）

FTP_DIR （连接的 FTP 的远程目录，比如： public_html）

一些注意事项的说明：

1）脚本需要用 root 用户来执行；

2）脚本需要用到 openssl 来加密，请事先安装好；

3）脚本默认备份所有的数据库（全量备份）；

4）备份文件的解密命令如下：
````
openssl enc -aes256 -in [ENCRYPTED BACKUP] -out decrypted_backup.tgz -pass pass:[BACKUPPASS] -d -md sha1

tar -zxPf [DECRYPTION BACKUP FILE]
````

解释一下参数 -P：
tar 压缩文件默认都是相对路径的。加个 -P 是为了 tar 能以绝对路径压缩文件。因此，解压的时候也要带个 -P 参数。

### 3、配置 gdrive 命令

gdrive 是一个命令行工具，用于 Google Drive 的上传下载等操作。官网网站：
https://github.com/prasmussen/gdrive

当然，你可以用以下的命令来安装 gdrive。

x86_64（64位）：
````
wget -O /usr/bin/gdrive http://dl.lamp.sh/files/gdrive-linux-x64
chmod +x /usr/bin/gdrive
````
 i386（32位）
```` 
wget -O /usr/bin/gdrive http://dl.lamp.sh/files/gdrive-linux-386
chmod +x /usr/bin/gdrive
````  

然后，运行以下命令开始获取授权：
>gdrive about

根据提示用浏览器打开 gdrive 给出的 URL，点击接受（Accept），然后将浏览器上显示出来的字符串粘贴回命令行里，完成授权。

### 4、运行脚本
>./Backup2GDrive.sh

脚本默认会显示备份进度，并在最后统计出所需时间。
如果你想将脚本加入到 cron 自动运行的话，就不需要前台显示备份进度，只写日志就可以了。
这个时候你需要稍微改一下脚本中的 log 函数。
````
log() {
     echo "$(date "+%Y-%m-%d %H:%M:%S")" "$1"
     echo -e "$(date "+%Y-%m-%d %H:%M:%S")" "$1" >> ${LOGFILE}
 }
 ````
改为
````
log() {
     echo -e "$(date "+%Y-%m-%d %H:%M:%S")" "$1" >> ${LOGFILE}
 }
  ````
 
关于如何使用 cron 自动备份，这里就不再赘述了 以 CentOS 6 来举例说明。

修改文件 /etc/crontab，内容如下：


````
 SHELL=/bin/bash
 PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
 MAILTO=root
 HOME=/root
 
 # For details see man 4 crontabs
 
 # Example of job definition:
 # .---------------- minute (0 - 59)
 # |  .------------- hour (0 - 23)
 # |  |  .---------- day of month (1 - 31)
 # |  |  |  .------- month (1 - 12) OR jan,feb,mar,apr ...
 # |  |  |  |  .---- day of week (0 - 6) (Sunday=0 or 7) OR sun,mon,tue,wed,thu,fri,sat
 # |  |  |  |  |
 # *  *  *  *  * user-name command to be executed
 30  1  *  *  * root bash /root/backup.sh
 ````
 
 以上表示，每天凌晨 1 点 30 分，root 用户执行一次 backup.sh 脚本。
 注意：
 一定要修改其中的 PATH 和 HOME 变量的值。
 尤其是 HOME 变量，gdrive 命令能否正确执行，是要依赖于其配置文件的。默认用 root 配置的话，其配置文件夹应该是 /root/.gdrive/ ，所以要更改 HOME 的值。
