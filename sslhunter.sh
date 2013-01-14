#!/bin/bash

if [ "$#" == "0" ]
then
   echo "This program hunts for the matching cert/key in an SSL pair."
   echo "Usage: sslhunter.sh [file.key|file.cert] (search_path1 search_path2 ... search_pathN)"
   exit 1
fi

if [ -f "$1" ]
then
file="$1"
shift
fi


getfiletype () {
if fgrep -q "BEGIN RSA PRIVATE KEY" "$1"
then
filetype=rsa
return 0
elif fgrep -q "BEGIN CERTIFICATE" "$1"
then
filetype=x509
return 0
fi
filetype=other
return 1
}

getmodulus(){
echo "Scanning $filetype   $2"
eval `openssl $1 -noout -modulus -in "$2"`
}

getfiletype "$file"

getmodulus "$filetype" "$file"

targetmodulus=$Modulus

IFS=$'\012'

while [ "$1" ]
do

if [ -d "$1" ]
then
searchdirs="$1
$searchdirs"
else
echo "$1 is not a valid directory... Skipping."
fi
shift

done

if [ ! "$searchdirs" ]
then
searchdirs="/etc/ssl
/var/cpanel/ssl
/home/*/ssl"
fi


echo "
Searching for matching modulus in the following directories:
$searchdirs
"

files=`find -L $searchdirs -type f -print`

for testfile in $files
do
getfiletype "$testfile"
if [ $filetype != "other" ]
then
getmodulus $filetype "$testfile"

if [ "$Modulus" = "$targetmodulus" ]
then
echo "   Matches!"
matches="$matches
$testfile type $filetype"
fi
fi
done

echo "

"

if [ "$matches" ]
then
echo "These files have the same modulus as $file: $matches
"
else
echo "No matching files found in your search path(s)."
fi
