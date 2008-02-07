package admin::Controller::logout;

use strict;
use warnings;
use base 'Catalyst::Controller';

=head1 NAME

admin::Controller::logout - Catalyst Controller

=head1 DESCRIPTION

This will log a user out.

=head1 METHODS

=head2 index 

The logout function.

=cut

sub index : Private {
    my ( $self, $c ) = @_;

    $c->log->debug('***logout::index called');

    $c->logout();

    delete $c->session->{admin};

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

The logout controller is Copyright (c) 2007 Sipwise GmbH, Austria. All
rights reserved.

=cut

# ende gelaende
1;
