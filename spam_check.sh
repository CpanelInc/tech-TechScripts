#!/bin/bash
# This script creates a few summaries from the mail queue to help you decide if
# the server is sending spam or not.
# 
# Description:
# http://staffwiki.cpanel.net/LinuxSupport/EximSpamOneLiners
# for a summary of the code, the main code block is at the bottom
# 
# To run: 
# curl -s --insecure https://raw.github.com/cPanelTechs/TechScripts/master/spam_check.sh > spam_check.sh; sh spam_check.sh
# 
#todo: check that there's some mail in the queue vs printing empty

function debug() {
    debug="off"
    if [ "$debug" = "on" ]; then
        echo $1
    fi
}
# example:
# debug "variable_name is ${variable_name}"

use_current=0
backup_current=0
remove_current=0
temp_dir=/root

function get_temp_file_dir () {
    clear;
    read -p "
    Choose a directory to store the temporary file cptemp_eximbp.  This will store the output of exim -bp (default /root): " input_dir
    debug "input_dir is ${input_dir}"
    input_dir=${input_dir:-/root}
    debug "input_dir is ${input_dir}"
    temp_dir=$(echo $input_dir | sed 's/\/$//')
    debug "temp_dir is ${temp_dir}"
    if [ -e $temp_dir ]; then
        if [ -e $temp_dir/cptemp_eximbp ]; then
            get_output_decision 
        fi
    else
        echo "There was a problem, or that directory does not exist. Please try again."
        get_temp_file_dir
    fi

    echo -e "\nThank you.\nThis file can later be used again to run commands (like 'cat $temp_dir/cptemp_eximbp | exiqsumm').\nThis script will not delete this temp file upon completion."
    debug "temp_dir is ${temp_dir}"
}

# If the temp output file already exists, user must choose (this will go back to get_temp_file_dir when complete)
function get_output_decision () {
    echo
    read -p "Output file ($temp_dir/cptemp_eximbp) already exists. Please enter a number 1-3
    1) Run diagnosis on the existing output file
    2) Move to backup ($temp_dir/cptemp_eximbp.1), and create a new output file
    3) Delete the existing output file, and create a new one (default): " file_choice
    file_choice=${file_choice:-3}
    case $file_choice in
        1) use_current=1;
        ;;
        2) backup_current=1;
        ;;
        3) remove_current=1;
           \rm -v $temp_dir/cptemp_eximbp
        ;;
        *)
        echo -e "\nPlease enter a valid choice: 1 to 3."
        get_output_decision
        ;;
    esac  
}

function run_eximbp () {
    debug "starting run_eximbp, backup_current is ${backup_current}\n use_current is ${use_current}"
    if [ $use_current -eq 0 ]; then
        echo -e "\nNow, beginning to run the command 'exim -bp'.  If this takes an excruciatingly long time, you can cancel (control-c) this script.\n You can then run this script again using the same target directory and existing 'exim -bp' output file (using option 1 of this script).\n Often, all that's needed is 30s worth of gathering the oldest messages in the queue."
        if [ $backup_current -eq 1 ]; then
            echo; mv -v $temp_dir/cptemp_eximbp $temp_dir/cptemp_eximbp.1
            exim -bp > $temp_dir/cptemp_eximbp
            debug "exim -bp >> $temp_dir/cptemp_eximbp"
        else
            exim -bp > $temp_dir/cptemp_eximbp
            debug "exim -bp > $temp_dir/cptemp_eximbp"
        fi
    fi
}

#todo: put this in a printf statement, report if domain is local/remote at the end:
# Are they local?
# for i in $doms; do echo -n $i": "; grep $i /etc/localdomains; done
function exiqsumm_to_get_top_domains () {
    echo -e "\nDomains stopping up the queue:"; 
    cat $temp_dir/cptemp_eximbp | exiqsumm | sort -n | tail -5;

    # Get domains from Exim queue
    doms=$(cat $temp_dir/cptemp_eximbp | exiqsumm | sort -n | egrep -v "\-\-\-|TOTAL|Domain" | tail -5 | awk '{print $5}')
}

function check_if_local () {
    echo -e "\nDomains from above that are local:"
    for onedomain in $doms; do
        islocal=$(grep $onedomain /etc/localdomains)
        ishostname=$(hostname | grep $onedomain)
        if [ "$islocal" -o "$ishostname" ]; then
            echo $onedomain;
        fi
    done
}

# There's an awk script in here that decodes base64 subjects
function get_subjects_of_top_domains () {
 for onedomain_of_five in $doms; do
    dom=$onedomain_of_five;
    echo -e "\n\n Count / Subjects for domain = $onedomain_of_five:";
    for email_id in `cat $temp_dir/cptemp_eximbp | grep -B1 $dom | awk '{print $3}'`; do
        exim -Mvh $email_id | grep Subject; 
    done | sort | uniq -c | sort -n | tail; 
 done | awk '{
     split($4,encdata,"?"); 
     command = (" base64 -d -i;echo"); 
     if ($0~/(UTF|utf)-8\?(B|b)/) {
         printf "      "$1" "$2"  "$3" "; 
         print encdata[4] | command; 
         close(command);
         }
     else {print}
     }
     END {printf "\n"}'
}

# Domains sending:
function find_addresses_sending_out () {
    declare -a sendingaddys=($(egrep "<" $temp_dir/cptemp_eximbp | awk '{print $4}' | sort | uniq -c | sort -n | sed 's/<>/bounce_email/g' | tail -4));
    echo -e "\nAddresses sending out: " ${sendingaddys[@]} "\n"| sed 's/ \([0-9]*\) /\n\1 /g'
    bigsender=$(echo ${sendingaddys[@]} | awk '{print $NF}'); 
    echo -e "So the big sender is:\n"$bigsender
}

function find_addresses_sending_to_top_domains () {
    echo; 
    for onedomain_of_five in $doms; do
        echo "Mails attempting to be sent to domain [$onedomain_of_five], from:"; 
        cat $temp_dir/cptemp_eximbp | grep -B1 $onedomain_of_five | egrep -v "\-\-|$onedomain_of_five" | awk '{print $4}' | sort | uniq -c | sort -n | tail -5; 
        echo; 
    done
}

# Run all functions
get_temp_file_dir
run_eximbp
exiqsumm_to_get_top_domains 
check_if_local 
get_subjects_of_top_domains 
find_addresses_sending_out
find_addresses_sending_to_top_domains
