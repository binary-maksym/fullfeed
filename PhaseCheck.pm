use strict;
use warnings;

package PhaseCheck;

sub new {
    my ($class, $args) = @_;
    my $self = bless {}, $class;
    $self->setParams($args);
    return $self;
}

sub get_errors {
    my ($self, $params) = @_;
    my $symbol = $params->{symbol} || $self->{symbol};
    my $long   = $params->{long}   || $self->{long};
    my $short  = $params->{short}  || $self->{short};

    unless ($symbol) {
        $self->_add_error("Symbol is needed!");
    }
    unless ($long) {
        $self->_add_error("Long period is needed!");
    }
    unless ($short) {
        $self->_add_error("Short period is needed!");
    }
    $self->_validate;

    $self->{spots} = $self->tail_idata;
    my $errors = {};
    foreach my $provider (keys %{$self->{spots}}) {
        next if $provider eq 'FXCM';
        $errors->{$provider} = $self->get_min_error({
            sample_name => $provider,
            ref_name    => 'FXCM'
        });
    }
    return $errors;
}

sub get_min_error {

    my ($self, $params) = @_;

    my $sample_name = $params->{sample_name};
    my $ref_name    = $params->{ref_name};
    my $long        = $params->{long} || $self->{long};
    my $short       = $params->{short} || $self->{short};

    if (!$sample_name || !$self->{spots}->{$sample_name}) {
        $self->_add_error("Not valid sample contributor name is provided!");
    }

    if (!$ref_name || !$self->{spots}->{$ref_name}) {
        $self->_add_error("Not valid ref contributor name is provided!");
    }

    if (!$long) {
        $self->_add_error("Long period is not provided!");
    }

    if (!$short) {
        $self->_add_error("Short period is not provided!");
    }

    my $time_shift = ($long - $short) / 2;
    unless ($time_shift > 0) {
        $self->_add_error("Long period should be greater than short period");
    }

    if (ref $self->{spots} ne 'HASH') {
        $self->_add_error("There is no spots!");
    }

    $self->_validate;

    my $a         = [sort(keys %{$self->{spots}->{$ref_name}})];
    my $ref_lists = {
        epoches => [sort(keys %{$self->{spots}->{$ref_name}})],
        spots   => $self->{spots}->{$ref_name}};

    my %sample;
    $self->{_last_epoch} = $ref_lists->{epoches}->[scalar(@{$ref_lists->{epoches}}) - 1];
    foreach (keys %{$self->{spots}->{$sample_name}}) {
        if ($_ >= $ref_lists->{epoches}->[0] + $time_shift && $_ <= $ref_lists->{epoches}->[scalar(@{$ref_lists->{epoches}}) - 1] - $time_shift) {
            $sample{$_} = $self->{spots}->{$sample_name}->{$_};
        }
    }

    unless (scalar keys %sample) {
        return;
    }

    my %err;
    my ($best_timeshift, $min_err);
    my $sample_lists = {
        epoches => [sort keys %sample],
        spots   => \%sample
    };

    for (my $i = -$time_shift; $i <= $time_shift; $i++) {
        $err{$i} = $self->calculate_err({
            sample     => $sample_lists,
            ref        => $ref_lists,
            time_shift => $i
        });

        if (!defined($min_err) || $err{$i} < $min_err) {
            ($best_timeshift, $min_err) = ($i, $err{$i});
        }
    }

    return {
        delay        => $best_timeshift,
        err          => $err{0} - $min_err,
        ticks_number => scalar keys %sample
    };
}

sub calculate_err {

    my ($self, $params) = @_;

    my $time_shift = $params->{time_shift} || 0;

    if (!$params->{sample} || !$params->{ref}) {
        $self->_add_error("Sample and Ref are required");
    }
    $self->_validate;

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

sub setParams {
    my ($self, $params) = @_;
    if ($params->{path} && (-e $params->{path})) {
        $self->{path} = $params->{path};
    }
    if ($params->{symbol} && $params->{symbol} =~ /^[a-z0-9]+$/i) {
        $self->{symbol} = $params->{symbol};
    }
    if ($params->{long} && $params->{long} >= 2 * 60 && $params->{long} <= 20 * 60) {
        $self->{long} = $params->{long};
    }
    if ($params->{short} && $params->{short} >= 2 * 60 && $params->{short} <= 20 * 60) {
        $self->{short} = $params->{short};
    }
    if ($params->{period} && $params->{period} =~ /^[0-9]+$/ && $params->{period} > 0) {
        $self->{period} = $params->{period};
    }
    if ($params->{result_path} && (-e $params->{result_path})) {
        $self->{result_path} = $params->{result_path};
    }
}

sub tail_idata {
    my ($self, $params) = @_;

    my $path = $params->{path};
    if (!$path) {
        my $date = $self->_get_current_date;
        $path = "$self->{path}/idata/$self->{symbol}/$date-fullfeed.csv";
    }

    my $interval = $params->{interval} || $self->{long};
    if (!(-f $path)) {
        return {};
    }

    if (!$interval) {
        $self->_add_error("Interval (Long) is not provided!");
    }

    $self->_validate;

    open my $bw, "-|", "tail", "-r", $path;

    my %spots;
    my $last_epoch;
    my $spots = {};
    while (my $line = <$bw>) {
        chomp $line;
        my @fields = split /\,/, $line;
        $last_epoch = $fields[0] if !$last_epoch;
        last if $fields[0] + $interval < $last_epoch;
        next if $fields[6] && $fields[6] =~ /BADSRC/;
        $spots->{$fields[5]} = {} if !$spots->{$fields[5]};
        $spots->{$fields[5]}->{($fields[5] eq 'FXDD' ? $fields[0] - 10 : $fields[0])} = $fields[4];
    }
    close $bw;

    return $spots;
}

sub save_to_file {
    my ($self, $params) = @_;
    my $path = $params->{'path'};
    if (!$path && $self->{symbol} && $self->{result_path}) {
        $path = "$self->{result_path}/$self->{symbol}.csv";
    }
    if (!$path) {
        $self->_add_error('Valid path for result file saving should be provided!');
    }
    if (ref $params->{errors} ne 'HASH') {
        $self->_add_error('Valid error list should be provided!');
    }

    $self->_validate;

    open(my $fh, ">>", $path) or _add_error('Can not create file!');

    $self->_validate;

    my $last_epoch = $self->{_last_epoch} || '';
    foreach (keys %{$params->{errors}}) {
        my $err = $params->{errors}->{$_};
        if ($err) {
            print $fh "$_,$err->{delay},$err->{err},$err->{ticks_number},$last_epoch\n";
        }
    }

    close $fh;
}

sub run {
    my ($self, $period) = @_;

    if (!$period) {
        $period = $self->{period};
    }

    if (!$period) {
        $self->_add_error('Timeout should be provided!');
    }

    $self->_validate;

    while (1) {
        my $errors = $self->get_errors;
        $self->save_to_file({errors => $errors});
        sleep $period;
    }
}

sub setSpots {
    my ($self, $spots) = @_;
    $self->{spots} = $spots;
}

sub _get_current_date {
    my $self = shift;
    my ($sec, $min, $hour, $day, $month, $year) = gmtime;
    my $date = "$day-" . $self->_month_to_name($month) . "-" . ($year + 1900);
    return $date;
}

sub _add_error {
    my ($self, $error) = @_;
    $self->{_error} = [] if (ref $self->{_error} ne 'ARRAY');
    push @{$self->{_error}}, $error;
}

sub _validate {
    my ($self, $error) = @_;
    if (ref $self->{_error} eq 'ARRAY') {
        print join("\n", @{$self->{_error}}) . "\n";
        die();
    }
}

sub _month_to_name {
    my $self   = shift;
    my $number = shift;
    my %m      = (
        0  => 'Jan',
        1  => 'Feb',
        2  => 'Mar',
        3  => 'Apr',
        4  => 'May',
        5  => 'Jun',
        6  => 'Jul',
        7  => 'Aug',
        8  => 'Sep',
        9  => 'Oct',
        10 => 'Nov',
        11 => 'Dec'
    );
    return $m{$number};
}

1;
