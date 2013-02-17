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
# curl -O https://raw.github.com/cPanelTechs/TechScripts/master/authdns.sh > authdns.sh; chmod u+x authdns.sh
# ./authdns.sh cpanel.net
#
# Todo: check for two-part tlds, like .xx.co or .com.br (3753229)
#  maybe, use two for any domain with 3 parts?
# Todo#2: check for responses from all the auth ns's, instead of just the top one


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
tld=${dom#*.}
options="+noall +authority +additional +comments"

# Functions
create_dig_oneliner() {
	tld_server=`dig NS ${tld}. +short | head -n1`
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
	auth_ns=`${dig_oneliner} | awk '/AUTHORITY SECTION/,/^[ ]*$/' | awk '{print $NF}' | sed -e 1d -e 's/.$//'`
	additional_ips=`${dig_oneliner} | awk '/ADDITIONAL SECTION/,0' | awk '{print $NF}' | sed 1d`
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
get_nameserver_ips
print_results
