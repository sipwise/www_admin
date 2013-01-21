package admin::Controller::dashboard;

use strict;
use warnings;
use base 'Catalyst::Controller';
use Data::Dumper;
use UNIVERSAL 'isa';


=head1 NAME

admin::Controller::dashboard - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=head2 index

Control the statistics dashboard.

=cut

sub index : Private {
    my ( $self, $c ) = @_;

    if($c->config->{dashboard}{enabled} == 1)
    {
        $c->response->redirect($c->uri_for('/dashboard/system'));
    }
    else
    {
        $c->response->redirect($c->uri_for('/'));
    }

    return 1;
}

sub system : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/dashboard.tt';

    my @hosts = get_host_list();

    $c->stash->{hosts} = \@hosts;

    my $selected_host = grep($c->request->params->{server_to_show}, @hosts) ? $c->request->params->{server_to_show} : $hosts[0];

    $c->stash->{selected_host} = $selected_host;

    my @plotdata = ();
    push @plotdata, {name=>"mem", title=>"Free Physical Memory", url=>[(
    		"/rrd/get?path=$selected_host/memory/memory-free.rrd",
    		"/rrd/get?path=$selected_host/memory/memory-cached.rrd",
    		"/rrd/get?path=$selected_host/memory/memory-buffered.rrd"
    )], si=>1};
    push @plotdata, {name=>"swap", title=>"Free Swap Memory", 
        url=>"/rrd/get?path=$selected_host/swap/swap-free.rrd", si=>1};
    push @plotdata, {name=>"load", title=>"Load", 
        url=>"/rrd/get?path=$selected_host/load/load.rrd", si=>0};
    push @plotdata, {name=>"rdisk", title=>"Root Disk", 
        url=>"/rrd/get?path=$selected_host/df/df-root.rrd", si=>1};
    push @plotdata, {name=>"ldisk", title=>"Network Traffic", 
        url=>"/rrd/get?path=$selected_host/interface/if_octets-eth0.rrd", si=>1};

    $c->stash->{ctx} = "system";
    $c->stash->{plotdata} = \@plotdata;
    $c->stash->{tz_offset} = admin::Utils::tz_offset();

    return 1;
}

sub voip : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/dashboard.tt';

    my @hosts = get_host_list();

    $c->stash->{hosts} = \@hosts;

    my $selected_host = grep($c->request->params->{server_to_show}, @hosts) ? $c->request->params->{server_to_show} : $hosts[0];

    $c->stash->{selected_host} = $selected_host;

    my @plotdata = ();
    push @plotdata, {name=>"provsub", title=>"Provisioned Subscribers", 
        url=>"/rrd/get?path=$selected_host/ngcp/oss_provisioned_subscribers.rrd", si=>0};
    push @plotdata, {name=>"regsubs", title=>"Registered Subscribers", 
        url=>"/rrd/get?path=$selected_host/ngcp/kam_usrloc_regusers.rrd", si=>0};
    push @plotdata, {name=>"actdlg", title=>"Active Calls", 
        url=>"/rrd/get?path=$selected_host/ngcp/kam_dialog_active.rrd", si=>0};
    push @plotdata, {name=>"sipr", title=>"SIP Register Latency", 
        url=>"/rrd/get?path=$selected_host/ngcp/sip_option.rrd", si=>0};

    $c->stash->{ctx} = "voip";
    $c->stash->{plotdata} = \@plotdata;
    $c->stash->{tz_offset} = admin::Utils::tz_offset();

    return 1;
}

sub sipstats: Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/dashboard.tt';
    my $stats;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_sipstat_24h',
                                                        undef,
                                                        \$stats,
                                                      );
    $c->stash->{stats} = $stats;

    my @hosts = get_host_list();

    $c->stash->{hosts} = \@hosts;

    my $selected_host = grep($c->request->params->{server_to_show}, @hosts) ? $c->request->params->{server_to_show} : $hosts[0];

    $c->stash->{selected_host} = $selected_host;

    my @plotdata = ();
    push @plotdata, {name=>"numpacketsperday", title=>"Captured SIP Packets per Day", 
        url=>"/rrd/get?path=$selected_host/ngcp/sipstats_num_packets_perday.rrd", si=>0};
    push @plotdata, {name=>"numpackets", title=>"Overall Available SIP Packets", 
        url=>"/rrd/get?path=$selected_host/ngcp/sipstats_num_packets.rrd", si=>0};
    push @plotdata, {name=>"partsize", title=>"Size of Capture Table", 
        url=>"/rrd/get?path=$selected_host/ngcp/sipstats_partition_size.rrd", si=>1};

    $c->stash->{ctx} = "sipstats";
    $c->stash->{plotdata} = \@plotdata;
    $c->stash->{tz_offset} = admin::Utils::tz_offset();

    return 1;
}

sub get_host_list {
    my $rrd_dirs = '/var/lib/collectd/rrd';
    my @hosts = qw();

    open(RRD_DIRS, "find $rrd_dirs -mindepth 1 -maxdepth 1 -type d | sort |") || die "can't use find in $rrd_dirs";
    while (<RRD_DIRS>) {
      chomp;
      s|.*/||;
      push @hosts, $_;
    }

    return @hosts;
}

=head1 BUGS AND LIMITATIONS

=over

=item none

=back

=head1 SEE ALSO

Provisioning model, Sipwise::Provisioning::Billing, Catalyst

=head1 AUTHORS

Andreas Granig <agranig@sipwise.com>

=head1 COPYRIGHT

The dashboard controller is Copyright (c) 2010 Sipwise GmbH, Austria.
You should have received a copy of the licences terms together with the
software.

=cut

# ende gelaende
1;
