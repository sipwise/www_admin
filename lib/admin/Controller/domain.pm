package admin::Controller::domain;

use strict;
use warnings;
use base 'Catalyst::Controller';

=head1 NAME

admin::Controller::domain - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=head2 index 

Display domain list.

=cut

sub index : Private {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/domain.tt';

    my $domains;
    return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_domains',
                                                        undef,
                                                        \$domains
                                                      );
    $c->stash->{domains} = $$domains{result};

    $c->stash->{edit_domain} = $c->request->params->{edit_domain};

    if(ref $c->session->{restore_domedit_input} eq 'HASH') {
        foreach my $domain (@{$c->stash->{domains}}) {
            next unless $$domain{domain} eq $c->stash->{edit_domain};
            $domain = { %$domain, %{$c->session->{restore_domedit_input}} };
            last;
        }
        delete $c->session->{restore_domedit_input};
    }
    if(ref $c->session->{restore_domadd_input} eq 'HASH') {
        $c->stash->{arefill} = $c->session->{restore_domadd_input};
        delete $c->session->{restore_domadd_input};
    }

    return 1;
}

=head2 do_edit_domain 

Change settings for a domain.

=cut

sub do_edit_domain : Local {
    my ( $self, $c ) = @_;

    my %messages;
    my %settings;

    my $domain = $c->request->params->{domain};

    $settings{cc} = $c->request->params->{cc};
    $messages{ecc} = 'Client.Voip.MalformedCc'
        unless $settings{cc} =~ /^\d+$/;

    $settings{timezone} = $c->request->params->{timezone};
    $messages{etimezone} = 'Client.Syntax.MalformedTimezone'
        unless $settings{timezone} =~ m#^\w+/\w.+$#;

    unless(keys %messages) {
        if($c->model('Provisioning')->call_prov( $c, 'billing', 'update_domain',
                                                 { domain => $domain,
                                                   data   => \%settings,
                                                 },
                                                 undef
                                               ))
        {
            $messages{edommsg} = 'Server.Voip.SavedSettings';
            $c->session->{messages} = \%messages;
            $c->response->redirect("/domain");
            return;
        }
    } else {
        $messages{edomerr} = 'Client.Voip.InputErrorFound';
    }

    $c->session->{messages} = \%messages;
    $c->session->{restore_domedit_input} = \%settings;
    $c->response->redirect("/domain?edit_domain=$domain");
    return;
}

=head2 do_create_domain 

Create a new domain.

=cut

sub do_create_domain : Local {
    my ( $self, $c ) = @_;

    my %messages;
    my %settings;

    my $domain = $c->request->params->{domain};

    $settings{cc} = $c->request->params->{cc};
    $messages{acc} = 'Client.Voip.MalformedCc'
        unless $settings{cc} =~ /^\d+$/;

    $settings{timezone} = $c->request->params->{timezone};
    $messages{atimezone} = 'Client.Syntax.MalformedTimezone'
        unless $settings{timezone} =~ m#^\w+/\w.+$#;

    unless(keys %messages) {
        if($c->model('Provisioning')->call_prov( $c, 'billing', 'create_domain',
                                                 { domain => $domain,
                                                   data   => \%settings,
                                                 },
                                                 undef
                                               ))
        {
            $messages{cdommsg} = 'Server.Voip.SavedSettings';
            $c->session->{messages} = \%messages;
            $c->response->redirect("/domain");
            return;
        }
    } else {
        $messages{cdomerr} = 'Client.Voip.InputErrorFound';
    }

    $c->session->{messages} = \%messages;
    $c->session->{restore_domadd_input} = \%settings;
    $c->session->{restore_domadd_input}{domain} = $domain;
    $c->response->redirect("/domain");
    return;
}

=head2 do_delete_domain 

Delete a domain.

=cut

sub do_delete_domain : Local {
    my ( $self, $c ) = @_;

    my $domain = $c->request->params->{domain};
    if($c->model('Provisioning')->call_prov( $c, 'billing', 'delete_domain',
                                             { domain => $domain },
                                             undef
                                           ))
    {
        $c->session->{messages}{edommsg} = 'Web.Domain.Deleted';
        $c->response->redirect("/domain");
        return;
    }

    $c->response->redirect("/domain");
    return;
}

=head1 BUGS AND LIMITATIONS

=over

=item currently none

=back

=head1 SEE ALSO

Provisioning model, Sipwise::Provisioning::Billing, Catalyst

=head1 AUTHORS

Daniel Tiefnig <dtiefnig@sipwise.com>

=head1 COPYRIGHT

The domain controller is Copyright (c) 2007 Sipwise GmbH, Austria. All
rights reserved.

=cut

# ende gelaende
1;
