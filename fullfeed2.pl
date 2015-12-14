use strict;
use warnings;
use PhaseCheck;
use Data::Dumper;
# create a new Shape object
my $phasecheck = PhaseCheck->new({
    symbol => 'frxEURUSD',
    long   => 3 * 60,
    short  => 2 * 60,
    path   => '/Users/maksym/work/binary/fullfeed/feed',
    result_path => '/Users/maksym/work/binary/fullfeed',
    period => 5
});
my $errors = $phasecheck->run;
