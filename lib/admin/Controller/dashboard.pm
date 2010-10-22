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
    push @plotdata, {name=>"mem", title=>"Memory", 
        url=>$c->config->{dashboard}{rrd_url_path}."/memory-used.rrd", si=>1};
    push @plotdata, {name=>"load", title=>"Load", 
        url=>$c->config->{dashboard}{rrd_url_path}."/load.rrd", si=>0};
    push @plotdata, {name=>"rdisk", title=>"Root Disk", 
        url=>$c->config->{dashboard}{rrd_url_path}."/df-root.rrd", si=>1};
    push @plotdata, {name=>"ldisk", title=>"Local Disk", 
        url=>$c->config->{dashboard}{rrd_url_path}."/df-disk.rrd", si=>1};

    $c->stash->{ctx} = "system";
    $c->stash->{plotdata} = \@plotdata;

    return 1;
}

sub voip : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/dashboard.tt';

    my @plotdata = ();
    push @plotdata, {name=>"sipo", title=>"SIP Option Latency", 
        url=>$c->config->{dashboard}{rrd_url_path}."/sip_option.rrd", si=>0};
    push @plotdata, {name=>"sipr", title=>"SIP Register Latency", 
        url=>$c->config->{dashboard}{rrd_url_path}."/sip_register.rrd", si=>0};
    push @plotdata, {name=>"mysql", title=>"DB Queries/sec", 
        url=>$c->config->{dashboard}{rrd_url_path}."/mysql.rrd", si=>0};
    push @plotdata, {name=>"ldisk", title=>"DB MGM Status", 
        url=>$c->config->{dashboard}{rrd_url_path}."/mysql_mgm.rrd", si=>0};

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

The dashboard controller is Copyright (c) 2010 Sipwise GmbH, Austria. All
rights reserved.

=cut

# ende gelaende
1;
