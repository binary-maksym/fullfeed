package Fullfeed;
use strict;
use warnings;
use File::ReadBackwards;
use Data::Dumper;
use Time::Local;

my @providers = (
    combined => 1,
    idata    => 1
);
my $path     = 'feed';
my $interval = 5 * 60;        # interval in seconds
my $date     = '30-Nov-15';
my $symbol   = 'frxEURJPY';

my $test = read_combined($symbol, $date, $interval);
print Dumper $test;

sub read_idata {
    my $symbol    = shift;
    my $date      = shift;
    my $interval  = shift;
    my $file_path = "$path/idata/$symbol/$date-fullfeed.csv";
    my $bw        = File::ReadBackwards->new($file_path) or die "can't read '$file_path' $!";
    my $last_epoch;
    my @result;
    while (defined(my $line = $bw->readline)) {
        chomp $line;
        my @fields = split /\,/, $line;
        $last_epoch = $fields[0] if !$last_epoch;
        last if $fields[0] + $interval < $last_epoch;
        unshift @result,
            {
            epoch  => $fields[0],
            spot   => $fields[4],
            from   => $fields[5],
            remark => $fields[6]};
    }
    return \@result;
}

sub read_combined {
    my $symbol    = shift;
    my $date      = shift;
    my $interval  = shift;
    my $file_path = "$path/combined/$symbol/$date.fullfeed";
    my $bw        = File::ReadBackwards->new($file_path) or die "can't read '$file_path' $!";
    my $last_epoch;
    my @result;
    while (defined(my $line = $bw->readline)) {
        chomp $line;
        my @fields = split / /, $line;

        my ($mday, $mon, $year) = split(/\-/, $date);
        $mon = get_month_number($mon);
        $year += 2000;
        my ($hour, $min, $sec) = split(/:/, $fields[0]);
        my $epoch = timelocal($sec, $min, $hour, $mday, $mon, $year) + 0;

        $last_epoch = $epoch if !$last_epoch;
        last if $epoch + $interval < $last_epoch;
        unshift @result,
            {
            epoch  => $epoch,
            spot   => $fields[4],
            from   => $fields[5],
            remark => ''
            };
    }
    return \@result;
}

sub get_month_number {
    my $month  = shift;
    my %months = (
        Jan => 0,
        Feb => 1,
        Mar => 2,
        Apr => 3,
        May => 4,
        Jun => 5,
        Jul => 6,
        Aug => 7,
        Sep => 8,
        Oct => 9,
        Nov => 10,
        Dec => 11
    );
    return $months{$month};
}
