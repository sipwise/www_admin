package admin::Controller::rrd;

use strict;
use warnings;
use base 'Catalyst::Controller';
use admin::Utils;
use Data::Dumper;

=head1 NAME

admin::Controller::rrd - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut


=head2 get

Serves rrd files

=cut

sub get : Local {
    my ( $self, $c ) = @_;

    $c->log->debug('***rrd::get called');

    my $path = $c->request->params->{path};
    my $rrd;

    if($path and $c->model('Provisioning')->call_prov( $c, 'system', 'get_rrd', 
                                                              {path => $path}, \$rrd)) {
        $c->stash->{current_view} = 'Binary';
        $c->stash->{content_type} = 'application/octet-stream';
        $c->stash->{content} = $$rrd{content};
        return;
    }
    $c->response->redirect('/');
}

sub end : ActionClass('RenderView') {
    my ( $self, $c ) = @_;

    if(defined $c->stash->{current_view} and $c->stash->{current_view} eq 'Binary') {
        return 1;
    }

    $c->stash->{current_view} = 'Sipwise';
    unless($c->response->{status} =~ /^3/) { # only if not a redirect
        if(exists $c->session->{prov_error}) {
            $c->session->{messages}{prov_error} = $c->session->{prov_error};
            delete $c->session->{prov_error};
        }

        if(exists $c->session->{messages}) {
            $c->stash->{messages} = $c->model('Provisioning')->localize($c, $c->session->{messages});
            delete $c->session->{messages};
        }
    }

    $c->stash->{subscriber}{username} = $c->session->{user}{username};

    return 1; # shouldn't matter
}

=head1 BUGS AND LIMITATIONS

=over

=item none

=back

=head1 SEE ALSO

Provisioning model, Catalyst

=head1 AUTHORS

Andreas Granig <agranig@sipwise.com>

=head1 COPYRIGHT

The rrd controller is Copyright (c) 2010 Sipwise GmbH, Austria. You
should have received a copy of the licences terms together with the
software.

=cut

1;
