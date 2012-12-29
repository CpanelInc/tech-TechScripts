#!/bin/sh
# Get nameservers for a domain name from the TLD servers.
# Also get the GLUE records if they exist.
#

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
				echo "(IP's resolved, not from TLD record)"
			done;`
	fi;
}

print_results() {
    printf "%b\n" "${greenbold}\n# dig NS ${tld}. +short | head -n1${clroff}"
    printf "%b\n" "$tld_server"
    printf "%b\n" "${greenbold}\n# ${dig_oneliner}${clroff}"
    printf "%b\n" "${dig_result}\n"
    printf "%b\n" "${greenbold}Nameserver Names:\n${clroff}${auth_ns}\n"
    printf "%b\n" "${greenbold}Nameserver IPs:\n${clroff}${bare_result}\n"
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
