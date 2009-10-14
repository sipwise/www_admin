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

    $settings{local} = $c->request->params->{local} ? 1 : 0;

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

    $settings{local} = $c->request->params->{local} ? 1 : 0;

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

=head2 detail

Show details for a given domain: rewrite rules

=cut

sub detail : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/domain_detail.tt';

    my $domain = $c->request->params->{domain};

    my $domain_rw;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_domain_rewrites',
                                                        { domain => $domain },
                                                        \$domain_rw
                                                      );
    $c->stash->{domain} = $domain_rw;
    $c->stash->{iteditid} = $c->request->params->{iteditid};

    my $audio_files;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_audio_files',
                                                        { domain => $domain },
                                                        \$audio_files
                                                      );
    $c->stash->{audio_files} = $$audio_files{result} if eval { @{$$audio_files{result}} };

    $c->stash->{edit_audio} = $c->request->params->{edit_audio};

    if(exists $c->session->{acrefill}) {
        $c->stash->{acrefill} = $c->session->{acrefill};
        delete $c->session->{acrefill};
    }
    if(exists $c->session->{aerefill}) {
        $c->stash->{aerefill} = $c->session->{aerefill};
        delete $c->session->{aerefill};
    } elsif($c->request->params->{edit_audio}) {
        foreach my $audio (eval { @{$$audio_files{result}} }) {
            if($$audio{handle} eq $c->request->params->{edit_audio}) {
                $c->stash->{aerefill} = $audio;
                last;
            }
        }
    }

    return 1;
}

=head2 create_rewrite

Create a rewrite rule for a given domain

=cut

sub create_rewrite : Local {
    my ( $self, $c ) = @_;

    my %messages;
    my %settings;

    my $domain = $c->request->params->{domain};
    my $match_pattern = $c->request->params->{match_pattern};
    my $replace_pattern = $c->request->params->{replace_pattern};
    my $description = $c->request->params->{description};

    unless(keys %messages) {
        if($c->model('Provisioning')->call_prov( $c, 'voip', 'create_domain_rewrite',
                                                 { domain => $domain,
                                                   match_pattern => $match_pattern,
                                                   replace_pattern => $replace_pattern,
                                                   description => $description,
                                                 },
                                                 undef
                                               ))
        {
            $messages{icalleemsg} = 'Server.Voip.SavedSettings';
            $c->session->{messages} = \%messages;
            $c->response->redirect("/domain/detail?domain=$domain");
            return;
        }
        else
        {
            $messages{icalleeerr} = 'Client.Voip.InputErrorFound';
        }
    } else {
    }

    $c->session->{messages} = \%messages;
    $c->response->redirect("/domain/detail?domain=$domain");
    return;
}

=head2 edit_rewrite

Updates a rewrite rule

=cut

sub edit_rewrite : Local {
    my ( $self, $c ) = @_;

    my %messages;
    my %settings;

    my $domain = $c->request->params->{domain};
    my $rewriteid = $c->request->params->{rewriteid};
    my $match_pattern = $c->request->params->{match_pattern};
    my $replace_pattern = $c->request->params->{replace_pattern};
    my $description = $c->request->params->{description};

    unless(keys %messages) {
        if($c->model('Provisioning')->call_prov( $c, 'voip', 'update_domain_rewrite',
                                                 { id => $rewriteid,
                                                   match_pattern => $match_pattern,
                                                   replace_pattern => $replace_pattern,
                                                   description => $description,
                                                 },
                                                 undef
                                               ))
        {
            $messages{icalleemsg} = 'Server.Voip.SavedSettings';
            $c->session->{messages} = \%messages;
            $c->response->redirect("/domain/detail?domain=$domain");
            return;
        }
        else
        {
            $messages{icalleeerr} = 'Client.Voip.InputErrorFound';
        }
    } else {
    }

    $c->session->{messages} = \%messages;
    $c->response->redirect("/domain/detail?domain=$domain");
    return;
}

=head2 delete_rewrite

Delete a rewrite rule

=cut

sub delete_rewrite : Local {
    my ( $self, $c ) = @_;

    my %messages;
    my %settings;

    my $domain = $c->request->params->{domain};
    my $rewriteid = $c->request->params->{rewriteid};

    unless(keys %messages) {
        if($c->model('Provisioning')->call_prov( $c, 'voip', 'delete_domain_rewrite',
                                                 { id => $rewriteid
                                                 },
                                                 undef
                                               ))
        {
            $messages{icalleemsg} = 'Server.Voip.SavedSettings';
            $c->session->{messages} = \%messages;
            $c->response->redirect("/domain/detail?domain=$domain");
            return;
        }
    } else {
    }

    $c->session->{messages} = \%messages;
    $c->response->redirect("/domain/detail?domain=$domain");
    return;
}

=head2 do_create_audio

Store a new audio file in the database.

=cut

sub do_create_audio : Local {
    my ( $self, $c ) = @_;

    my %messages;
    my %settings;

    $settings{domain} = $c->request->params->{domain};
    unless(length $settings{domain}) {
        $c->response->redirect("/domain");
        return;
    }
    $settings{handle} = $c->request->params->{handle};
    $settings{data}{description} = $c->request->params->{description}
        if length $c->request->params->{description};
    my $upload = $c->req->upload('cupload_audio');
    $settings{data}{audio} = eval { $upload->slurp };

    unless(keys %messages) {
        if($c->model('Provisioning')->call_prov( $c, 'voip', 'create_audio_file',
                                                 \%settings,
                                                 undef))
        {
            $messages{audiomsg} = 'Web.AudioFile.Created';
            $c->session->{messages} = \%messages;
            $c->response->redirect("/domain/detail?domain=$settings{domain}#audio");
            return;
        }
    }

    $messages{audioerr} = 'Client.Voip.InputErrorFound';
    $c->session->{messages} = \%messages;
    $c->session->{acrefill} = \%settings;
    $c->response->redirect("/domain/detail?domain=$settings{domain}#audio");
    return;
}

=head2 do_update_audio

Update an audio file in the database.

=cut

sub do_update_audio : Local {
    my ( $self, $c ) = @_;

    my %messages;
    my %settings;

    $settings{domain} = $c->request->params->{domain};
    unless(length $settings{domain}) {
        $c->response->redirect("/domain");
        return;
    }
    $settings{handle} = $c->request->params->{handle};
    unless(length $settings{handle}) {
        $c->response->redirect("/domain/detail?domain=$settings{domain}");
        return;
    }
    $settings{data}{description} = $c->request->params->{description};
    my $upload = $c->req->upload('eupload_audio');
    $settings{data}{audio} = eval { $upload->slurp } if defined $upload;

    unless(keys %messages) {
        if($c->model('Provisioning')->call_prov( $c, 'voip', 'update_audio_file',
                                                 \%settings,
                                                 undef))
        {
            $messages{audiomsg} = 'Web.AudioFile.Updated';
            $c->session->{messages} = \%messages;
            $c->response->redirect("/domain/detail?domain=$settings{domain}#audio");
            return;
        }
        $c->response->redirect("/domain/detail?domain=$settings{domain}&amp;edit_audio=$settings{handle}#audio");
        return;
    }

    $messages{audioerr} = 'Client.Voip.InputErrorFound';
    $c->session->{messages} = \%messages;
    $c->session->{aerefill} = $settings{data};
    $c->response->redirect("/domain/detail?domain=$settings{domain}&amp;edit_audio=$settings{handle}#audio");
    return;
}

=head2 do_delete_audio

Delete an audio file from the database.

=cut

sub do_delete_audio : Local {
    my ( $self, $c ) = @_;

    my %settings;

    $settings{domain} = $c->request->params->{domain};
    unless(length $settings{domain}) {
        $c->response->redirect("/domain");
        return;
    }
    $settings{handle} = $c->request->params->{handle};
    unless(length $settings{handle}) {
        $c->response->redirect("/domain/detail?domain=$settings{domain}");
        return;
    }

    if($c->model('Provisioning')->call_prov( $c, 'voip', 'delete_audio_file',
                                             \%settings,
                                             undef))
    {
        $c->session->{messages} = { provmsg => 'Web.AudioFile.Deleted' };
        $c->response->redirect("/domain/detail?domain=$settings{domain}#audio");
        return;
    }

    $c->response->redirect("/domain/detail?domain=$settings{domain}#audio");
    return;
}

=head2 listen_audio

Listen to an audio file from the database.

=cut

sub listen_audio : Local {
    my ( $self, $c ) = @_;

    my %settings;

    $settings{domain} = $c->request->params->{domain};
    unless(length $settings{domain}) {
        $c->response->redirect("/domain");
        return;
    }
    $settings{handle} = $c->request->params->{handle};
    unless(length $settings{handle}) {
        $c->response->redirect("/domain/detail?domain=$settings{domain}");
        return;
    }

    my $audio;
    if($c->model('Provisioning')->call_prov( $c, 'voip', 'get_audio_file',
                                             \%settings,
                                             \$audio))
    {
        $c->stash->{current_view} = 'Plain';
        $c->stash->{content_type} = 'audio/x-wav';
        $c->stash->{content} = eval { $$audio{audio}->value() };
        return;
    }

    $c->response->redirect("/domain/detail?domain=$settings{domain}#audio");
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
