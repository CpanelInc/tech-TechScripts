#!/bin/sh

PHPINI='/usr/local/lib/php.ini'
HTTPDCONF='/usr/local/apache/conf/httpd.conf'

clear

echo -------------------------
echo 'Apache version'
echo -------------------------
/usr/local/apache/bin/httpd -v
echo ; echo
echo -------------------------
echo 'PHP version'
echo -------------------------
php -v
echo ; echo
echo -------------------------
echo 'PHP configuration'
echo -------------------------
/usr/local/cpanel/bin/rebuild_phpconf --current
echo ; echo
echo -------------------------
echo 'Apache modules'
echo -------------------------
/usr/local/apache/bin/httpd -l
echo ; echo
echo -------------------------
echo 'PHP modules'
echo -------------------------
php -m
echo ; echo


echo -------------------------
echo Backing up $PHPINI
echo -------------------------
if [ -e $PHPINI ] ; then
cp -p $PHPINI $PHPINI.backup.cpanel.`date +%s`
ls -l $PHPINI $PHPINI.backup.cpanel.*
fi

echo ; echo

echo -------------------------
echo Backing up $HTTPDCONF
echo -------------------------
if [ -e $HTTPDCONF ] ; then
cp -p $HTTPDCONF $HTTPDCONF.backup.cpanel.`date +%s`
ls -l $HTTPDCONF $HTTPDCONF.backup.cpanel.*
fi
