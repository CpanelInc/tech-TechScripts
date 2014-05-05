#!/bin/sh
# Get nameservers for a domain name from the TLD servers.
# Also get the GLUE records if they exist.
# If glue records do not exist, find them manually.
#
# This script is meant to be run from the local Desktop as a quick reference.
# 
# Description:
# https://staffwiki.cpanel.net/LinuxSupport/GuideToDns#Bash_script_to_show_authoritative_nameservers_and_GLUE_records
# 
# How to download and use:
# curl -O https://raw.githubusercontent.com/cPanelTechs/TechScripts/master/authdns.sh > authdns.sh; chmod u+x authdns.sh
# ./authdns.sh cpanel.net
#
# Todo: check for two-part tlds, like .xx.co or .com.br (3753229)
# need to check if 2nd to last is legit tld, then run it.
# http://stackoverflow.com/questions/14460680/how-to-get-a-list-of-tlds-using-bash-for-building-a-regex
# http://data.iana.org/TLD/tlds-alpha-by-domain.txt
# http://mxr.mozilla.org/mozilla-central/source/netwerk/dns/effective_tld_names.dat?raw=1
#
# Todo#2: check for responses from all the auth ns's, instead of just the top one

function debug() {
     debug="off"
      if [ "$debug" = "on" ]; then
            echo $1
             fi
}
# example:
# debug "variable_name is ${variable_name}"

# Check for dig commannd
verify_tools() {
    command -v dig >/dev/null 2>&1 || { echo >&2 "Oops! The dig command is necessary for this script, but was not found on this system :(  Aborting."; exit 1; }
}

# Check input
check_input() {
    if [ -z ${dom} ]; then
        echo 'Please specify a domain.'; exit 1;
    fi
}

# Get input, initial variables
dom=${1}
#tld=${dom#*.}
tld=$(echo $dom | awk -F. '{print $NF}')
debug "tld is ${tld}"
options="+noall +authority +additional +comments"
multi_check_done=0

# Functions
try_sec_level_domain() {
    num_parts=$(echo $dom | awk -F"." '{print NF}')
    if [ $num_parts > 2 ]; then
        debug "Starting multi part domain check"
        regex=$(curl -s http://data.iana.org/TLD/tlds-alpha-by-domain.txt | sed '1d; s/^ *//; s/ *$//; /^$/d' | awk '{print length" "$0}' | sort -rn | cut -d' ' -f2- | tr '[:upper:]' '[:lower:]' | awk '{print "^"$0"$"}' | tr '\n' '|' | sed 's/\|$//')
        let sec_lev_tld_pos=$num_parts-1
        debug "sec_lev_tld_pos is $sec_lev_tld_pos, num_parts is $num_parts"
        sec_lev_tld=$(echo $dom | cut -d. -f$sec_lev_tld_pos)
        debug "sec_lev_tld is $sec_lev_tld"
        is_legit=$(echo $sec_lev_tld | awk -v reg=$regex '$0~reg');
        if [ "$is_legit" ]; then tld=$(echo $dom | cut -d. -f$sec_lev_tld_pos,$num_parts); fi 
        multi_check_done=1
        debug "multicheck is done.  the new tld is $tld"
    fi
}

create_dig_oneliner() {
	tld_server=$(dig NS ${tld}. +short | head -n1)
	dig_oneliner="dig @${tld_server} ${dom}. ${options}"
}

get_result() {
	dig_result=`${dig_oneliner}`
}

set_colors() {
    # Colors and formatting
    greenbold='\033[1;32m'
    clroff="\033[0m";
}

get_nameservers() {
	# nameserver names and possibly IP's from TLD servers
	auth_ns=$(${dig_oneliner} | awk '/AUTHORITY SECTION/,/^[ ]*$/' | awk '{print $NF}' | sed -e 1d -e 's/.$//')
    debug "auth_ns is ${auth_ns} multi_check_done is $multi_check_done"
    ns_check_ip=$(echo $auth_ns | egrep '([[:digit:]]{1,3}\.){3}[[:digit:]]{1,3}')
    ns_check_name=$(echo $auth_ns | egrep [a-zA-Z])
    debug "ns_check_ip is ${ns_check_ip}"
    debug "ns_check_name is ${ns_check_name}"
    if [ ! "$ns_check_name" -a ! "$ns_check_ip" -a $multi_check_done -lt 1 ]; then
        try_sec_level_domain
        create_dig_oneliner
        get_result
        get_nameservers
    fi
	additional_ips=$(${dig_oneliner} | awk '/ADDITIONAL SECTION/,0' | awk '{print $NF}' | sed 1d)
}

get_nameserver_ips() {
	# get bare IP's of nameservers
	if [ "$additional_ips" ];
		then bare_result=$additional_ips;
		else bare_result=`
			for auth_ips in "${auth_ns[@]}"; do
				dig +short $auth_ips
				echo "(Warning: these IP's had to be resolved manually, so glue records are bad)"
			done;`
	fi;
}

print_results() {
    printf "%b\n" "${greenbold}\n# dig NS ${tld}. +short | head -n1${clroff}"
    printf "%b\n" "$tld_server"
    printf "%b\n" "${greenbold}\n# ${dig_oneliner}${clroff}"
    printf "%b\n" "${dig_result}\n"
    printf "%b\n" "${greenbold}authoritative nameserver names:\n${clroff}${auth_ns}\n"
    printf "%b\n" "${greenbold}authoritative nameserver IPs:\n${clroff}${bare_result}\n"
}



# Run code
verify_tools
check_input
create_dig_oneliner
get_result
set_colors
get_nameservers
# get_nameservers also includes a check that tries 2nd level domains
get_nameserver_ips
print_results
