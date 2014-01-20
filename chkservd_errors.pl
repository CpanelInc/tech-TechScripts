#!/usr/local/cpanel/3rdparty/perl/514/bin/perl

use strict;
use warnings;
use Time::Piece;
use Time::Seconds;
use File::ReadBackwards;

#Todo:
# headers
# print help?

sub debug {
    my $debug_toggle = "no";
    if(defined $debug_toggle){
        if ($debug_toggle eq "yes") {
            # silences a stupid warning
            #if($_[1]){ 
                print "(debug) @_\n"; 
            #} 
        } 
    }
}

# Variables
my @lines;
my $lastdate;
my $curdate;
my $duration;
my $duration_min;
my $line_has_date=0;
my $checks_per_day;
chomp(my $every_n_sec=`grep chkservd_check_interval /var/cpanel/cpanel.config | cut -d= -f2`);
my $file  = '/var/log/chkservd.log';

# Set search time for 'system too slow' check
# IDK why this didn't work:
#if ( !$every_n_sec =~ /\D/ ) \{
#if ( !looks_like_number $every_n_sec || $every_n_sec < 1 ) \{
if ( $every_n_sec < 1 ) {
    &debug("every_n_sec is not an acceptable digit, using default 10");
    $checks_per_day=10;
} else { 
    &debug("every_n_sec is a digit, using it");
    $checks_per_day = ( 24*(60/($every_n_sec/60)) );
    &debug("checks_per_day is: $checks_per_day");
}

## Open log file
# Get number of days to check
my $days = shift or die "Please enter number of previous days (this is juat an estimate) as an argument.\n";
# Get number of lines.  This is a guessed average (#lines per check seem to be ~5-8, so lets use 6.5)
my $lines_to_check = ($days*$checks_per_day*6.5);
&debug("lines_to_check is: $lines_to_check");

# Tail the file (opeing the whole thing is ridonculous time-wise)
sub reverse_lines {
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

@lines = &reverse_lines();

# While loop reads the file
#while ($line = <$file>) {
foreach my $line(@lines) {
    # Set the date
    if ($line =~ /\[(\d{4}(-\d{2}){2} \d{2}(:\d{2}){2} [+-]\d{4})\].*/) {
        $line_has_date = 1;
        &debug("one is $1");

        ##########
        # Time::Piece
        $curdate = Time::Piece->strptime($1, "%Y-%m-%d %H:%M:%S %z");
        &debug("curdate is now $curdate");

        # Calculate time difference between this & last check
        # If this is the first time run, establish the starting values
        # note to self: this would have worked too: $lastdate ||= $curdate;
        if (!$lastdate) {
            $lastdate = $curdate;
            &debug ("after setting first occurence, lastdate is ", $lastdate, "\n");
        } else {
            $duration = $curdate - $lastdate;
            &debug("duration is $duration");
            &debug ("duration is ", $duration->minutes, " minutes");
            &debug ("duration is ", $duration->hours, " hours");
            $duration_min=$duration->minutes;
            &debug ("duration_min is ", $duration_min);
        }
    }

    # These are usually trash lines
    if ($line !~ /Restarting|nable|\*\*|imeout|ailure|terrupt|100%|9[89]%|second/ && $line =~ /:\-\]/){
        print "[", $lastdate, "] ", " ....\n";
    }
    # Main search
    if ($line =~ /Restarting|nable|\*\*|imeout|ailure|terrupt|100%|9[89]%|second/){
        my @array_fields = split /(\.){2,}/,$line;
        if (scalar(@array_fields) > 1){
            foreach (@array_fields) {
                if (/:\-\]/) {
                    print "[", $lastdate, "] ", $_, "\n";
                }
            }
        } else {
                print "[", $lastdate, "] ", $line;
            }
        #&debug("\nWHILE LOOP DONE\n");
    }

    &debug ("duration_min is ", $duration_min);
    if(defined $duration_min){
        if($duration_min > $checks_per_day) {
            printf "[$lastdate] %.0f minutes since last check\n", $duration_min;
        }
    }

    # Set lastdate for next round
    if ($line_has_date) {
        $lastdate=$curdate;
    }

}
