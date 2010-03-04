package admin::Controller::login;

use strict;
use warnings;
use base 'Catalyst::Controller';

=head1 NAME

admin::Controller::login - Catalyst Controller

=head1 DESCRIPTION

This allows a user to log in.

=head1 METHODS

=head2 index 

The authentication function.

=cut

sub index : Private {
    my ( $self, $c ) = @_;

    $c->log->debug('***login::index called');

    my $username = $c->request->params->{username} || "";
    my $password = $c->request->params->{password} || "";

    if ($username && $password) {
        if($c->model('Provisioning')->login($c, $username, $password)) {
            $c->log->debug('***Login::index login successfull');
            if($c->session->{unauth_uri}) {
                $c->log->debug('***Login::index redirecting user to '. $c->session->{unauth_uri});
                $c->response->redirect($c->session->{unauth_uri});
                delete $c->session->{unauth_uri};
                return;
            }
        }
    } else {
        $c->session->{prov_error} = 'Client.Syntax.LoginMissingPass' unless length $password;
        $c->session->{prov_error} = 'Client.Syntax.LoginMissingUsername' unless length $username;
    }

    $c->response->redirect($c->uri_for('/'));
}

=head1 BUGS AND LIMITATIONS

=over

=item currently none

=back

=head1 SEE ALSO

Provisioning model, Catalyst

=head1 AUTHORS

Daniel Tiefnig <dtiefnig@sipwise.com>

=head1 COPYRIGHT

The login controller is Copyright (c) 2007-2010 Sipwise GmbH, Austria.
All rights reserved.

=cut

# ende gelaende
1;
