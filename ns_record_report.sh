#!/bin/sh

# Print column headers
tput bold
printf "%-24s %-16s %6s\n" "Nameserver" "ResolvedIP" "Zones"
tput sgr0

# Find all unique NS records in all zones and loop through their names
for nameserver in `grep -h '\bNS\b' /var/named/*.db |awk '{print $NF}' |sed 's/\.$//' |sort -u`; do

  # Do an A lookup on nameserver name
  resolved_ip=`dig A $nameserver. +short |xargs echo -n`
  if [[ -z $resolved_ip ]]; then
    resolved_ip='no IP found'
  fi

  # Count appearances in zones
  zones=`grep "\bNS.*$nameserver" /var/named/*.db |wc -l`

  # Print row
  printf "%-24s %-16s %6s\n" "$nameserver" "$resolved_ip" "$zones"
done
