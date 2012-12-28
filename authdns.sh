#!/bin/bash
# Get nameservers for a domain name from the TLD servers.
# Also get the GLUE records if they exist.
#

# Check for dig commannd
command -v dig >/dev/null 2>&1 || { echo >&2 "How can I look up domain servers without dig?  Please install the dig command on this system. Aborting."; exit 1; }

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
    # Mac
    if [ "`uname`" == "Darwin" ];
       then
       greenbold='\033[0;32m'

       # Linux
       else
       greenbold='\E[32;1m'
    fi;
    clroff="\033[0m";
}

get_nameservers() {
	# nameserver names and possibly IP's from TLD servers
	auth_ns=`${dig_oneliner} | awk '/AUTHORITY SECTION/,/^[ ]*$/' | awk '{print $NF}' | sed 1d | sed 's/.$//'`
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
	echo -e $greenbold"\n# dig NS ${tld}. +short | head -n1"$clroff
	echo $tld_server
	echo -e $greenbold"\n# "$dig_oneliner$clroff
	echo -e "${dig_result}\n"
	echo -e $greenbold"Nameserver Names: \n"$clroff"${auth_ns}\n"
	echo -e $greenbold"Nameserver IP's: \n"$clroff"${bare_result}\n"
}


# Check input, run code
if [ -z ${1} ]; then
echo 'Please specify a domain.'
else
	create_dig_oneliner
	get_result
	set_colors
	get_nameservers
	get_nameserver_ips
	print_results
fi
