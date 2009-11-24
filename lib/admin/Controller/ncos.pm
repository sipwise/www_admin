package admin::Controller::ncos;

use strict;
use warnings;
use base 'Catalyst::Controller';

=head1 NAME

admin::Controller::ncos - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=head2 index

Display and edit NCOS levels.

=cut

sub index : Private {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/ncos.tt';

    my $levels;
    return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_ncos_levels',
                                                        undef,
                                                        \$levels
                                                      );
    $c->stash->{levels} = $levels if eval { @$levels };


    $c->stash->{edit_level} = $c->request->params->{edit_level};

    if(exists $c->session->{crefill}) {
        $c->stash->{crefill} = $c->session->{crefill};
        delete $c->session->{crefill};
    }
    if(exists $c->session->{erefill}) {
        $c->stash->{erefill} = $c->session->{erefill};
        delete $c->session->{erefill};
    } elsif($c->request->params->{edit_level}) {
        foreach my $lvl (eval { @$levels }) {
            if($$lvl{level} == $c->request->params->{edit_level}) {
                $c->stash->{erefill} = $lvl;
                last;
            }
        }
    }

    return 1;
}

=head2 do_create_level

Create a new NCOS level in the database.

=cut

sub do_create_level : Local {
    my ( $self, $c ) = @_;

    my %messages;
    my %settings;

    $settings{level} = $c->request->params->{level};
    $settings{data}{mode} = $c->request->params->{mode}
        if defined $c->request->params->{mode};
    $settings{data}{description} = $c->request->params->{description}
        if length $c->request->params->{description};

    unless(keys %messages) {
        if($c->model('Provisioning')->call_prov( $c, 'billing', 'create_ncos_level',
                                                 \%settings,
                                                 undef))
        {
            $messages{clvlmsg} = 'Web.NCOSLevel.Created';
            $c->session->{messages} = \%messages;
            $c->response->redirect("/ncos#create_level");
            return;
        }
    }

    $messages{clvlerr} = 'Client.Voip.InputErrorFound';
    $c->session->{messages} = \%messages;
    $c->session->{crefill} = \%settings;
    $c->response->redirect("/ncos#create_level");
    return;
}

=head2 do_update_level

Update settings of an NCOS level in the database.

=cut

sub do_update_level : Local {
    my ( $self, $c ) = @_;

    my %messages;
    my %settings;

    $settings{level} = $c->request->params->{level};
    unless(length $settings{level}) {
        $c->response->redirect("/ncos");
        return;
    }

    $settings{data}{mode} = $c->request->params->{mode}
        if defined $c->request->params->{mode};
    $settings{data}{description} = $c->request->params->{description};

    unless(keys %messages) {
        if($c->model('Provisioning')->call_prov( $c, 'billing', 'update_ncos_level',
                                                 \%settings,
                                                 undef))
        {
            $messages{elvlmsg} = 'Web.NCOSLevel.Updated';
            $c->session->{messages} = \%messages;
            $c->response->redirect("/ncos");
            return;
        }
        $c->response->redirect("/ncos?edit_level=$settings{level}");
        return;
    }

    $messages{elvlerr} = 'Client.Voip.InputErrorFound';
    $c->session->{messages} = \%messages;
    $c->response->redirect("/ncos?edit_level=$settings{level}");
    return;
}

=head2 do_delete_level

Delete an NCOS level from the database.

=cut

sub do_delete_level : Local {
    my ( $self, $c ) = @_;

    my %settings;

    $settings{level} = $c->request->params->{level};
    unless(length $settings{level}) {
        $c->response->redirect("/ncos");
        return;
    }

    if($c->model('Provisioning')->call_prov( $c, 'billing', 'delete_ncos_level',
                                             \%settings,
                                             undef))
    {
        $c->session->{messages} = { elvlmsg => 'Web.NCOSLevel.Deleted' };
        $c->response->redirect("/ncos");
        return;
    }

    $c->response->redirect("/ncos");
    return;
}

=head2 lists

Display and edit NCOS pattern and LNP lists.

=cut

sub lists : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/ncos_lists.tt';

    my $level = $c->request->params->{level};
    my $lvli;
    return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_ncos_level',
                                                        { level => $level },
                                                        \$lvli
                                                      );
    $c->stash->{level} = $lvli;
    $c->stash->{level}{level} = $level;

    my $patterns;
    return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_ncos_pattern_list',
                                                        { level => $level },
                                                        \$patterns
                                                      );
    $c->stash->{patterns} = $patterns if eval { @$patterns };

    my $lnpids;
    return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_ncos_lnp_list',
                                                        { level => $level },
                                                        \$lnpids
                                                      );
    $c->stash->{lnpids} = $lnpids if eval { @$lnpids };

    my $providers;
    return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_lnp_providers',
                                                        { level => $level },
                                                        \$providers
                                                      );
    foreach my $lnpid (eval { @$lnpids }) {
        for(eval { @$providers }) {
            if($$_{id} == $$lnpid{lnp_provider_id}) {
                $$lnpid{lnp_provider} = $$_{name};
            }
        }
    }

    # filter already used LNP providers
    @$providers = grep { my $tmp = $$_{id};
                         ! grep { $$_{lnp_provider_id} == $tmp }
                                eval { @$lnpids }
                       }
                       eval { @$providers };
    $c->stash->{providers} = $providers if @$providers;

    $c->stash->{edit_pattern} = $c->request->params->{edit_pattern};
    $c->stash->{edit_lnpid} = $c->request->params->{edit_lnpid};

    if(exists $c->session->{pcrefill}) {
        $c->stash->{pcrefill} = $c->session->{pcrefill};
        delete $c->session->{pcrefill};
    }
    if(exists $c->session->{perefill}) {
        $c->stash->{perefill} = $c->session->{perefill};
        delete $c->session->{perefill};
    } elsif($c->request->params->{edit_pattern}) {
        foreach my $pat (eval { @$patterns }) {
            if($$pat{pattern} eq $c->request->params->{edit_pattern}) {
                $c->stash->{perefill} = $pat;
                last;
            }
        }
    }

    if(exists $c->session->{lcrefill}) {
        $c->stash->{lcrefill} = $c->session->{lcrefill};
        delete $c->session->{lcrefill};
    }
    if(exists $c->session->{lerefill}) {
        $c->stash->{lerefill} = $c->session->{lerefill};
        delete $c->session->{lerefill};
    } elsif($c->request->params->{edit_lnpid}) {
        foreach my $lnpid (eval { @$lnpids }) {
            if($$lnpid{lnp_provider_id} == $c->request->params->{edit_lnpid}) {
                $c->stash->{lerefill} = $lnpid;
                last;
            }
        }
    }

    return 1;
}

=head2 do_create_pattern

Creates a new entry in the pattern list of an NCOS level.

=cut

sub do_create_pattern : Local {
    my ( $self, $c ) = @_;

    my %settings;
    $settings{level} = $c->request->params->{level};

    $settings{patterns}[0]{pattern} = $c->request->params->{pattern};
    $settings{patterns}[0]{description} = $c->request->params->{description};

    $settings{purge_existing} = 0;

    if($c->model('Provisioning')->call_prov( $c, 'billing', 'set_ncos_pattern_list',
                                             \%settings,
                                             undef))
    {
        $c->session->{messages} = { patmsg => 'Web.NCOSPattern.Created' };
        $c->response->redirect("/ncos/lists?level=$settings{level}");
        return;
    }

    $c->session->{messages}{paterr} = 'Client.Voip.InputErrorFound';
    $c->session->{pcrefill} = $settings{patterns}[0];
    $c->response->redirect("/ncos/lists?level=$settings{level}");
    return;
}

=head2 do_delete_pattern

Deletes an entry from the pattern list of an NCOS level.

=cut

sub do_delete_pattern : Local {
    my ( $self, $c ) = @_;

    my %settings;
    $settings{level} = $c->request->params->{level};
    my $pattern = $c->request->params->{pattern};

    my $patterns;
    unless($c->model('Provisioning')->call_prov( $c, 'billing', 'get_ncos_pattern_list',
                                                 \%settings,
                                                 \$patterns))
    {
        $c->response->redirect("/ncos/lists?level=$settings{level}");
        return;
    }
    @{$settings{patterns}} = grep { $$_{pattern} ne $pattern } @$patterns;
    $settings{purge_existing} = 1;

    if($c->model('Provisioning')->call_prov( $c, 'billing', 'set_ncos_pattern_list',
                                             \%settings,
                                             undef))
    {
        $c->session->{messages} = { patmsg => 'Web.NCOSPattern.Deleted' };
        $c->response->redirect("/ncos/lists?level=$settings{level}");
        return;
    }

    $c->response->redirect("/ncos/lists?level=$settings{level}");
    return;
}

=head2 do_update_pattern

Updates an entry from the pattern list of an NCOS level.

=cut

sub do_update_pattern : Local {
    my ( $self, $c ) = @_;

    my %settings;
    $settings{level} = $c->request->params->{level};
    my $oldpattern = $c->request->params->{oldpattern};
    my $newpattern = $c->request->params->{newpattern};
    my $description = $c->request->params->{description};

    my $patterns;
    unless($c->model('Provisioning')->call_prov( $c, 'billing', 'get_ncos_pattern_list',
                                                 \%settings,
                                                 \$patterns))
    {
        $c->response->redirect("/ncos/lists?level=$settings{level}");
        return;
    }
    @{$settings{patterns}} = grep { $$_{pattern} ne $oldpattern } @$patterns;
    $settings{purge_existing} = 1;
    push @{$settings{patterns}}, { pattern => $newpattern, description => $description };

    if($c->model('Provisioning')->call_prov( $c, 'billing', 'set_ncos_pattern_list',
                                             \%settings,
                                             undef))
    {
        $c->session->{messages} = { patmsg => 'Web.NCOSPattern.Updated' };
        $c->response->redirect("/ncos/lists?level=$settings{level}");
        return;
    }

    $c->session->{messages}{paterr} = 'Client.Voip.InputErrorFound';
    $c->session->{perefill} = $settings{patterns}[-1];
    $c->response->redirect("/ncos/lists?level=$settings{level}&amp;edit_pattern=$oldpattern");
    return;
}

=head2 save_local_ac

Set or unset "local_ac" for an ncos level.

=cut

sub save_local_ac : Local {
    my ( $self, $c ) = @_;

    my %messages;
    my %settings;

    $settings{level} = $c->request->params->{level};
    unless(length $settings{level}) {
        $c->response->redirect("/ncos");
        return;
    }

    $settings{data}{local_ac} = $c->request->params->{local_ac} ? 1 : 0;

    unless(keys %messages) {
        if($c->model('Provisioning')->call_prov( $c, 'billing', 'update_ncos_level',
                                                 \%settings,
                                                 undef))
        {
            $messages{lacmsg} = $settings{data}{local_ac} ? 'Web.NCOSLevel.LACSet' : 'Web.NCOSLevel.LACUnset';
            $c->session->{messages} = \%messages;
            $c->response->redirect("/ncos/lists?level=$settings{level}#pattern");
            return;
        }
        $c->response->redirect("/ncos/lists?level=$settings{level}");
        return;
    }

    $messages{lacerr} = 'Client.Voip.InputErrorFound';
    $c->session->{messages} = \%messages;
    $c->response->redirect("/ncos/lists?level=$settings{level}#pattern");
    return;
}

=head2 do_set_lnp_provider_id

Creates or updates an entry in the LNP provider list of an NCOS level.

=cut

sub do_set_lnp_provider_id : Local {
    my ( $self, $c ) = @_;

    my %settings;
    $settings{level} = $c->request->params->{level};

    $settings{lnp_provider_ids}[0]{lnp_provider_id} = $c->request->params->{lnp_provider_id};
    $settings{lnp_provider_ids}[0]{description} = $c->request->params->{description};

    $settings{purge_existing} = 0;

    if($c->model('Provisioning')->call_prov( $c, 'billing', 'set_ncos_lnp_list',
                                             \%settings,
                                             undef))
    {
        if($c->request->params->{new}) {
            $c->session->{messages}{lnpmsg} = 'Web.NCOSLNP.Created';
            $c->response->redirect("/ncos/lists?level=$settings{level}#LNP");
        } else {
            $c->session->{messages}{lnpmsg} = 'Web.NCOSLNP.Updated';
            $c->response->redirect("/ncos/lists?level=$settings{level}&amp;edit_lnpid=".
                                   $c->request->params->{lnp_provider_id} ."#LNP");
        }
        return;
    }

    $c->session->{messages}{lnperr} = 'Client.Voip.InputErrorFound';
    if($c->request->params->{new}) {
        $c->session->{lcrefill} = $settings{lnp_provider_ids}[0];
        $c->response->redirect("/ncos/lists?level=$settings{level}#LNP");
    } else {
        $c->session->{lerefill} = $settings{lnp_provider_ids}[0];
        $c->response->redirect("/ncos/lists?level=$settings{level}&amp;edit_lnpid=".
                               $c->request->params->{lnp_provider_id} ."#LNP");
    }
    return;
}

=head2 do_delete_lnp_provider_id

Deletes an entry from the LNP provider list of an NCOS level.

=cut

sub do_delete_lnp_provider_id : Local {
    my ( $self, $c ) = @_;

    my %settings;
    $settings{level} = $c->request->params->{level};
    my $lnpid = $c->request->params->{lnp_provider_id};

    my $lnpids;
    unless($c->model('Provisioning')->call_prov( $c, 'billing', 'get_ncos_lnp_list',
                                                 \%settings,
                                                 \$lnpids))
    {
        $c->response->redirect("/ncos/lists?level=$settings{level}#LNP");
        return;
    }
    @{$settings{lnp_provider_ids}} = grep { $$_{lnp_provider_id} != $lnpid } @$lnpids;
    $settings{purge_existing} = 1;

    if($c->model('Provisioning')->call_prov( $c, 'billing', 'set_ncos_lnp_list',
                                             \%settings,
                                             undef))
    {
        $c->session->{messages} = { lnpmsg => 'Web.NCOSLNP.Deleted' };
        $c->response->redirect("/ncos/lists?level=$settings{level}#LNP");
        return;
    }

    $c->response->redirect("/ncos/lists?level=$settings{level}#LNP");
    return;
}


=head1 BUGS AND LIMITATIONS

=over

=item none

=back

=head1 SEE ALSO

Provisioning model, Sipwise::Provisioning::Billing, Catalyst

=head1 AUTHORS

Daniel Tiefnig <dtiefnig@sipwise.com>

=head1 COPYRIGHT

The billing controller is Copyright (c) 2009 Sipwise GmbH, Austria. All
rights reserved.

=cut

# ende gelaende
1;
