use strict;
use warnings;
use PhaseCheck;

my ($path, $long, $short, $symbol, $interval, $where);
for (my $i = 0; $i < scalar @ARGV; $i++) {
    if ($ARGV[$i] eq '-p') {
        $path = $ARGV[$i + 1];
    } elsif ($ARGV[$i] eq '-l') {
        $long = $ARGV[$i + 1];
    } elsif ($ARGV[$i] eq '-s') {
        $short = $ARGV[$i + 1];
    } elsif ($ARGV[$i] eq '-u') {
        $symbol = $ARGV[$i + 1];
    } elsif ($ARGV[$i] eq '-i') {
        $interval = $ARGV[$i + 1];
    } elsif ($ARGV[$i] eq '-w') {
        $where = $ARGV[$i + 1];
    } elsif ($ARGV[$i] eq '-h') {
        print qq~	-p = path to feed folder
    -w = path to folder where to save the result
	-l = long period in seconds
	-s = short period in seconds
	-u = underlying name
	-i = calculate delay every i seconds
	-h = this manual
~;
        exit;
    }
}

my @errors;
if (!$path || !(-e $path)) {
    push @errors, "Incorrect path to feed folder!";
}

if ($where && !(-e $where)) {
    push @errors, "Incorrect path to result folder is provided!";
}

unless ($long && $long =~ /^[0-9]+$/ && $long >= 2*60 && $long <= 20*60) {
    push @errors, "Long period should be between 2 and 20 minutes";
}

unless ($short && $short =~ /^[0-9]+$/ && $short >= 2*60 && $short < $long) {
    push @errors, "Short period should be between 2 minutes and long period";
}

unless ($symbol && $symbol =~ /^[0-9a-z]+$/i) {
    push @errors, "Incorrect underlying name is provided";
}

unless ($interval && $interval =~ /^[0-9]+$/ && $interval > 0) {
    push @errors, "Incorrect interval is provided";
}

if (scalar @errors) {
    print join("\n", @errors) . "\n";
    exit;
}

my $phasecheck = PhaseCheck->new({
    symbol      => $symbol,
    long        => $long,
    short       => $short,
    path        => $path,
    result_path => $where,
    period      => $interval
});

$phasecheck->run;

1;
