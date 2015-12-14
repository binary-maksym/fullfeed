use strict;
use warnings;
# use File::ReadBackwards;
use Time::Local;

my ($path,$long,$short,$symbol,$interval,$where);
for(my $i=0; $i < scalar @ARGV; $i++){
	if($ARGV[$i] eq '-p'){
		$path = $ARGV[$i+1]; 
	}
	elsif($ARGV[$i] eq '-l'){
		$long = $ARGV[$i+1]; 
	}
	elsif($ARGV[$i] eq '-s'){
		$short = $ARGV[$i+1]; 
	}
	elsif($ARGV[$i] eq '-u'){
		$symbol = $ARGV[$i+1]; 
	}
	elsif($ARGV[$i] eq '-i'){
		$interval = $ARGV[$i+1]; 
	}
    elsif($ARGV[$i] eq '-w'){
        $where = $ARGV[$i+1]; 
    }
	elsif($ARGV[$i] eq '-h'){
		print qq~	-p = path to feed folder
    -w = path to folder where to save the result
	-l = long period in minutes
	-s = short period in minutes
	-u = underlying name
	-i = calculate delay every i minutes
	-h = this manual
~;
		exit;
	}
}

my @errors;
if(!$path || !(-f $path)){
    push @errors, "Incorrect path to feed folder!";
}

if($where && !(-f $where)){
    push @errors, "Incorrect path to result folder is provided!";
}

unless($long && $long=~/^[0-9]+$/ && $long >=2 && $long<=20){
    push @errors, "Long period should be between 2 and 20 minutes";
}

unless($short && $short=~/^[0-9]+$/ && $short >=2 && $short<$long){
    push @errors, "Short period should be between 2 minutes and long period";
}

unless($symbol && $symbol=~/^[0-9a-z]+$/i){
   push @errors, "Incorrect underlying name is provided";
}

unless($interval && $interval=~/^[0-9]+$/ && $interval > 0){
    push @errors, "Incorrect interval is provided";
}

if(scalar @errors){
    print join("\n", @errors)."\n";
    exit;
}


use Data::Dumper;
print Dumper (\($path,$long,$short,$symbol,$interval));

$path   = '/Users/maksym/work/binary/fullfeed/feed';
$long   = 3 * 60;                                      # interval in seconds
$short  = 2 * 60;                                      # interval in seconds
$symbol = 'frxEURUSD';




my $last_time;
open(my $fh, ">>", "delays.csv") or die();

# for(my $i=1447286399;$i>=1447200000;$i-=3*60){
for(my $i=1447286399;$i>=1447286399;$i-=3*60){
# for(my $i=1448927755;$i>=1448927755-2*3*60;$i-=3*60){
	$last_time = $i;
	print $last_time."\n";
	# $last_time = 1448927755;

	my $errors = get_providers_errors({
	    symbol => $symbol,
	    long   => $long,
	    short  => $short
	});
	
	

	foreach(keys %{$errors}){
		my $err = $errors->{$_};
		if($err){
			print $fh "$_,$err->{delay},$err->{err},$err->{ticks_number},$last_time\n";
		}
	}

}

close $fh;

sub get_providers_errors {

    my $params = shift;
    if (!$params->{symbol} || !$params->{long} || !$params->{short}) {
        die "symbol and long and short are required!";
    }

    my $idata = tail_idata({
            symbol   => $params->{symbol},
            interval => $params->{long}});

    # my $combined = tail_combined({
    #         symbol   => $params->{symbol},
    #         interval => $params->{long}});

    # my %data = (%$idata, %$combined);
    my %data = %$idata;
    my %errors;

    foreach my $provider (keys %data) {
        next if $provider eq 'FXCM';
        $errors{$provider} = get_min_error({
                sample => $data{$provider},
                ref    => $data{'FXCM'},
                long   => $params->{long},
                short  => $params->{short}});
    }

    return \%errors;
}

sub get_min_error {

    my $params = shift;

    my $sample_full = $params->{sample};
    my $ref         = $params->{ref};
    my $long        = $params->{long};
    my $short       = $params->{short};

    if (!$sample_full || !$ref || !$long || !$short) {
        die "sample list and ref list and long and short are required";
    }

    my $time_shift = ($long - $short) / 2;

    my $ref_lists = get_lists($ref);
    
    my %sample;
    foreach(keys %$sample_full){
    	if($_ >= $ref_lists->{epoches}->[0] + $time_shift && $_ <= $ref_lists->{epoches}->[scalar(@{$ref_lists->{epoches}}) - 1] - $time_shift){
    		$sample{$_}=$sample_full->{$_};
    	}
    }
    
    unless (scalar keys %sample) {
        return;
    }

    my %err;
    my ($best_timeshift, $min_err);
    my $sample_lists = get_lists(\%sample);

    for (my $i = -$time_shift; $i <= $time_shift; $i++) {
        $err{$i} = calculate_err({
            sample     => $sample_lists,
            ref        => $ref_lists,
            time_shift => $i
        });

        if (!defined($min_err) || $err{$i} < $min_err) {
            ($best_timeshift, $min_err) = ($i, $err{$i});
        }
    }

    return {
        delay => $best_timeshift,
        err   => $err{0}-$min_err,
        ticks_number => scalar keys %sample
    };
}

sub calculate_err {
	
    my $params = shift;
    my $time_shift = $params->{time_shift} || 0;
    if (!$params->{sample} || !$params->{ref}) {
        die "sample and ref are required";
    }

    my ($sample_epochs, $sample_spots, $ref_epochs, $ref_spots) =
        ($params->{sample}->{epoches}, $params->{sample}->{spots}, $params->{ref}->{epoches}, $params->{ref}->{spots});

    my $error = 0;
    foreach my $epoch (@$sample_epochs) {
        my $sample_epoch = $epoch - $time_shift;
        my $ref_value;
        if (!$ref_spots->{$sample_epoch}) {
            for (my $i = 1; $i < scalar @$ref_epochs; $i++) {
                if ($ref_epochs->[$i] > $sample_epoch) {
                    $ref_spots->{$sample_epoch} =
                        $ref_spots->{$ref_epochs->[$i - 1]} +
                        ($sample_epoch - $ref_epochs->[$i - 1]) *
                        ($ref_spots->{$ref_epochs->[$i]} - $ref_spots->{$ref_epochs->[$i - 1]}) /
                        ($ref_epochs->[$i] - $ref_epochs->[$i - 1]);
                    last;
                }
            }
        }
        $error += ($ref_spots->{$sample_epoch} - $sample_spots->{$epoch})**2;
    }

    return $error;
}

sub tail_idata {
	
    my $params   = shift;
    my $interval = $params->{interval} || 5;
    my $symbol   = $params->{symbol};

    if (!$symbol) {
        die 'Symbol required!';
    }
    my $bw = get_file_handler({
            symbol => $symbol,
            type   => 'idata'
        }) || return {};
    my $last_epoch;

    my %spots;
    # while (defined(my $line = $bw->readline)) {
    	# print Dumper $bw;
    while (my $line = <$bw>) {
        chomp $line;
        my @fields = split /\,/, $line;
        $last_epoch = $fields[0] if !$last_epoch && (!$last_time || $last_time > $fields[0]);
        next if !$last_epoch;
        last if $fields[0] + $interval < $last_epoch;
        next if $fields[6] && $fields[6] =~ /BADSRC/;
        $spots{$fields[5]} = {} if !$spots{$fields[5]};
        $spots{$fields[5]}->{($fields[5] eq 'FXDD' ? $fields[0]-10 : $fields[0])} = $fields[4];
    }
    close $bw;

    return \%spots;
}

sub tail_combined {

    my $params   = shift;
    my $interval = $params->{interval} || 5;
    my $symbol   = $params->{symbol};

    if (!$symbol) {
        die 'Symbol required!';
    }

    my $bw = get_file_handler({
            symbol => $symbol,
            type   => 'combined'
        }) || return {};

    my $last_epoch;
    my %spots;
    # while (defined(my $line = $bw->readline)) {
    while (my $line = <$bw>) {
        chomp $line;
        my @fields = split / /, $line;

        my ($mday, $mon, $year) = split(/\-/, get_date());
        $mon = get_month_number($mon);
        $year += 2000;
        my ($hour, $min, $sec) = split(/:/, $fields[0]);
        my $epoch = timegm($sec, $min, $hour, $mday, $mon, $year) + 0;

        $last_epoch = $epoch if !$last_epoch && (!$last_time || $last_time > $epoch);
        next if !$last_epoch;
        if ($epoch + $interval < $last_epoch) {
            last;
        }
        $spots{$fields[5]} = {} if !$spots{$fields[5]};
        $spots{$fields[5]}->{$epoch} = $fields[4];
    }
    close $bw;

    return \%spots;
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

sub get_file_handler {
    my $params = shift;
    if (!$params->{symbol} || !$params->{type}) {
        die 'Symbol and type required!';
    }
    my $date = get_date();
    my $fp;
    if ($params->{type} eq 'idata') {
        $fp = "$path/idata/$params->{symbol}/$date-fullfeed.csv";
    } elsif ($params->{type} eq 'combined') {
        $fp = "$path/combined/$params->{symbol}/$date.fullfeed";
    }
    my $bw;
    if ($fp) {
    	open $bw, "-|", "tail", "-r", $fp;
        # $bw = File::ReadBackwards->new($fp);
    }

    return $bw;
}

sub get_date {
    return '11-Nov-15';
}

sub get_lists {
    my $list_hashes = shift;

    my (@arr, %hash);
    foreach (sort keys %$list_hashes) {
        push @arr, $_;
        $hash{$_} = $list_hashes->{$_};
    }
    return {
        epoches => \@arr,
        spots   => \%hash
    };
}

