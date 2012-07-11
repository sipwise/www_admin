package admin::Controller::domain;

use strict;
use warnings;
use base 'Catalyst::Controller';
use Data::Dumper;

use admin::Utils;

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
    $c->stash->{domains} = $domains if eval { @$domains };

    if(ref $c->session->{restore_domadd_input} eq 'HASH') {
        $c->stash->{arefill} = $c->session->{restore_domadd_input};
        delete $c->session->{restore_domadd_input};
    }

    return 1;
}

=head2 do_create_domain

Create a new domain.

=cut

sub do_create_domain : Local {
    my ( $self, $c ) = @_;

    my %messages;

    my $domain = $c->request->params->{domain};

    unless(keys %messages) {
        if($c->model('Provisioning')->call_prov( $c, 'billing', 'create_domain',
                                                 { domain => $domain },
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

=head2 preferences

Show preferences for a given domain.

=cut

sub preferences : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/domain_preferences.tt';

    my $domain = $c->request->params->{domain};
    $c->stash->{domain} = $domain;

    my $preferences;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_domain_preferences',
                                                        {
                                                          domain => $domain,
                                                        },
                                                        \$preferences
                                                      );

    my $db_prefs;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_preferences',
                                                        undef, \$db_prefs
                                                      );
    $db_prefs = [ grep { $$_{dom_pref} } @$db_prefs ] if eval { @$db_prefs };
    
    ### restore data entered by the user ###

    if(ref $c->session->{restore_preferences_input} eq 'HASH') {
        if(ref $preferences eq 'HASH') {
            $preferences = { %$preferences, %{$c->session->{restore_preferences_input}} };
        } else {
            $preferences = $c->session->{restore_preferences_input};
        }
        delete $c->session->{restore_preferences_input};
    }
    
    # need to find and provide avaiable options for enum types
    foreach my $pref (@$db_prefs) {
        if ($$pref{data_type} eq 'enum') {
            
            my $enum_options;
            return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_enum_options', 
                { preference_id => $$pref{id},
                  pref_type => 'dom',
                }, 
                \$enum_options );

            $$preferences{$$pref{preference}} = { 
                selected => $$preferences{$$pref{preference}},
                options => $enum_options,
            } if eval { @$enum_options };
        }
        elsif ($$pref{preference} eq 'sound_set') {
            my $sound_sets;
            return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_sound_sets_flat', 
                {},
                \$sound_sets );

            $$preferences{$$pref{preference}} = { 
                selected => $$preferences{$$pref{preference}},
                options => $sound_sets,
            } if eval { @$sound_sets };
        }

    }


    if(eval { @$db_prefs }) {
        $c->stash->{preferences_array} = admin::Utils::prepare_tt_prefs($c, $db_prefs, $preferences);
    }

    $c->stash->{edit_preferences} = $c->request->params->{edit_preferences};

    return 1;
}

=head2 update_preferences

Update domain preferences in the database.

=cut

sub update_preferences : Local {
    my ( $self, $c ) = @_;

    my $domain = $c->request->params->{domain};
    $c->stash->{domain} = $domain;

    my $preferences;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_domain_preferences',
                                                        {
                                                          domain => $domain,
                                                        },
                                                        \$preferences
                                                      );

    my $db_prefs;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_preferences',
                                                        undef, \$db_prefs
                                                      );
    $db_prefs = [ grep { $$_{dom_pref} } @$db_prefs ] if eval { @$db_prefs };

    return unless admin::Utils::prepare_db_prefs($c, $db_prefs, $preferences, $domain);

    ### save settings ###

    unless(eval {keys %{$c->session->{messages}} }) {
        if($c->model('Provisioning')->call_prov( $c, 'voip', 'set_domain_preferences',
                                                 { domain => $domain,
                                                   preferences => $preferences,
                                                 },
                                                 undef
                                               ))
        {
            $c->session->{messages}{prefmsg} = 'Server.Voip.SavedSettings';
            $c->response->redirect("/domain/preferences?domain=$domain");
            return;

        }
    } else {
        $c->session->{messages}{preferr} = 'Client.Voip.InputErrorFound';
    }

    $c->session->{restore_preferences_input} = $preferences;
    $c->response->redirect("/domain/preferences?domain=$domain&edit_preferences=1");
    return;
}

=head2 edit_list

Add, remove or activate/deactivate entries from a number list preference.

=cut

sub edit_list : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/domain_edit_list.tt';

    my $domain = $c->request->params->{domain};
    $c->stash->{domain} = $domain;

    my $preferences;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_domain_preferences',
                                                        { domain => $domain },
                                                        \$preferences
                                                      );

    my $list = $c->request->params->{list_name};

    if(defined $$preferences{$list}) {
        my $block_list = ref $$preferences{$list} ? $$preferences{$list} : [ $$preferences{$list} ];
        $c->stash->{list_data} = admin::Utils::prepare_tt_list($c, $block_list);
    }

    $c->stash->{list_name} = $list;

    my $list_mode = $list;
    $list_mode =~ s/list$/mode/;
    $c->stash->{list_mode} = $$preferences{$list_mode};
    $list_mode =~ s/mode$/clir/;
    $c->stash->{block_in_clir} = $$preferences{$list_mode};

    if(defined $c->session->{blockaddtxt}) {
        $c->stash->{blockaddtxt} = $c->session->{blockaddtxt};
        delete $c->session->{blockaddtxt};
    }

    return 1;
}

=head2 do_edit_list

Update a number list preference in the database.

=cut

sub do_edit_list : Local {
    my ( $self, $c ) = @_;

    my $domain = $c->request->params->{domain};
    $c->stash->{domain} = $domain;

    my $preferences;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_domain_preferences',
                                                        { domain => $domain },
                                                        \$preferences
                                                      );

    my $list = $c->request->params->{list_name};

    # input text field to add new entry to block list
    my $add = $c->request->params->{block_add};

    # delete link next to entries in block list
    my $del = $c->request->params->{block_del};

    # activate/deactivate link next to entries in block list
    my $act = $c->request->params->{block_act};

    admin::Utils::addelact_blocklist($c, $preferences, $list, $add, $del, $act);

    unless(eval {keys %{$c->session->{messages}} }) {
        $c->model('Provisioning')->call_prov( $c, 'voip', 'set_domain_preferences',
                                              { domain => $domain,
                                                preferences => {
                                                                 $list => $$preferences{$list},
                                                               },
                                              },
                                              undef
                                            );
    } else {
        $c->session->{messages}{numerr} = 'Client.Voip.InputErrorFound';
    }

    $c->response->redirect("/domain/edit_list?domain=$domain&list_name=$list");
}

=head2 edit_iplist

Add or remove entries from an IP list preference.

=cut

sub edit_iplist : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/domain_edit_iplist.tt';

    my $domain = $c->request->params->{domain};
    $c->stash->{domain} = $domain;

    my $preferences;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_domain_preferences',
                                                        { domain => $domain },
                                                        \$preferences
                                                      );

    my $list = $c->request->params->{list_name};
    $c->stash->{list_name} = $list;

    if(defined $$preferences{$list}) {
        my $iplist = ref $$preferences{$list} ? $$preferences{$list} : [ $$preferences{$list} ];

        my $bg = '';
        my $i = 1;
        foreach my $entry (sort @$iplist) {
            push @{$c->stash->{list_data}}, { ipnet      => $entry,
                                              background => $bg ? '' : 'tr_alt',
                                              id         => $i++,
                                            };
            $bg = !$bg;
        }
    }

    if(defined $c->session->{listaddtxt}) {
        $c->stash->{listaddtxt} = $c->session->{listaddtxt};
        delete $c->session->{listaddtxt};
    }

    return 1;
}

=head2 do_edit_iplist

Update an IP list preference in the database.

=cut

sub do_edit_iplist : Local {
    my ( $self, $c ) = @_;

    my $domain = $c->request->params->{domain};
    $c->stash->{domain} = $domain;

    my $preferences;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_domain_preferences',
                                                        { domain => $domain },
                                                        \$preferences
                                                      );

    my $list = $c->request->params->{list_name};

    # input text field to add new entry to IP list
    my $add = $c->request->params->{list_add};

    # delete link next to entries in IP list
    my $del = $c->request->params->{list_del};

    admin::Utils::addel_iplist($c, $preferences, $list, $add, $del);

    unless(eval {keys %{$c->session->{messages}} }) {
        $c->model('Provisioning')->call_prov( $c, 'voip', 'set_domain_preferences',
                                              { domain => $domain,
                                                preferences => {
                                                                 $list => $$preferences{$list},
                                                               },
                                              },
                                              undef
                                            );
    } else {
        $c->session->{messages}{numerr} = 'Client.Voip.InputErrorFound';
    }

    $c->response->redirect("/domain/edit_iplist?domain=$domain&list_name=$list");
}

=head1 BUGS AND LIMITATIONS

=over

=item currently none

=back

=head1 SEE ALSO

Provisioning model, Sipwise::Provisioning::Billing, Catalyst

=head1 AUTHORS

=over

=item Daniel Tiefnig <dtiefnig@sipwise.com>

=item Andreas Granig <agranig@sipwise.com>

=back

=head1 COPYRIGHT

The domain controller is Copyright (c) 2007-2010 Sipwise GmbH, Austria.
You should have received a copy of the licences terms together with the
software.

=cut

# ende gelaende
1;
