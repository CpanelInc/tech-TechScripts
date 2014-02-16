#!/usr/local/cpanel/3rdparty/perl/514/bin/perl

use strict;
use warnings;
use Time::Piece;
use Time::Seconds;
use File::ReadBackwards;

#Todo:
# account for broken lines better
# add a line from messeges, showing if server was restarted?
# headers
# print help?


# Variables
my $verbose = 1;
my $file = '/var/log/chkservd.log';
my $checks_per_day;
chomp(my $every_n_sec = `grep chkservd_check_interval /var/cpanel/cpanel.config | cut -d= -f2`);
my $every_n_min;
my @lines;
my $line_has_date = 2;
my $lastdate = '';
my $curdate;
my $tz;
my $tz_num;
my $curdate_printable;
my $duration;
my $duration_min;
my $duration_reported;
my $regex_error_bucket;
my $regex_known_full_lines;

# Set search time for 'system too slow' check
# IDK why this didn't work:
#if ( !$every_n_sec =~ /\D/ ) \{
#if ( !looks_like_number $every_n_sec || $every_n_sec < 1 ) \{
if ( $every_n_sec < 1 ) {
    &debug("every_n_sec is not an acceptable digit, using default 300 = 10 min");
    $every_n_sec = 300;
    $checks_per_day = ( 24*(60/($every_n_sec/60)) );
} 
else { 
    &debug("every_n_sec is a digit, using it");
    $checks_per_day = ( 24*(60/($every_n_sec/60)) );
    &debug("checks_per_day is: $checks_per_day");
}
# Add a 5 minute cushion to lower number of reports
$every_n_min = (($every_n_sec/60)+5);

## Open log file
# Get number of days to check
my $days = shift or die "Please enter number of previous days (this is juat an estimate) as an argument.\n";
# Get number of lines.  This is a guessed average (#lines per check seem to be ~5-8, so lets use 6.5)
my $lines_to_check = ($days*$checks_per_day*6.5);
&debug("lines_to_check is: $lines_to_check");

# Tail the file (opeing the whole thing is ridonculous time-wise)

@lines = &tail_file();

# While loop reads the file
while (@lines) {
    &debug("While loop started");
    my $line = shift(@lines);
    # Set the date
    if ($line =~ /\[(\d{4}(-\d{2}){2} \d{2}(:\d{2}){2} [+-]\d{4})\].*/) {
        $line_has_date = 1;
        &debug("line_has_date is now on: $line_has_date");
        $duration_reported = 0;
        &debug("Date string found, one is $1");

        # very manually adjusting timezone
        $curdate = Time::Piece->strptime($1, "%Y-%m-%d %H:%M:%S %z");
        &debug("curdate is now $curdate");
        &debug("lastdate is $lastdate");
        $tz = $curdate->strftime("%z");
        &debug("tz is $tz");
        $tz_num = ($tz + 0)/100;
        &debug("tz_num is $tz_num");
        $curdate += $tz_num*ONE_HOUR;
        &debug("after tz adjustment, curdate is now $curdate");
        $curdate_printable=$curdate->strftime("%Y-%m-%d %H:%M:%S $tz");
        &debug("curdate_printable is $curdate_printable");

        # Calculate time difference between this & last check
        # If this is the first time run, establish the starting values
        # note to self: the cPanel way (although I'd lose my debug): $lastdate ||= $curdate;
        if (!$lastdate) {
            $lastdate = $curdate;
            &debug ("after setting first occurence, lastdate is ", $lastdate, "\n");
        } 
        else {
            $duration = $curdate - $lastdate;
            &debug("duration is $duration");
            &debug ("duration is ", $duration->minutes, " minutes");
            &debug ("duration is ", $duration->hours, " hours");
            $duration_min=$duration->minutes;
            &debug ("duration_min is ", $duration_min);
        }
    }
    &debug("line_has_date, after if loop, is $line_has_date");

    # Regex for errors
    $regex_error_bucket = 'Restarting|nable|\*\*|imeout|ailure|terrupt|100%|9[89]%';
    $regex_known_full_lines = 'second';

    # If these are seen, something needs to be added to the error_bucket
    if ( ($line !~ /$regex_error_bucket/) && ($line =~ /:-]/) ){
        print "[$curdate_printable] ....\n";
    }
    # Main search
    if ($line =~ /$regex_error_bucket/){
        &debug ("line is ", $line);
        my @array_fields = split /(\.){2,}/,$line;
        &debug ("num fields is ", scalar(@array_fields));
        if (scalar(@array_fields) > 0){
            foreach (@array_fields) {
                # This is main search. Every thing else is exceptions. If happy face can't find it, it's weird.
                &debug("line_has_date, in foreach, is $line_has_date");
                if ( /:-]/ ) {
                    chomp;
                    print "[$curdate_printable] ", substr($_,0,100), "...\n";
                &debug("line_has_date, in if_foreach, is $line_has_date");
                }
                # More verbose output for broken lines
                elsif ( ($_ =~ /$regex_error_bucket/) && ($line_has_date == 1) ){
                    chomp;
                    print "[$curdate_printable] ", substr($_,0,100), "...\n";
                }
                elsif ( (/$regex_error_bucket/) && ($verbose == 1) ){
                &debug("line_has_date, in if_error_bucket & verbose, is $line_has_date");
                    chomp;
                    # Without doing a more complicated subroutine/hash, this the best that can be done.  
                    # The empty space means that the error message might go with the following line displayed,
                    # or the previous one. 
                    # The error variation shows that chksrvd should really be output in JSON format.
                    print "[                         ] ", substr($_,0,100), "...\n";
                }
            }
        }
    }
    elsif ($line =~ /$regex_known_full_lines/) {
        if ($line_has_date == 1){
            print $line;
        }
        else{
            print "[$curdate_printable] $line";
        }
    }

    &debug ("duration_min is ", $duration_min);
    &debug ("duration_reported is ", $duration_reported);
    if( (defined $duration_min) && ($duration_reported == 0) ){
        if($duration_min > $every_n_min) {
            printf "[$curdate_printable] %.0f minutes since last check\n", $duration_min;
            $duration_reported = 1;
            &debug ("duration_reported is ", $duration_reported);
        }
    }

    # Set lastdate for next round
    if ($line_has_date == 1) {
        $lastdate = $curdate;
    }
    # Reset so we can check again
    $line_has_date = 2;
    &debug("line_has_date is now off: $line_has_date");

&debug("While loop finished\n");
}

sub debug {
    my $debug_toggle = "no";
    # not sure why, but these checks silences warnings
    #if( ($debug_toggle eq "yes") && (defined $debug_toggle) && $_[1] ) {
    if( ($debug_toggle eq "yes") && (defined $debug_toggle) ) {
        print "(debug) @_\n"; 
    } 
}

sub tail_file {
    my $lim = $lines_to_check;
    my $bw = File::ReadBackwards->new( $file ) or die "can't read $file: $!\n" ;

    my $line;
    my @lines;
    while( defined( my $line = $bw->readline ) ) {
        push @lines, $line;
        last if --$lim <= 0;
    }
    reverse @lines;
}

