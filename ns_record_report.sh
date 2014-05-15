#!/bin/sh

# Find all unique NS records in all zones and loop through their names
for NS in `grep -h '\bNS\b' /var/named/*.db |awk '{print $NF}' |sed 's/\.$//' |sort -u`; do

  # Print nameserver name
  echo -n "$NS   "

  # Do an A lookup on nameserver name
  dig A $NS. +short |xargs echo -n; echo -n "   "

  # Count number of zones in which nameserver name appears in NS Record
  grep "\bNS.*$NS" /var/named/*.db |wc -l
done
