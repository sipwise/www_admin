package admin::Model::Provisioning;

use strict;
use warnings;
use base 'Catalyst::Model';
use Scalar::Util;
use Catalyst::Plugin::Authentication;

use Sipwise::Provisioning::Voip;
use Sipwise::Provisioning::Billing;

=head1 NAME

admin::Model::Provisioning - Sipwise provisioning catalyst model

=head1 DESCRIPTION

Catalyst Model that uses Sipwise::Provisioning::Voip to get and set VoIP
admin and user data.

=cut

sub new {
    my $class = shift;

    my $self = {};
    $$self{voip} = Sipwise::Provisioning::Voip->new();
    $$self{billing} = Sipwise::Provisioning::Billing->new();

    return bless $self, $class;
}

sub call_prov {
    # model, catalyst, scalar, scalar, hash-ref, scalar-ref
    my ($self, $c, $backend, $function, $parameter, $result) = @_;

    $c->log->debug("***Provisioning::call_prov calling '$backend\::$function'");

    eval {
        $$result = $$self{$backend}->handle_request( $function,
                                                     {
                                                       authentication => {
                                                                           type     => 'admin',
                                                                           username => $c->session->{admin}{login},
                                                                           password => $c->session->{admin}{password},
                                                                         },
                                                       parameters => $parameter,
                                                   });
    };

    if($@) {
        if(ref $@ eq 'SOAP::Fault') {
            $c->log->error("***Provisioning::call_prov: $backend\::$function failed: ". $@->faultstring);
            $c->session->{prov_error} = $@->faultcode;
        } else {
            $c->log->error("***Provisioning::call_prov: $backend\::$function failed: $@");
            $c->session->{prov_error} = 'Server.Internal';
        }
        return;
    }

    return 1;
}

##########################
# non-standard functions #
##########################

sub login {
    my ($self, $c, $admin, $password) = @_;

    $c->log->debug('***Provisioning::login called, authenticating...');

    unless(defined $admin and length $admin) {
        $c->session->{prov_error} = 'Client.Voip.MissingUsername';
        return;
    }
    unless(defined $password and length $password) {
        $c->session->{prov_error} = 'Client.Voip.MissingPass';
        return;
    }

    unless(Scalar::Util::blessed($admin)
           and ($Catalyst::Plugin::Authentication::VERSION < 0.10003
                ? $admin->isa("Catalyst::Plugin::Authentication::User")
                : $admin->isa("Catalyst::Authentication::User")))
    {
        if(my $user_obj = $self->_get_admin($c, $admin)) {
            $admin = $user_obj;
        } else {
            if($c->session->{prov_error} and $c->session->{prov_error} eq 'Server.Voip.NoSuchAdmin') {
                $c->log->info("***Provisioning::login authentication failed for '$admin', unknown login.");
                $c->session->{prov_error} = 'Client.Voip.AuthFailed';
            }
            return;
        }
    }
    if($self->_auth_admin($c, $admin, $password)) {
        $c->set_authenticated($admin);
        $c->log->debug('***Provisioning::login authentication succeeded.');
        $$admin{password} = $password;
        $c->session->{admin} = $admin;
        return 1;
    }

    $c->log->info("***Provisioning::login authentication failed for '$$admin{login}', wrong password.");
    $c->session->{prov_error} = 'Client.Voip.AuthFailed';
    return;
}

sub localize {
    my ($self, $lang, $messages) = @_;

    return unless defined $messages;

    if(ref $messages eq 'HASH') {
        my %translations;
        foreach my $msgname (keys %$messages) {
            $translations{$msgname} = eval { $$self{voip}->get_localized_string({language => $lang, code => $$messages{$msgname}}) };
            unless(defined $translations{$msgname}) {
                $translations{$msgname} = eval { $$self{voip}->get_localized_string({language => $lang, code => 'Server.Internal'}) };
            }
        }
        return \%translations;
    } elsif(!ref $messages) {
        my $translation = eval { $$self{voip}->get_localized_string({language => $lang, code => $messages}) };
        unless(defined $translation) {
            $translation = eval { $$self{voip}->get_localized_string({language => $lang, code => 'Server.Internal'}) };
        }
        return $translation;
    }

    return;
}



####################
# helper functions #
####################

sub _get_admin {
    my ($self, $c, $login) = @_;

    my $admin_obj = eval {
        $$self{billing}->get_admin({login => $login});
    };
    if($@) {
        if(ref $@ eq 'SOAP::Fault') {
            $c->log->error("***Provisioning::_get_admin failed to get admin '$login' from DB: ". $@->faultstring)
                unless $@->faultcode eq 'Server.Voip.NoSuchAdmin';
            $c->session->{prov_error} = $@->faultcode;
        } else {
            $c->log->error("***Provisioning::_get_admin failed to get admin '$login' from DB: $@.");
            $c->session->{prov_error} = 'Server.Internal';
        }
        return;
    }
    my $return = { %$admin_obj, id => $login, store => $self };
    if($Catalyst::Plugin::Authentication::VERSION < 0.10003) {
        return bless $return, "Catalyst::Plugin::Authentication::User::Hash";
    } else {
        return bless $return, "Catalyst::Authentication::User::Hash";
    }
}

sub _auth_admin {
    my ($self, $c, $admin, $pass) = @_;

    eval { $$self{billing}->authenticate_admin({ login => $$admin{login},
                                                 password => $pass,
                                              });
    };
    if($@) {
        if(ref $@ eq 'SOAP::Fault') {
            $c->log->error("***Provisioning::_auth_admin failed to auth admin '$$admin{login}': ". $@->faultstring);
            $c->session->{prov_error} = $@->faultcode;
        } else {
            $c->log->error("***Provisioning::_auth_admin failed to auth admin '$$admin{login}': $@.");
            $c->session->{prov_error} = 'Server.Internal';
        }
        return;
    }

    return 1;
}

=head1 BUGS AND LIMITATIONS

=over

=item currently none

=back

=head1 SEE ALSO

Sipwise::Provisioning::Voip, Sipwise::Provisioning::Billing, Catalyst

=head1 AUTHORS

Daniel Tiefnig <dtiefnig@sipwise.com>

=head1 COPYRIGHT

The Provisioning model is Copyright (c) 2007-2008 Sipwise GmbH, Austria.
All rights reserved.

=cut

# ende gelaende
1;
