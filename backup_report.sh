#!/bin/bash
# Quick backup report script written by: Marco Ferrufino
#
# Description: https://staffwiki.cpanel.net/bin/view/LinuxSupport/CPanelBackups
#
# How to run this script:
# curl -s --insecure https://raw.github.com/cPanelTechs/TechScripts/master/backup_report.sh | sh

# this shows backups enabled or disabled but i need to return the value to the check functions

backlogdir=/usr/local/cpanel/logs/cpbackup;


# check if new backups are enabled
function check_new_backups() {
 echo -e "\n\n\033[36m[ cPTech Backup Report v1.0 ]\033[0m";
 new_enabled=$(grep BACKUPENABLE /var/cpanel/backups/config 2>/dev/null | awk -F"'" '{print $2}')
 new_cron=$(crontab -l | grep bin\/backup | awk '{print $1,$2,$3,$4,$5}')
 if [ "$new_enabled" = "yes" ]; then new_status='\033[1;32m'Enabled'\033[0m'
 else new_status='\033[1;31m'Disabled'\033[0m'
 fi
 echo -e "New Backups = $new_status\t\t(cron time: $new_cron)"
}

# check if legacy or new backups are enabled.  if each one is, then show how many users are skipped
function check_legacy_backups() {
 legacy_enabled=$(grep BACKUPENABLE /etc/cpbackup.conf | awk '{print $2'})
 legacy_cron=$(crontab -l | grep cpbackup | awk '{print $1,$2,$3,$4,$5}')
 if [ $legacy_enabled = "yes" ]; then legacy_status='\033[1;32m'Enabled'\033[0m'
 else legacy_status='\033[1;31m'Disabled'\033[0m'
 fi
 echo -e "Legacy Backups = $legacy_status\t(cron time: $legacy_cron)"
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
 echo -e "\n\033[36m[ A count of user exceptions ]\033[0m";
}

function list_legacy_exceptions() {
legacy_users=$(grep "LEGACY_BACKUP=1" /var/cpanel/users/* | wc -l);
if [ $legacy_enabled == "yes" ]; then
 oldxs=$(egrep "LEGACY_BACKUP=0" /var/cpanel/users/* | wc -l);
 skip_file_ct=$(wc -l /etc/cpbackup-userskip.conf 2>/dev/null)
 if [ $oldxs -gt 0 -o "$skip_file_ct" ]; then
  echo -e "Legacy Backups Exceptions";
 fi
 if [ $oldxs -gt 0 ]; then echo -e "Number of real Legacy backup exceptions: "$oldxs"\n"; fi;
 if [ -n "$skip_file_ct" ]; then echo -e "Extra Information: This skip file should no longer be used\n"$skip_file_ct"\n"; fi
elif [ $legacy_users -gt 0 -a $legacy_status == "Disabled" ]; then
 echo -e "\nExtra Information: Legacy Backups aren't enabled, but there are $legacy_users users ready to use them."
echo
fi
}

function list_new_exceptions() {
if [ "$new_enabled" == "yes" ]; then
 newxs=$(egrep "BACKUP=0" /var/cpanel/users/* | grep ":BACK" | wc -l);
 echo -e "New Backups exceptions: $newxs";
 newen=$(egrep "BACKUP=1" /var/cpanel/users/* | grep ":BACK" | wc -l);
 echo -e "New Backup users enabled: "$newen
fi
}

function count_local_new_backups() {
echo -e "\n\033[36m[ A count of the backup files on local disk currently ]\033[0m";
new_backup_dir=$(awk '/BACKUPDIR/ {print $2}' /var/cpanel/backups/config 2>/dev/null)
if [ -n "$new_backup_dir" ]; then
 number_new_backups=$(\ls $new_backup_dir/*/accounts/ 2>/dev/null | wc -l)
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

# Run all functions
check_new_backups
check_legacy_backups
print_start_end_times 
exceptions_heading
list_legacy_exceptions
list_new_exceptions
count_local_new_backups
count_local_legacy_backups
echo; echo
