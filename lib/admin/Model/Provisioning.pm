package admin::Model::Provisioning;

use strict;
use warnings;
use base 'Catalyst::Model';
use Scalar::Util;
use Catalyst::Plugin::Authentication;

use Sipwise::Provisioning::Voip;
use Sipwise::Provisioning::Billing;
use Sipwise::Provisioning::System;

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
    $$self{system} = Sipwise::Provisioning::System->new();

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
        my $perr = $@;
        if(ref $perr eq 'SOAP::Fault') {
            $c->log->error("***Provisioning::call_prov: $backend\::$function failed: ". $perr->faultstring);
            $c->session->{prov_error} = $perr->faultcode;
            $c->session->{prov_error_object} = $perr->faultdetail->{object}
                if defined eval { $perr->faultdetail->{object} };
        } else {
            $c->log->error("***Provisioning::call_prov: $backend\::$function failed: $perr");
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

    $c->session->{admin}{login} = $admin;
    $c->session->{admin}{password} = $password;
    if(my $adm_obj = $self->_get_admin($c, $admin)) {
        $c->set_authenticated($adm_obj);
        $c->log->debug('***Provisioning::login authentication succeeded.');
        $$adm_obj{password} = $password;
        $c->session->{admin} = $adm_obj;
        return 1;
    } else {
        delete $c->session->{admin};
        if($c->session->{prov_error} and $c->session->{prov_error} eq 'Client.Voip.AuthFailed') {
            $c->log->info("***Provisioning::login authentication failed for '$admin'.");
        }
        return;
    }
}

sub localize {
    my ($self, $c, $lang, $messages) = @_;

    return unless defined $messages;
    if(! defined $c->session->{admin}) {
        if($messages eq 'Client.Voip.AuthFailed') {
            return 'Login failed, please verify username and password.';
        }
        return;
    }

    if(ref $messages eq 'HASH') {
        my %translations;
        foreach my $msgname (keys %$messages) {
            $translations{$msgname} = $self->_translate($c, $$messages{$msgname}, $lang);
        }
        return \%translations;
    } elsif(!ref $messages) {
        return $self->_translate($c, $messages, $lang);
    }

    return;
}



####################
# helper functions #
####################

sub _get_admin {
    my ($self, $c, $login) = @_;

    my $admin_obj;
    $self->call_prov($c, 'billing', 'get_admin', { login => $login }, \$admin_obj)
        or return;

    my $return = { %$admin_obj, id => $login };
    if($Catalyst::Plugin::Authentication::VERSION < 0.10003) {
        return bless $return, "Catalyst::Plugin::Authentication::User::Hash";
    } else {
        return bless $return, "Catalyst::Authentication::User::Hash";
    }
}

sub _translate {
    my ($self, $c, $code, $lang) = @_;

    my $translation;
    eval {
        $self->call_prov( $c, 'voip', 'get_localized_string',
                          { language => $lang, code => $code },
                          \$translation,
                        )
    };
    unless(defined $translation) {
        eval {
            $self->call_prov( $c, 'voip', 'get_localized_string',
                              { language => $lang, code => 'Server.Internal' },
                              \$translation,
                            )
        };
    }

    return $translation;
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

The Provisioning model is Copyright (c) 2007-2010 Sipwise GmbH, Austria.
You should have received a copy of the licences terms together with the
software.

=cut

# ende gelaende
1;
