#!/bin/bash
# Quick backup report script written by: Marco Ferrufino
#
# Description: https://staffwiki.cpanel.net/bin/view/LinuxSupport/CPanelBackups
#
# How to run this script:
# curl -s --insecure https://raw.githubusercontent.com/cPanelTechs/TechScripts/master/backup_report.sh | sh

# this shows backups enabled or disabled but i need to return the value to the check functions

backlogdir=/usr/local/cpanel/logs/cpbackup;


# check if new backups are enabled
function check_new_backups() {
 echo -e "\n\n\033[36m[ cPTech Backup Report v2.1 ]\033[0m";
 new_enabled=$(grep BACKUPENABLE /var/cpanel/backups/config 2>/dev/null | awk -F"'" '{print $2}')
 new_cron=$(crontab -l | grep bin\/backup | awk '{print $1,$2,$3,$4,$5}')
 if [ "$new_enabled" = "yes" ]; then new_status='\033[1;32m'Enabled'\033[0m'
 else new_status='\033[1;31m'Disabled'\033[0m'
 fi
 echo -e "New Backups = $new_status\t\t(cron time: $new_cron)\t\t/var/cpanel/backups/config"
}

# check if legacy or new backups are enabled.  if each one is, then show how many users are skipped
function check_legacy_backups() {
 legacy_enabled=$(grep BACKUPENABLE /etc/cpbackup.conf | awk '{print $2'})
 legacy_cron=$(crontab -l | grep cpbackup | awk '{print $1,$2,$3,$4,$5}')
 if [ $legacy_enabled = "yes" ]; then legacy_status='\033[1;32m'Enabled'\033[0m'
 else legacy_status='\033[1;31m'Disabled'\033[0m'
 fi
 echo -e "Legacy Backups = $legacy_status\t(cron time: $legacy_cron)\t\t/etc/cpbackup.conf"
}

# For the ftp backup server checks.  I couldn't do this with normal arrays, so using this eval hack
hput () {
  eval hash"$1"='$2'
}
hget () {
  eval echo '${hash'"$1"'#hash}'
}

# Check if any active FTP backups
function check_new_ftp_backups() {
 any_ftp_backups=$(\grep 'disabled: 0' /var/cpanel/backups/*backup_destination 2>/dev/null)
 if [ -n "$any_ftp_backups" ]; then ftp_backup_status='Enabled'
 else ftp_backup_status='Disabled'
 fi
 echo -e "\nNew FTP Backups = $ftp_backup_status\t(as of v2.0, this script only checks for new ftp backups, not legacy)"

 # Normal arrays
 declare -a ftp_server_files=($(\ls /var/cpanel/backups/*backup_destination));
 declare -a ftp_server_names=($(for i in ${ftp_server_files[@]}; do echo $i | cut -d/ -f5 | rev | cut -d_ -f4,5,6,7,8 | rev; done));
 # Array hack is storing 'Disabled' status in $srvr_SERVER_NAME
 for i in ${ftp_server_files[@]}; do hput srvr_$(echo $i | cut -d/ -f5 | rev | cut -d_ -f4,5,6,7,8 | rev) $(\grep disabled $i | awk '{print $2}'); done
 
 # Print
 for i in ${ftp_server_names[@]}; do 
  echo -n "Backup FTP Server: "$i" = "
  srvr_status=$(hget srvr_$i)
  if [ $srvr_status = 0 ]; then
   echo -e '\033[1;32m'Enabled'\033[0m';
   else echo -e '\033[1;31m'Disabled'\033[0m';
  fi
 done
}

# look at start, end times.  print number of users where backup was attempted
function print_start_end_times () {
echo -e "\n\033[36m[ Current Backup Logs in "$backlogdir" ]\033[0m";
if [ -e $backlogdir ]; then
 cd $backlogdir;
 for i in `\ls`; do
  echo -n $i": "; grep "Started" $i; echo -n "Ended ";
  \ls -lrth | grep $i | awk '{print $6" "$7" "$8}';
  echo -ne " Number of users backed up:\t";  grep "user :" $i | wc -l;
 done;
 echo -e "\n\033[36m[ Expected Number of Users ]\033[0m";
 wc -l /etc/trueuserdomains;
fi;
}

function exceptions_heading() {
 echo -e "\n\033[36m[ A count of users enabled/disabled ]\033[0m";
}

function list_legacy_exceptions() {
legacy_users=$(grep "LEGACY_BACKUP=1" /var/cpanel/users/* | wc -l);
if [ $legacy_enabled == "yes" ]; then
 oldxs=$(egrep "LEGACY_BACKUP=0" /var/cpanel/users/* | wc -l);
 skip_file_ct=$(wc -l /etc/cpbackup-userskip.conf 2>/dev/null)
 if [ $oldxs -gt 0 -o "$skip_file_ct" ]; then
  echo -e "Legacy Backups:";
 fi
 if [ $oldxs -gt 0 ]; then echo -e "Number of real Legacy backup users disabled: \033[1;31m$oldxs\033[0m\n"; fi;
 if [ -n "$skip_file_ct" ]; then echo -e "Extra Information: This skip file should no longer be used\n"$skip_file_ct"\n"; fi
elif [ $legacy_users -gt 0 -a $legacy_status == "Disabled" ]; then
 echo -e "\nExtra Information: Legacy Backups are disabled as a whole, but there are $legacy_users users ready to use them."
echo
fi
}

function list_new_exceptions() {
# TODO: math
newsuspended=$(egrep "=1" /var/cpanel/users/* | grep "SUSPENDED" | wc -l);
if [ "$newsuspended" != 0 ]; then
    echo -e "Users suspended: \033[1;31m$newsuspended\033[0m";
fi

if [ "$new_enabled" == "yes" ]; then
 newxs=$(egrep "BACKUP=0" /var/cpanel/users/* | grep ":BACK" | wc -l);
 echo -e "New Backup users disabled: \033[1;31m$newxs\033[0m";
 newen=$(egrep "BACKUP=1" /var/cpanel/users/* | grep ":BACK" | wc -l);
 echo -e "New Backup users enabled: \033[1;32m$newen\033[0m"
fi
}

function count_local_new_backups() {
echo -e "\n\033[36m[ A count of the backup files on local disk currently ]\033[0m";
new_backup_dir=$(awk '/BACKUPDIR/ {print $2}' /var/cpanel/backups/config 2>/dev/null)
if [ -n "$new_backup_dir" ]; then
 number_new_backups=$(\ls /backup/*/accounts 2>/dev/null | egrep -v ":$" | awk NF | wc -l)
 echo -e "New backups in $new_backup_dir/*/accounts: "$number_new_backups
else echo "0 - No new backup directory configured"
fi
}

function count_local_legacy_backups() {
legacy_backup_dir=$(awk '/BACKUPDIR/ {print $2}' /etc/cpbackup.conf)
echo -e "\nLegacy backups in $legacy_backup_dir/cpbackup: "
for freq in daily weekly monthly; do 
 echo -n $freq": "; 
 \ls $legacy_backup_dir/cpbackup/$freq | egrep -v "^dirs$|^files$|cpbackup|status" | sed 's/\.tar.*//g' | sort | uniq | wc -l;
done
}

function show_recent_errors() {
    # Errors from backup log directory
    echo -e "\n\033[36m[ Count of Recent Errors ]\033[0m";
    for i in `\ls $backlogdir`; do 
        echo -n $backlogdir"/"$i" Ended "; 
        \ls -lrth $backlogdir | grep $i | awk '{print $6" "$7" "$8}'; 
        \egrep -i "failed|error|load to go down|Unable" $backlogdir/$i | cut -c -180 | sort | uniq -c ;
    done | tail;
    # Errors from cPanel error log
    echo -e "\n/usr/local/cpanel/logs/error_log:"
    egrep "(warn|die|panic) \[backup" /usr/local/cpanel/logs/error_log | awk '{printf $1"] "; for (i=4;i<=20;i=i+1) {printf $i" "}; print ""}' | uniq -c | tail -3

    #any_ftp_backups=$(\grep 'disabled: 0' /var/cpanel/backups/*backup_destination 2>/dev/null)
    if [ -n "$any_ftp_backups" ]; then
        # Errors from FTP backups
        echo -e "\n/usr/local/cpanel/logs/cpbackup_transporter.log:"
        egrep '] warn|] err' /usr/local/cpanel/logs/cpbackup_transporter.log | tail -5
    fi
}

# Run all functions
check_new_backups
check_legacy_backups
check_new_ftp_backups
print_start_end_times 
exceptions_heading
list_legacy_exceptions
list_new_exceptions
count_local_new_backups
count_local_legacy_backups
show_recent_errors
echo; echo
