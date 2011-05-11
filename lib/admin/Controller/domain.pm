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

=head2 rewrite

Show rewrite rule details for a given domain.

=cut

sub rewrite : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/domain_rewrite.tt';

    my $domain = $c->request->params->{domain};

    my $domain_rw;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_domain_rewrites',
                                                        { domain => $domain },
                                                        \$domain_rw
                                                      );
    $c->stash->{domain} = $domain_rw;
    $c->stash->{editid} = $c->request->params->{editid};

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
    my $direction = $c->request->params->{direction};
    my $field = $c->request->params->{field};
    my $match_pattern = $c->request->params->{match_pattern};
    my $replace_pattern = $c->request->params->{replace_pattern};
    my $description = $c->request->params->{description};
    my $priority = $c->request->params->{priority};

    my $a = "";
    if($field eq 'caller') { $a = 'caller'.$a; }
    elsif($field eq 'callee') { $a = 'callee'.$a; }
    if($direction eq 'in') { $a = 'i'.$a; }
    elsif($direction eq 'out') { $a = 'o'.$a; }
    my $m = $a.'msg'; my $e = $a.'err'; my $d = $a.'detail';

    unless(keys %messages) {
        if($c->model('Provisioning')->call_prov( $c, 'voip', 'create_domain_rewrite',
                                                 { domain => $domain,
                                                   data   =>  {
                                                       direction => $direction,
                                                       field => $field,
                                                       match_pattern => $match_pattern,
                                                       replace_pattern => $replace_pattern,
                                                       description => $description,
                                                       priority => $priority,
                                                   },
                                                 },
                                                 undef
                                               ))
        {
            $messages{$m} = 'Server.Voip.SavedSettings';
            $c->session->{messages} = \%messages;
            $c->response->redirect("/domain/rewrite?domain=$domain#$a");
            return;
        }
        else
        {
            $messages{$e} = 'Client.Voip.InputErrorFound';
            if($c->session->{prov_error_object}) {
              $c->flash->{$d} = $c->session->{prov_error_object};
            }
        }
    } else {
    }

    $c->session->{messages} = \%messages;
    $c->response->redirect("/domain/rewrite?domain=$domain#$a");
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
    my $direction = $c->request->params->{direction};
    my $field = $c->request->params->{field};
    my $rewriteid = $c->request->params->{rewriteid};
    my $match_pattern = $c->request->params->{match_pattern};
    my $replace_pattern = $c->request->params->{replace_pattern};
    my $description = $c->request->params->{description};
    my $priority = $c->request->params->{priority};
    
    my $a = "";
    if($field eq 'caller') { $a = 'caller'.$a; }
    elsif($field eq 'callee') { $a = 'callee'.$a; }
    if($direction eq 'in') { $a = 'i'.$a; }
    elsif($direction eq 'out') { $a = 'o'.$a; }
    my $m = $a.'msg'; my $e = $a.'err'; my $d = $a.'detail';

    unless(keys %messages) {
        if($c->model('Provisioning')->call_prov( $c, 'voip', 'update_domain_rewrite',
                                                 { id   => $rewriteid,
                                                   data => {
                                                       match_pattern => $match_pattern,
                                                       replace_pattern => $replace_pattern,
                                                       description => $description,
                                                       direction => $direction,
                                                       field => $field,
                                                       priority => $priority,
                                                   },
                                                 },
                                                 undef
                                               ))
        {
            $messages{$m} = 'Server.Voip.SavedSettings';
            $c->session->{messages} = \%messages;
            $c->response->redirect("/domain/rewrite?domain=$domain#$a");
            return;
        }
        else
        {
            $messages{$e} = 'Client.Voip.InputErrorFound';
            if($c->session->{prov_error_object}) {
              $c->flash->{$d} = $c->session->{prov_error_object};
            }
        }
    } else {
    }

    $c->session->{messages} = \%messages;
    $c->response->redirect("/domain/rewrite?domain=$domain#$a");
    return;
}

=head2 update_rewrite_priority

Updates the priority of rewrite rules upon re-order

=cut

sub update_rewrite_priority : Local {
    my ( $self, $c ) = @_;

    my %messages;
    my %settings;
    
    my $prio = 999;

    my $rules = $c->request->params->{'rule[]'};

    foreach my $rule_id(@$rules)
    {
       my $rule = undef;
       $c->model('Provisioning')->call_prov( $c, 'voip', 'get_domain_rewrite',
           { id => $rule_id },
           \$rule
       );
       $c->model('Provisioning')->call_prov( $c, 'voip', 'update_domain_rewrite',
           { id   => $rule_id,
             data => {
               match_pattern => $rule->{match_pattern},
               replace_pattern => $rule->{replace_pattern},
               description => $rule->{description},
               direction => $rule->{direction},
               field => $rule->{field},
               priority => $prio,
             },
           },
           undef
        );
        $prio-- if($prio > 1);
    }

    $c->session->{messages} = \%messages;
    $c->response->redirect("/domain");
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
    my $direction = $c->request->params->{direction};
    my $field = $c->request->params->{field};
    
    my $a = "";
    if($field eq 'caller') { $a = 'caller'.$a; }
    elsif($field eq 'callee') { $a = 'callee'.$a; }
    if($direction eq 'in') { $a = 'i'.$a; }
    elsif($direction eq 'out') { $a = 'o'.$a; }
    my $m = $a.'msg'; my $e = $a.'err';

    unless(keys %messages) {
        if($c->model('Provisioning')->call_prov( $c, 'voip', 'delete_domain_rewrite',
                                                 { id => $rewriteid
                                                 },
                                                 undef
                                               ))
        {
            $messages{$m} = 'Server.Voip.SavedSettings';
            $c->session->{messages} = \%messages;
            $c->response->redirect("/domain/rewrite?domain=$domain#$a");
            return;
        }
    } else {
    }

    $c->session->{messages} = \%messages;
    $c->response->redirect("/domain/rewrite?domain=$domain#$a");
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

=head2 audio

Show audio file details for a given domain.

=cut

sub audio : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/domain_audio.tt';

    my $domain = $c->request->params->{domain};

    $c->stash->{domain} = $domain;

    my $audio_files;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_audio_files',
                                                        { domain => $domain },
                                                        \$audio_files
                                                      );
    $c->stash->{audio_files} = $audio_files if eval { @$audio_files };

    $c->stash->{edit_audio} = $c->request->params->{edit_audio};
    $c->stash->{delete_audio} = $c->request->params->{daf};

    if(exists $c->session->{acrefill}) {
        $c->stash->{acrefill} = $c->session->{acrefill};
        delete $c->session->{acrefill};
    }
    if(exists $c->session->{aerefill}) {
        $c->stash->{aerefill} = $c->session->{aerefill};
        delete $c->session->{aerefill};
    } elsif($c->request->params->{edit_audio}) {
        foreach my $audio (eval { @$audio_files }) {
            if($$audio{handle} eq $c->request->params->{edit_audio}) {
                $c->stash->{aerefill} = $audio;
                last;
            }
        }
    }

    return 1;
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
            $c->response->redirect("/domain/audio?domain=$settings{domain}");
            return;
        }
    }

    $messages{audioerr} = 'Client.Voip.InputErrorFound';
    $c->session->{messages} = \%messages;
    $c->session->{acrefill} = \%settings;
    $c->response->redirect("/domain/audio?domain=$settings{domain}");
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
        $c->response->redirect("/domain/audio?domain=$settings{domain}");
        return;
    }
    $settings{data}{description} = $c->request->params->{description};
    my $upload = $c->req->upload('eupload_audio');
    $settings{data}{audio} = eval { $upload->slurp } if defined $upload;

    if($c->model('Provisioning')->call_prov( $c, 'voip', 'update_audio_file',
                                             \%settings,
                                             undef))
    {
        $messages{audiomsg} = 'Web.AudioFile.Updated';
        $c->session->{messages} = \%messages;
        $c->response->redirect("/domain/audio?domain=$settings{domain}");
        return;
    }

    $messages{audioerr} = 'Client.Voip.InputErrorFound';
    $c->session->{messages} = \%messages;
    $c->session->{aerefill} = $settings{data};
    $c->response->redirect("/domain/audio?domain=$settings{domain}&amp;edit_audio=$settings{handle}");
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
        $c->response->redirect("/domain/audio?domain=$settings{domain}");
        return;
    }

    if($c->model('Provisioning')->call_prov( $c, 'voip', 'delete_audio_file',
                                             \%settings,
                                             undef))
    {
        $c->session->{messages} = { audiomsg => 'Web.AudioFile.Deleted' };
        $c->response->redirect("/domain/audio?domain=$settings{domain}");
        return;
    }

    $c->response->redirect("/domain/audio?domain=$settings{domain}&amp;daf=$settings{handle}");
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
        $c->response->redirect("/domain/audio?domain=$settings{domain}");
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

    $c->response->redirect("/domain/audio?domain=$settings{domain}");
    return;
}

=head2 vsc

Show VSC details for a given domain.

=cut

sub vsc : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/domain_vsc.tt';

    my $domain = $c->request->params->{domain};

    $c->stash->{domain} = $domain;

    my $audio_files;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_audio_files',
                                                        { domain => $domain },
                                                        \$audio_files
                                                      );
    $c->stash->{audio_files} = $audio_files if eval { @$audio_files };

    my $vscs;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_domain_vscs',
                                                        { domain => $domain },
                                                        \$vscs
                                                      );
    $c->stash->{vscs} = $vscs if eval { @$vscs };

    my $vsc_actions;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_vsc_actions',
                                                        { },
                                                        \$vsc_actions
                                                      );
    @$vsc_actions = grep { my $tmp = $_;
                                      ! grep { $$_{action} eq $tmp }
                                             eval { @$vscs }
                                    }
                                    eval { @$vsc_actions };
    $c->stash->{vsc_actions} = $vsc_actions if @$vsc_actions;

    $c->stash->{edit_vsc} = $c->request->params->{edit_vsc};

    if(exists $c->session->{vcrefill}) {
        $c->stash->{vcrefill} = $c->session->{vcrefill};
        delete $c->session->{vcrefill};
    }
    if(exists $c->session->{verefill}) {
        $c->stash->{verefill} = $c->session->{verefill};
        delete $c->session->{verefill};
    } elsif($c->request->params->{edit_vsc}) {
        foreach my $vsc (eval { @$vscs }) {
            if($$vsc{action} eq $c->request->params->{edit_vsc}) {
                $c->stash->{verefill} = $vsc;
                last;
            }
        }
    }

    return 1;
}

=head2 do_create_vsc

Store a new VSC entry in the database.

=cut

sub do_create_vsc : Local {
    my ( $self, $c ) = @_;

    my %messages;
    my %settings;

    $settings{domain} = $c->request->params->{domain};
    unless(length $settings{domain}) {
        $c->response->redirect("/domain");
        return;
    }
    $settings{action} = $c->request->params->{action};
    $settings{data}{digits} = $c->request->params->{digits}
        if length $c->request->params->{digits};
    $settings{data}{audio_file_handle} = $c->request->params->{audio_file_handle};
    $settings{data}{description} = $c->request->params->{description}
        if length $c->request->params->{description};

    if($c->model('Provisioning')->call_prov( $c, 'voip', 'create_domain_vsc',
                                             \%settings,
                                             undef))
    {
        $messages{vscmsg} = 'Web.VSC.Created';
        $c->session->{messages} = \%messages;
        $c->response->redirect("/domain/vsc?domain=$settings{domain}");
        return;
    }

    $messages{vscerr} = 'Client.Voip.InputErrorFound';
    $c->session->{messages} = \%messages;
    $c->session->{vcrefill} = \%settings;
    $c->response->redirect("/domain/vsc?domain=$settings{domain}");
    return;
}

=head2 do_update_vsc

Update a VSC entry in the database.

=cut

sub do_update_vsc : Local {
    my ( $self, $c ) = @_;

    my %messages;
    my %settings;

    $settings{domain} = $c->request->params->{domain};
    unless(length $settings{domain}) {
        $c->response->redirect("/domain");
        return;
    }
    $settings{action} = $c->request->params->{action};
    unless(length $settings{action}) {
        $c->response->redirect("/domain/vsc?domain=$settings{domain}");
        return;
    }
    $settings{data}{digits} = length $c->request->params->{digits}
                                     ? $c->request->params->{digits}
                                     : undef;
    $settings{data}{audio_file_handle} = $c->request->params->{audio_file_handle}
        if defined $c->request->params->{audio_file_handle};
    $settings{data}{description} = $c->request->params->{description};

    if($c->model('Provisioning')->call_prov( $c, 'voip', 'update_domain_vsc',
                                             \%settings,
                                             undef))
    {
        $messages{vscmsg} = 'Web.VSC.Updated';
        $c->session->{messages} = \%messages;
        $c->response->redirect("/domain/vsc?domain=$settings{domain}");
        return;
    }

    $messages{vscerr} = 'Client.Voip.InputErrorFound';
    $c->session->{messages} = \%messages;
    $c->session->{verefill} = $settings{data};
    $c->response->redirect("/domain/vsc?domain=$settings{domain}&amp;edit_vsc=$settings{action}");
    return;
}

=head2 do_delete_vsc

Delete a VSC entry from the database.

=cut

sub do_delete_vsc : Local {
    my ( $self, $c ) = @_;

    my %settings;

    $settings{domain} = $c->request->params->{domain};
    unless(length $settings{domain}) {
        $c->response->redirect("/domain");
        return;
    }
    $settings{action} = $c->request->params->{action};
    unless(length $settings{action}) {
        $c->response->redirect("/domain/vsc?domain=$settings{domain}");
        return;
    }

    if($c->model('Provisioning')->call_prov( $c, 'voip', 'delete_domain_vsc',
                                             \%settings,
                                             undef))
    {
        $c->session->{messages} = { vscmsg => 'Web.VSC.Deleted' };
        $c->response->redirect("/domain/vsc?domain=$settings{domain}");
        return;
    }

    $c->response->redirect("/domain/vsc?domain=$settings{domain}");
    return;
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
