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
#      hand, such issues are rare, so you are usuall fine using it to visually
#      differentiate user-defined subroutine calls from built-in functions.
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
# TIP: Sometimes a problem can be more efficiently solved by writing a short
#      subroutine rather than requiring an external module.
#

# cPanel-specific tips
#
# Tip: When using external modules, try to use on that cpanel installs for
#      its version of perl. For example, Time::Piece appears to already be
#      installed on cpanel servers, while Date::Parse is not always installed.
#
use Time::Local;
#use Time::Piece;
#use Time::Seconds;
#use File::ReadBackwards;
#use Date::Parse;

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
my ($days, $filter_pattern) = @ARGV;
#debug($days, $filter_pattern);exit;

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
# more scalable, readable and recycle-able
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
# TIP: Avoid running expensive operations multiple times. Obviously, don't
# loop within a loop if there is no real need to do so. Less obviously,
# run just one regex and extract the needed info in one pass.
#
# TIP: With regular expressions, you should generally follow the "simpler is
# better" rule. Instead of using a regex that maps the timestamp parts to
# date, time and timezone, you can just look for lines matching
# [xxxx-xx-xx ? ?] and then split on the space character to get the time and
# timezone. I'm assuming that splitting on a single character is significantly
# faster than doing an extract-by-regex operation, but I've never tested that
# theory.
#
# Pattern that matches the beginning of each log entry in /var/log/chkservd.log
# The timestamp portion must be enclosed in () to permit extraction
#my $chkservd_entry_start_pattern = '^\[([\d]{4}\-[\d]{2}\-[\d]{2} [^\]]*)\]';
my $chkservd_entry_start_pattern = '^\[([\d]{4}\-[\d]{2}\-[\d]{2} [0-9\:\+ ]{14})\]';

#
# Call main function that grabs chkservd errors going back X days
#
my @entries = chkservd_grep($days);
debug(@entries);
exit;
foreach my $entry (@entries) {
#debug($entry);
    print "$entry->{'text'}\n";
    if ($entry->{'last_seen'}) {
        keys %{$entry->{'last_seen'}};
        while (my ($label, $time) = each %{$entry->{'last_seen'}}) {
            next unless $time;
            printf(
                "Time since previous %s: %s\n",
                $label,
                seconds_to_human_readable_time(
                    $entry->{'time'} - $time
                )
            );
        }
    }
    print "\n";
}
#        foreach my $last_seen_event (@{$entry->{'last_seen'}}) {
#debug($last_seen_event);
#            my $label = (keys %{$last_seen_event})[0];
#            printf("Time since last $label: %s\n",
#                    seconds_to_human_readable_time(
#                        $entry->{'time'} - $last_seen_event->{'time'}
#                    ));
#        }
#    }
#    print "\n";
#}

#
# Subroutines
#

#
# TIP: write a general-purpose subroutine, such as get_entries_from_log(), that
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
sub chkservd_grep {
    my $days = shift;
    my $log_file = '/var/log/chkservd.log';

    #
    # TODO: Figure out why '**' part of search pattern is not working
    #

    # If no search pattern, use default one that looks for common problems
    my $filter_pattern = shift ||
            'Restart|nable|\*\*|imeout|ailure|terrupt|100%|9[89]%|second';

    return get_entries_from_log($log_file,
                               $chkservd_entry_start_pattern,
                               $days,
                               $filter_pattern,
#                               500,
                               1000,
#                               5000,
#                               10000,
#                               20000,
#                               40000,
#                               80000,
                               'check', 'Service check');
                               #'tmp warning', '/tmp');
                               #'socket', 'socket');
}
#    my $filename = shift;
#    my $entry_start_pattern = shift;
#    my $days = shift || 1;
#    my $filter_pattern = shift || '.*';
#    my $bytes = shift || 200; # For maximum efficiency, should be a little
#                              # greater than the average log entry length
#
## Input for evnet types should be either of the following
##     - a string, which should be a regex pattern to watch for
##     - an array containing event labels and respective regex patterns to 
##       identify the event:
##           (label1, pattern1, [label2, pattern2], ...)
#my $last_seen_events_input = shift;


#
# Get epoch time (unix time) from a timestamp string
#
sub epoch_time_from_timestamp {
    my $timestamp = shift;
    my ($date, $time, $offset) = split(' ', $timestamp);
    die "Invalid timestamp!\n" unless $date and $time and $offset;
    my ($year, $month, $day) = split('-', $date);
    die "Invalid date!\n" unless $year and $month and $day;
    if ($year < 100) {
        if ($year < 70) {
            $year = $year + 2000;
        }
        else {
            $year = $year + 1900;
        }
    }
    my ($hour, $minute, $second) = split(':', $time);
    die "Invalid time!\n" unless $hour and $minute and $second;
    my $uncorrected_epoch_time = timegm($second, $minute, $hour,
                                        $day, $month - 1, $year);
    my $offset_multiplier = substr($offset, 0, 1) eq '+' ? 1 : -1;
    my $offset_hours = substr($offset, 1, 2);
    my $offset_minutes = substr($offset, 3, 2);
    my $offset_seconds = $offset_hours * 60 * 60 + $offset_minutes * 60;
    $offset_seconds = $offset_seconds * $offset_multiplier;
    return $uncorrected_epoch_time - $offset_seconds;
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
    die "Missing input!\n" if !$filename or !$variable;

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
sub get_entries_from_log {
    my $filename = shift;
    my $entry_start_pattern = shift;
    my $days = shift || 1;
    my $filter_pattern = shift || '.*';
    my $bytes = shift || 200; # For maximum efficiency, should be a little
                              # greater than the average log entry length

    # Input for event types should be either of the following
    #     - a string, which should be a regex pattern to watch for
    #     - an array containing event labels and respective regex patterns to 
    #       identify the event:
    #           (label1, pattern1, [label2, pattern2], ...)
    my $last_seen_events_input = \@_;

    # Watched events are repackaged into an array of hashes, each hash with the
    # following structure:
    # { $label => { 'pattern' => $pattern, 'time' => $time } }
    my @last_seen_events;

    # Always make the filter match the first event type to watch for
    push(@last_seen_events, {
            'filter match' => {
                'pattern' => $filter_pattern,
                'time' => undef
            }
        });

    # If watching for entries matching other patterns, add them to the array
    if ($last_seen_events_input) {

        # If just one element, it means input was just a pattern, so add it
        # with generic label
        if (scalar @$last_seen_events_input < 2) {
            push(@last_seen_events, {
                    'watched event' => {
                        'pattern' => @$last_seen_events_input[0],
                        'time' => undef
                    }
                });
        }
        else {
            # Valid input has an even number of elements (label, pattern)
            if (scalar @$last_seen_events_input % 2) {
                die "Invalid 'last seen' input!\n";
            }
            # Convert event input into array of name/value pairs
            my %h = @$last_seen_events_input;

            # Load each event into array
            keys %h;
            while(my($label, $pattern) = each %h) {
                push(@last_seen_events, {
                        $label => {
                            'pattern' => $pattern,
                            'time' => undef
                        }
                    });
            }
        }
    }

    # Throw error if required input not present
    if (!$filename || !$entry_start_pattern) {
        die "Missing input!\n";
    }

    #
    # Prepare variables
    #

    my $bytes_read;

    # Set how often the date should be parsed out and converted to epoch time
    # in order to determine if we've read back to the cutoff date yet. Doing
    # this periodically speeds up read times
#    my $check_date_every_x_entries = 1;
#    my $check_date_every_x_entries = 10;
    my $check_date_every_x_entries = 100;
#    my $check_date_every_x_entries = 1000;
#    my $check_date_every_x_entries = 10000;

    my @entries;
#    my $entries_count = 0;

    my $fh;
    my $final_seek = 0;
    my $lower_datecheck_offset = 0;
    my $pointer_position_after_seek;

#    # Track entry offset to facilitate doing things every X iterations
#    my $seek_offset = 0;

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
            "from pattern. Timestamp should be enclosed in parentheses.\n";

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
    # using WHENCE = 2 (SEEK_END) to tail a file.
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
        my $leftmost_match_offset;
        my @offsets;
        my $this_chunk_length;

        # When reading the file for the first time, check to see if the
        # length of the file is less than the size of the chunk we are reading
        # on each iteration. If so, indicate that this is the final seek
        unless ($pointer_position_after_seek) {
            $pointer_position_after_seek = tell($fh) - $bytes;
        }
        if ($pointer_position_after_seek <= 2 * -$bytes) {
            $final_seek = 1;
        }

#debug('pointer position after seek', $pointer_position_after_seek);

#debug('before read bytes', $bytes);
        # Read chunk of data of size $bytes
        $bytes = -(read $fh, $buffer, -$bytes);
#        $bytes_read = read $fh, $buffer, -$bytes;

#        # If the amount of data read is different than requested, we've reached
#        # the top of the file, so this will be the final seek
#        if ($bytes_read < -$bytes) {
#            $bytes = -$bytes_read;
#            $final_seek = 1;
#        }

#debug('after read bytes', $bytes);
#        read $fh, $buffer, -$bytes;

#debug('buffer', $buffer);
# This shouldn't happen, but no need to continue if nothing to read
last unless $bytes;

        # Look at data read into buffer plus remainder from previous loop
#        $this_chunk = $buffer . $this_chunk . $tail_of_chopped_entry;
        $this_chunk = $buffer . $this_chunk . $tail_of_chopped_entry;

#        # Prepend a newline if this is the top of the file so that regex
#        # can identify it as a log entry (matching on '\n<start of entry>')
#        $this_chunk = "\n" . $this_chunk if $final_seek;

# Artificially prepend a newline to handle the special case that this is the
# very first line in the file, which would be excluded without the newline. Note
# that this newline must be removed later on from the string that is passed to
# the next interation
$this_chunk = "\n" . $this_chunk;

        # Find offsets for all entries contained within this chunk. These
        # offsets will be used later to extract out any entries found in this
        # chunk
        while ($this_chunk =~ /\n($entry_start_pattern)/g) {
            push @offsets, $-[0];
        }

#debug('offsets:', @offsets);
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

            # While iterating in reverse order, extract entries from this chunk,
            # saving matching entries into array and performing other
            # calculations
            $this_chunk_length = length($this_chunk);
            $characters_parsed = 0;
            ENTRIES_IN_CHUNK:
            foreach my $offset (reverse @offsets) {

                # Length of part of chunk we're looking at now
                my $newline_plus_entry_length =
                        $this_chunk_length - $offset - $characters_parsed;

                # Get part that represents a log entry (minus leading newline)
                my $entry = substr($this_chunk,
                                   $offset + 1,
                                   $newline_plus_entry_length - 1);

                # Increment the variable holding the number of characters
                # already looked at for use in next iteration
                $characters_parsed = $characters_parsed +
                                     $newline_plus_entry_length;

                # The very last entry in the log will have a hanging newline
                # which should be removed, so chomp last extracted entry in case
                # it also happens to be the very last entry in the file
                chomp($entry) unless scalar @entries;

                # Remember offset of start of first entry for later use
                $leftmost_match_offset = $offset;                    

                # Elements in result array will consist of both the pattern
                # filtering on as well as the "last seen" patterns we're
                # watching.

                # These last seen patterns are needed to be able to calculate
                # elapsed times between occurrances and will be removed later
                LAST_SEEN_EVENTS:
                foreach my $last_seen_event (@last_seen_events) {
                    my $label = (keys %{$last_seen_event})[0];

#debug('checking...');
#debug($entry, $last_seen_event->{$label}->{'pattern'});
                    # If any patterns match, add that entry
                    if ($entry =~ /$last_seen_event->{$label}->{'pattern'}/) {
#debug('adding entry!');
                        chomp $entry;
#                        $entries_count = push(@entries, $entry);
                        push(@entries, $entry);
                        last LAST_SEEN_EVENTS;
                    }
                }
            } # END ENTRIES_IN_CHUNK foreach

            # Save leftover part of chopped entry so that it can be appended to
            # the chunk in the next loop. Note that the extra leading newline
            # that was artificially added must be stripped off
            $tail_of_chopped_entry = substr(substr($this_chunk, 1),
                                            0,
                                            $leftmost_match_offset);

            # If any entries found in chunk, empty it for the next iteration
            $this_chunk = '';
        }
        else {
            # If nothing matched, no remaining piece of log needs to be saved
            $tail_of_chopped_entry = '';
        }

#        # Keep track of which seek we're on so we can check certain things
#        # every X seeks
#        $seek_offset = $seek_offset + 1;

        # If we're only going back to a certain date, then every so often check
        # if we've reached the cutoff date. If so, prune entries past cutoff
        # date and break out of the seek loop
#        if ($start_epoch_time and $entries_count) {
        if ($start_epoch_time and scalar @entries) {

            # Check if we've reached cuttof date only periodically to avoid
            # doing too many expensive regex and timestamp-to-epoch time
            # conversions. Also, be sure to prune if this is the last seek loop
            # so as not to forget to prune after the very last iteration
            if (!(scalar @entries % $check_date_every_x_entries) or
                    $final_seek) {

                # Pass entries array by reference so that it can be trimmed if
                # any old entries found. Also need to break out of seek loop if 
                # any old entries are found since that means we're done
                last if prune_old_entries(\@entries,
                                          $lower_datecheck_offset,
                                          $start_epoch_time,
                                          $entry_start_pattern);
#debug('entries:', @entries);
                # Remember the offset we should start on for the next date check
                $lower_datecheck_offset = scalar @entries;
            }
        }

        # Set pointer position after seek
        $pointer_position_after_seek = tell($fh);

        # Seek upwards to grab next chunk
        seek $fh, $bytes * 2, 1;

        # Continue looping until we've reached the top of the file. Top of file
        # is detected when the pointer position is the same as the number of
        # bytes to read per seek
        redo unless $final_seek;
    }

    # Reverse entries found in this chunk as values were read pushed into
    # arrays in reverse order
    @entries = reverse @entries;
debug(@entries);exit;
    return filter_entries(\@entries, \@last_seen_events, $entry_start_pattern);
}

sub filter_entries {

    my $entries = shift;
    my $events = shift;
    my $entry_start_pattern = shift;

    my @filtered_entries;
    my @last_seen_events;

    foreach my $entry (@{ $entries }) {
        foreach my $event (@{ $events }) {
            my $label = (keys %{$event})[0];
            my $this_epoch_time;
            my $this_timestamp;
            if ($entry =~ /$event->{$label}->{'pattern'}/) {
                if ($label eq 'filter match') {
                    push(@filtered_entries, {
                            'entry' => $entry,
                            'last_seen_events' => \@last_seen_events
                        });
                    @last_seen_events = ();
                }
                else {
                    if ($entry =~ /^$entry_start_pattern/) {
                        $this_timestamp = $1;
                        $this_epoch_time =
                                epoch_time_from_timestamp($this_timestamp);
                    }
                    if ($this_epoch_time) {
                        push(@last_seen_events, {
                                $label => $this_epoch_time
                            });
                    }
                }
            }
        }
    }
    return @filtered_entries;
}

# TODO: it might be more efficient to just check the first entry, then the
# middle entry, then halfway from middle to end (or middle to beginning), etc.
# instead of looking at the whole array. However, the logic is too complex and
# hurts my brain.
sub prune_old_entries {
    my $reversed_entries = shift;
    my $start_offset = shift;
    my $start_epoch_time = shift;
    my $pattern = shift;

    my $i = scalar @{ $reversed_entries } - 1;
    my $old_entries_found = 0;

    for ($i = scalar @{ $reversed_entries } - 1; $i >= $start_offset; $i--) {
        # Other variables specific to foreach loop
        my $this_timestamp;
        my $this_epoch_time;

        # Extract timestamp from entry
        if (${ $reversed_entries }[$i] =~ /^$pattern/) {
            $this_timestamp = $1;
        }
    
        # TODO: Decide whether it is worth writing a custom
        # function that converts a timestamp to epoch time
        #$this_epoch_time =
        #   Date::Parse::str2time($this_timestamp);
        $this_epoch_time = epoch_time_from_timestamp($this_timestamp);

# USING DELETE
#        if ($this_epoch_time < $start_epoch_time) {
#            delete @{ $reversed_entries }[$i];
#            $old_entries_found = 1;
#        }
#        else {
#            last;
#        }
#    }
#    return $old_entries_found;

# USING SPLICE        
#debug('start_epoch_time', $start_epoch_time);
#debug('this_epoch_time', $this_epoch_time);
        # Stop adding entries if we've reached cutoff date
        if ($this_epoch_time >= $start_epoch_time) {
            if (${ $reversed_entries }[$i + 1]) {
#debug('array size:', scalar @{ $reversed_entries });
#debug("\$i = $i");
#debug('# pruned:', scalar @{ $reversed_entries } - ($i + 1));
                splice(@{ $reversed_entries }, $i + 1,
                        scalar @{ $reversed_entries } - ($i + 1));
#debug(@{ $reversed_entries });
                return 1;
            }
#debug('array size:', scalar @{ $reversed_entries });
#debug("\$i = $i");
#debug('all ok', $i);
#debug(@{ $reversed_entries });
            return 0;
        }
    }

    # If we haven't returned yet, it means all entries are too old
#debug('start_epoch_time', $start_epoch_time);
#debug('this_epoch_time', $this_epoch_time);
#debug('array size:', scalar @{ $reversed_entries });
#debug("\$i = $i");
#debug('all pruned');
    splice(@{ $reversed_entries }, $i + 1,
            scalar @{ $reversed_entries } - ($i + 1));
#debug(@{ $reversed_entries });
    return 1;
}

sub populate_last_seen_times {
    my $log_entries = shift;
    my $last_seen_events = shift;

    my @entries = @{$log_entries};
    my @events = @{$last_seen_events};

    return unless scalar @entries and scalar @events;

    my $last_seen_hash = {};
   
    foreach my $event (@events) {
        my $label = (keys %{$event})[0];
        $last_seen_hash->{$label} = $event->{$label}->{'time'};
    }

    for (my $i = scalar @entries; $i--; ) {
        last if ($entries[$i]->{'last_seen'});
        $entries[$i]->{'last_seen'} = $last_seen_hash;
    }
}

#
# TIP: It is almost always better to store raw values until they are displayed
#      to the user. For example, the time elapsed between logs should be stored
#      as an integer value representing the number of seconds between entries.
#      When you need to render the time to a human, then format it using
#      a subroutine such as the following
#
sub seconds_to_human_readable_time {
    my $secs = shift;
    if ($secs >= 365 * 24 * 60 * 60) {
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

sub debug {
    print Dumper(@_) if $DEBUG;
}
