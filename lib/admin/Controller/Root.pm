package admin::Controller::Root;

use strict;
use warnings;
use base 'Catalyst::Controller';

#
# Sets the actions in this controller to be registered with no prefix
# so they function identically to actions created in MyApp.pm
#
__PACKAGE__->config->{namespace} = '';

=head1 NAME

admin::Controller::Root - Root Controller for admin

=head1 DESCRIPTION

This provides basic functionality for the admin web interface.

=head1 METHODS

=head2 auto

Verify user is logged in.

=cut

# Note that 'auto' runs after 'begin' but before your actions and that
# 'auto' "chain" (all from application path to most specific class are run)
sub auto : Private {
    my ($self, $c) = @_;

    if ($c->controller =~ /^admin::Controller::Root\b/
        or $c->controller =~ /^admin::Controller::login\b/)
    {
        $c->log->debug('***Root::auto front page or login access granted.');
        return 1;
    }

    if (!$c->user_exists) {
        $c->log->debug('***Root::auto User not found, forwarding to /');
        $c->response->redirect($c->uri_for('/'));
        return;
    }

    return 1;
}

=head2 default

Display default page.

=cut

sub default : Private {
    my ( $self, $c ) = @_;

    if ($c->user_exists) {
        $c->stash->{template} = 'tt/default.tt';
    } else {
        $c->stash->{template} = 'tt/login.tt';
    }
}

=head2 end

Attempt to render a view, if needed.

=cut 

sub end : ActionClass('RenderView') {
    my ( $self, $c ) = @_;

    $c->stash->{current_view} = $c->config->{view};

    unless($c->response->{status} =~ /^3/) { # only if not a redirect
        if(exists $c->session->{prov_error}) {
            $c->stash->{prov_error} =
                $c->model('Provisioning')->localize($c->view($c->config->{view})->
                                                        config->{VARIABLES}{site_config}{language},
                                                    $c->session->{prov_error});
            delete $c->session->{prov_error};
        }

        if(exists $c->session->{messages}) {
            $c->stash->{messages} = $c->model('Provisioning')->localize($c->view($c->config->{view})->
                                                                            config->{VARIABLES}{site_config}{language},
                                                                        $c->session->{messages});
            delete $c->session->{messages};
        }
    }

    return 1;
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

The Root controller is Copyright (c) 2007 Sipwise GmbH, Austria. All
rights reserved.

=cut

# ende gelaende
1;
