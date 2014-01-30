#!/usr/local/cpanel/3rdparty/bin/perl

use strict;
use warnings;

# #!/usr/local/cpanel/3rdparty/perl/514/bin/perl
# TIP: better to use the symlink to perl instead of a specific version since
# perl version will change when cPanel switches to a newer version
#

#
#TODO: convert this into a module that allows for parsing most any log file
#

#
# Conventions and general tips
#
# CONVENTION: constrain the width of code to 80 columns
#
# CONVENTION: put spaces before and after equal signs
#
# CONVENTION: the preferred way to format else statements is to place the word
#             on its own line like so:
#             if () {
#             }
#             else {
#             }
#
# TIP: use verbose comments that fully explain any complexity or ambiguity so
#      that someone unfamiliar with the code can understand what is going on
#
# TIP: for readability and to reduce ambiguity, err on the side of verbose
#      variable names. Ex: $current_date instead of $curdate
#
# TIP: subroutines should all appear in the same section of your code, most
#      commonly after the main-line code.
#
# TIP: Using the '&' for function calls (i.e. &debug) should be avoided as there
#      are a few instances where it can cause unexpected results. On the other
#      hand, such issues are rare, so you can use it to visually differentiate
#      user-defined subroutine calls from built-in functions.
#
# TIP: You can leave off parentheses if doing so does not introduce any
#      ambiguity, such as debug ''; instead of debug('');
#
# TIP: It is dangerous to rely on global variables. Better to pass an argument
#      and then use a local variable inside the subroutine
#
# TIP: Name your functions carefully to avoid confusion. For example, if the 
#      function, reverse_lines(), reads a file backwards in order to grab the
#      end of a file, its purpose is actually to tail the log--the reversal of
#      lines was simply one step in achieving that end. Therefore, a better name#      would be tail().
#
# TIP: Avoid running shell commands for portability and speed (and fun!)
#

#
# Tip: use a module that cpanel installs for internal perl. Not sure if the
#      module I used qualifies (Date::Parse). However, Time::Piece was
#      definitley not available on my cpanel server
#
#use Time::Piece;
#use Time::Seconds;
#
#
# TIP: Avoid using modules not already installed by cpanel for internal perl
#
#use File::ReadBackwards;
#
use Date::Parse; # Needed to convert local time to epoch time for each log entry
use Data::Dumper; # For easier debugging

#
# TIP: Normally, you should avoid global variables that are used inside
# subroutines, but toggling debugging on/off globally is probably ok.
# 
# Global variables
#
# Toggle debugging messages
my $DEBUG = 1;

#
# Usage:
#     chkservd_grep days [search_string]
#
my ($days, $search_pattern) = @ARGV;
#debug($days, $search_pattern);exit;

die "usage: chkservd_grep number_of_days [search_string]" unless $days;

#
# Main program
#

#
# TIP: This script does not use the 'chkservd_check_interval' value from
# /var/cpanel/cpanel.config. However, I'm including the the get_config_value()
# function to illustrate how you would want to go about extracting a value from
# a configuration file using perl.
#
# TIP: Instead of hard-coding a particular variable and filename, generalize the
# operation with a subroutine that accepts arguments. This will make your code
# more readable and provide you with recyclable code that can be used in
# other programs or become part of a module
#
#
#chomp(my $interval = `grep chkservd_check_interval /var/cpanel/cpanel.config | cut -d= -f2`);
my $interval = get_config_value('/var/cpanel/cpanel.config',
                                'chkservd_check_interval',
                                '=');
#debug('Value of chkservd_check_interval: ' . $interval);

#
# PERFORMANCE CONSIDERATIONS
#
# TIP: Instead of tailing the log and then re-looping through it again, it
# would be more efficient to perform necessary filtering and time calculation
# as you read it the first time (easier said than done!). This script
# uses the functions seek() and read() to work backwards fromt he end of the
# log file and perform the necessary filtering and time calculations in one
# pass.
# 
# TIP: With regular expressions, you should generally follow the "simpler is
# better" rule. Instead of using a regex that maps the timestamp parts to
# date, time and timezone, you can just look for lines matching
# [xxxx-xx-xx ? ?] and then split on the space character to get the time and
# timezone
#
# TIP: Avoid running expensive operations multiple times. Obviously, don't
# loop within a loop if there is no real need to do so. Less obviously,
# run just one regex and extract the needed info in one pass.
#
# Pattern that matches the beginning of each log entry in /var/log/chkservd.log
# The timestamp portion must be enclosed in () to permit extraction
my $chkservd_entry_start_pattern = '^\[([\d]{4}\-[\d]{2}\-[\d]{2} [^\]]*)\]';

#
# Call main function that grabs chkservd errors going back X days
#
my @log_entries_and_durations = chkservd_errors($days);
foreach (@log_entries_and_durations) {
    print "@$_[0]\n";
    printf("Time since last error: %s\n",
           seconds_to_human_readble_time(@$_[1])) if @$_[1];
    print "\n";
}

#
# Subroutines
#

#
# TIP: write a general-purpose subroutine, such as log_entries_by_date(), that
# accomplishes the general task (in this case, dividing a log into entries while
# keeping track of the time elapsed between matching entries). Then, use a 
# more user-friendly function that accepts fewer arguments to accomplish a
# more specific task (like parsing chkservd).
#
# This has various benefits some of which are:
# - Code is more recyclable
# - Code is more flexible
# - Generalization forces you to think conceptually and thus more powerfully
#
# Chkservd-specific function that calls the main log parser with the appropriate
# arguments
sub chkservd_errors {
    my $days = shift;
    my $log_file = '/var/log/chkservd.log';

    #
    # TODO: Figure out why '**' part of search pattern is not working
    #

    # If no search pattern, use default one that looks for common problems
    my $search_pattern = shift ||
            'Restart|nable|\*\*|imeout|ailure|terrupt|100%|9[89]%|second';

    return log_entries_by_date($log_file,
                               $chkservd_entry_start_pattern,
                               $days,
                               $search_pattern,
                               1000);
}

#
# TIP: This script doesn't make use the following function, get_config_value(),
# but I'm including it to illustrate what you would want to do instead of
# calling the 'grep' shell command
#
# Return the value of a particular variable in a configuration file
#
sub get_config_value {

    my $filename = shift;
    my $variable = shift;
    my $delimiter = shift || '=';
    my $value;

    # Throw error if required input not present
    die "Missing input\n" if !$filename or !$variable;

    my $fh;
    my @matching_lines;

    open $fh, $filename or die "Could not open $filename: $!";
    @matching_lines = grep /^$variable\s?$delimiter/, <$fh>;

    # Get rid of trailing newline
    chomp @matching_lines;

    # Throw error if no matches or multiple matches
    if (!scalar @matching_lines) {
        die "No entry for '$variable' found in $filename\n";
    }

    # Scalar context of array equal to number of entries
    elsif (scalar @matching_lines > 1) {
        die "More than one entry for '$variable' in $filename\n"
    }

    # Grab value, trimming any whitespace
    $value = (split($delimiter, $matching_lines[0]))[1];
    $value =~ s/^\s+|\s+$//g;

    return $value;
}

#
# Get array of log entries going back to a particular date
#
sub log_entries_by_date {
    my $filename = shift;
    my $entry_start_pattern = shift;
    my $days = shift || 1;
    my $search_pattern = shift;
    my $bytes = shift || 200; # For maximum efficiency, should be a little
                              # greater than the average log entry length

    # Throw error if required input not present
    if (!$filename || !$entry_start_pattern) {
        die "Missing input for log_entries_by_date()\n";
    }

    #
    # Prepare variables
    #
    my @elapsed_times;
    my @entries;
    my $fh;
    my $final_seek = 0;
    my $last_entry_epoch_time;
    my @result;
    my $start_epoch_time;
    my $tail_of_chopped_entry = '';
    my $this_chunk = '';
    my $timestamp_pattern;

    my $todays_epoch_time = time;
    if ($days) {
        $start_epoch_time = $todays_epoch_time - $days * 24 * 60 * 60;
    }

    # Ensure sign makes sense. Should always be negative when tailing so as to
    # count backwards from the end of the file.
    $bytes = -$bytes if ($bytes > 0);

    # If input variable for line pattern regex contains the '^' start-of-line
    # character, remove it
    $entry_start_pattern =~ s/^\^//;

    # Extract start date pattern from timestamp pattern
    $timestamp_pattern = $entry_start_pattern;
    $timestamp_pattern =~ s/^.*(\(.*\)).*$/$1/ or die "Couldn't extract date",
            "from pattern. Timestamp should be surrounded by parentheses.\n";

    # Open log file
    open $fh, $filename or die "Could not open $filename: $!\n";

    #
    # The following seek will read in chunks of the file, reading backwards
    # from the end of the file. Each chunk will then be analyzed to see
    # if it contains any entries, which will be added to an array of entries
    # as they are found. The elapsed time between entries will also be tracked
    # in a separate array
    #

    #
    # Explanation of 'seek' function, as it is not self-evident what it does
    #
    # Seek sets the filehandle's position. You can optionally seek from EOF by
    # using WHENCE = 2 (SEEK_END) for WHENCE tail a file.
    #
    # seek FILEHANDLE,POSITION,WHENCE
    # Values for WHENCE:
    #       0 - SEEK_SET - new position in bytes
    #       1 - SEEK_CUR - current position + POSITION
    #       2 - SEEK_END - EOF + POSITION (negative position backtracks from
    #                      end of file)
    seek $fh, $bytes, 2;
    {
        my $buffer;
        my $characters_parsed;
        my $fh_pointer_position;
        my $leftmost_match_offset;
        my @offsets;
        my $this_chunk_length;
        my $this_timestamp;

        # Need to know pointer position if this is the first iteration of seek
        # just in case we're already within $bytes of the top of the file. If
        # so, indicate that this is the last loop. Otherwise, this chunk will
        # be read in twice
        unless ($fh_pointer_position) {
            $fh_pointer_position = tell($fh);
            if ($fh_pointer_position <= -$bytes) {
                $final_seek = 1;
            }
        }

        # Read chunk of data of size $bytes
        read $fh, $buffer, -$bytes;

        # Look at data read into buffer plus remainder from previous loop
        $this_chunk = $buffer . $this_chunk . $tail_of_chopped_entry;

        # Prepend a newline if this is the top of the file so that regex
        # can identify it as a log entry (matching on '\n<start of entry>')
        $this_chunk = "\n" . $this_chunk if $final_seek;

        # Find offsets for all entries contained within this chunk. These
        # offsets will be used later to extract out any entries found in this
        # chunk
        while ($this_chunk =~ /\n($entry_start_pattern)/g) {
            push @offsets, $-[0];
        }

#debug(@offsets);

        # NOTE: it would be nice to just write a function to extract the
        # entries and return the leftover part, but we also need to check the
        # timestamps to know when we've looked far enough back in the file

        # If matches found, save current buffer for next loop
        if (scalar @offsets) {

            # NOTE: The following foreach() function is a loop within a loop.
            # However, it is efficient because we are only looping through a
            # handful of entries at most and there is no easy way to just
            # magically suck the matching entries out of the chunk we are
            # inspecting and also filter unmatching results and analyze the
            # timestamp

            # Load entries in this chunk into array (parsing array in reverse
            # order is easier
            $this_chunk_length = length($this_chunk);
            $characters_parsed = 0;
            foreach my $offset (reverse @offsets) {

                # Length of part of chunk we're looking at now
                my $newline_plus_entry_length =
                        $this_chunk_length - $offset - $characters_parsed;

                # Get part that represents a log entry (minus leading newline)
                my $entry = substr($this_chunk,
                                   $offset + 1,
                                   $newline_plus_entry_length - 1);

#debug($entry);
                # Other variables specific to foreach loop
                my $seconds_since_match;
                my $this_timestamp;
                my $this_epoch_time;

                # Increment the variable holding the number of characters
                # already looked at for use in next iteration
                $characters_parsed = $characters_parsed +
                                     $newline_plus_entry_length;

                # The very last entry in the log will have a hanging newline
                # which should be removed, so chomp last entry in case it
                # happens to also be the very last entry
                chomp($entry) unless scalar @entries;

                # Remember offset of start of first entry for later use
                $leftmost_match_offset = $offset;

                # Extract timestamp from entry
                if ($entry =~ /^$entry_start_pattern/) {
                    $this_timestamp = $1;
                }
                # TODO: What is the most compatible way to convert
                # string to epoch time (need to respect timezone)?
                # Convert timestamp to epoch time
                $this_epoch_time = Date::Parse::str2time($this_timestamp);

                # Load entry into array
                if (!$search_pattern or
                        $search_pattern and $entry =~ /$search_pattern/) {
                    push(@entries, $entry);

                    # Calculate the elapsed time between matches
                    if ($last_entry_epoch_time) {
                        $seconds_since_match = $last_entry_epoch_time -
                                               $this_epoch_time;
                    }
                    push(@elapsed_times, $seconds_since_match);

                    # Save this time for next iteration
                    $last_entry_epoch_time = $this_epoch_time;
                }

                # Stop looping if this entry's time is prior to target time
                if ($start_epoch_time && $this_epoch_time < $start_epoch_time) {
                    $final_seek = 1;
                    last;
                }
            }

            # Save leftover part of chopped entry so that it can be appended to
            # the chunk in the next loop
            $tail_of_chopped_entry = substr($this_chunk,
                                            0,
                                            $leftmost_match_offset);

            # Clear this chunk so that it is not prepended in next seek
            $this_chunk = '';
        }
        else {
            # If nothing matched, no remaining piece of log needs to be saved
            $tail_of_chopped_entry = '';
        }
       
        # Save position of filehandle pointer as this is important in figuring
        # out when we're near the top of the file
        $fh_pointer_position = tell($fh);

        # Stop reading if we just read the very top of the file
        last if $final_seek or $DEBUG and scalar @entries > 10;

        # Move file pointer up so that we can read previous block of data
        if ($fh_pointer_position < -$bytes * 2) {
            $final_seek = 1;
            $bytes = -$fh_pointer_position;
            seek $fh, 0, 0;
        } else {
            seek $fh, $bytes * 2, 1;
        }

        redo; # Loop unless we've reached the top of the file
    }

    # Reverse entries found in this chunk as values were read pushed into
    # arrays in reverse order
    @entries = reverse @entries;
    @elapsed_times = reverse @elapsed_times;

    # Values in elapsed time array need to be shifted such that their offsets
    # correspond with those of entries array. This is because the calculated
    # times were necessarily calculated with a one-iteration delay.
    unshift(@elapsed_times, undef);

    # Combine elements of arrays into one two-dimensional array
    for my $i (0 .. $#entries) {
        my @pair = ($entries[$i], $elapsed_times[$i]);
        push(@result, \@pair);
    }

    return @result;
}

#
# TIP: It is almost always better to store raw values until they are displayed
#      to the user. For example, the time elapsed between logs should be stored
#      as an integer value representing the number of seconds between entries.
#      When you need to render the time to a human, then format it using
#      a subroutine such as the following
#
sub seconds_to_human_readble_time {
    my $secs = shift;
    if ($secs < 1) {
        return;
    }
    elsif ($secs >= 365 * 24 * 60 * 60) {
        return sprintf '%.1fy', $secs / (365 * 24 * 60 * 60);
    }
    elsif ($secs >= 24 * 60 * 60) {
        return sprintf '%.1fd', $secs / (24 * 60 * 60);
    }
    elsif ($secs >= 60 * 60) {
        return sprintf '%.1fh', $secs / (60 * 60);
    }
    elsif ($secs >= 60) {
        return sprintf '%.1fm', $secs / 60;
    }
    else {
        return sprintf '%.1fs', $secs;
    }
}

#
# Data::Dumper is very useful for debugging as it shows you the contents of
# complex data types such as arrays, hashes, and objects
#
use Data::Dumper;
sub debug {
    print Dumper(@_) if $DEBUG;
}
