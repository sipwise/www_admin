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

    my @plotdata = ();
    push @plotdata, {name=>"mem", title=>"Free Memory", 
        url=>"/rrd/get?path=memory/memory-free.rrd", si=>1};
    push @plotdata, {name=>"load", title=>"Load", 
        url=>"/rrd/get?path=load/load.rrd", si=>0};
    push @plotdata, {name=>"rdisk", title=>"Root Disk", 
        url=>"/rrd/get?path=df/df-root.rrd", si=>1};
    push @plotdata, {name=>"ldisk", title=>"Network Traffic", 
        url=>"/rrd/get?path=interface/if_octets-eth0.rrd", si=>1};

    $c->stash->{ctx} = "system";
    $c->stash->{plotdata} = \@plotdata;

    return 1;
}

sub voip : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/dashboard.tt';

    my @plotdata = ();
    push @plotdata, {name=>"provsub", title=>"Provisioned Subscribers", 
        url=>"/rrd/get?path=ngcp/oss_provisioned_subscribers.rrd", si=>0};
    push @plotdata, {name=>"regsubs", title=>"Registered Subscribers", 
        url=>"/rrd/get?path=ngcp/kam_usrloc_regusers.rrd", si=>0};
    push @plotdata, {name=>"actdlg", title=>"Active Calls", 
        url=>"/rrd/get?path=ngcp/kam_dialog_active.rrd", si=>0};
    push @plotdata, {name=>"sipr", title=>"SIP Register Latency", 
        url=>"/rrd/get?path=ngcp/sip_option.rrd", si=>0};

    $c->stash->{ctx} = "voip";
    $c->stash->{plotdata} = \@plotdata;

    return 1;
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
