package admin::Controller::peering;

use strict;
use warnings;
use base 'Catalyst::Controller';
use Data::Dumper;
use admin::Utils;

=head1 NAME

admin::Controller::peering - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=head2 index 

Configure SIP peerings

=cut

sub index : Private {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/peering.tt';

    my $peer_groups;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_peer_groups',
                                                        undef,
                                                        \$peer_groups
                                                      );
    $c->stash->{peer_groups} = $peer_groups if eval { @$peer_groups };	
    $c->stash->{editid} = $c->request->params->{editid};
    
    my $peering_contracts;
    my $contracts;
    return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_sip_peering_contracts',
                                                        1,
                                                        \$peering_contracts
                                                      );
    if (eval { @$peering_contracts }) {
	$contracts = [];
        #foreach my $sdentry (sort {$a->{id} <=> $b->{id}} @$peering_contracts) {
	foreach my $peering_contract (@$peering_contracts) {
	    my %contract; # = {};
	    $contract{id} = $peering_contract->{id};
	    if(defined $peering_contract->{billing_profile} and length $peering_contract->{billing_profile}) {
	        my $profile;
	        return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_billing_profile',
                                                                    { handle => $peering_contract->{billing_profile} },
                                                                    \$profile
                                                                  );
                $contract{billing_profile_name} = $$profile{data}{name};
	    } else {
		$contract{billing_profile_name} = '';
	    }
	    $contract{short_contact} = admin::Utils::short_contact($c,$peering_contract->{contact});
	    #$contract{status} = $peering_contract->{status};
	    $contract{create_timestamp} = $peering_contract->{create_timestamp};
	    push @$contracts,\%contract;
	}
	$c->stash->{contracts} = $contracts;
    }

    if(exists $c->session->{garefill}) {
        $c->stash->{garefill} = $c->session->{garefill};
        delete $c->session->{garefill};
    }

    return 1;
}

=head2 do_delete_grp

Delete a peering group

=cut

sub delete_grp : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/peering.tt';

    my %messages;
    my %settings;

    my $grpid = $c->request->params->{grpid};
    
    if($c->model('Provisioning')->call_prov( $c, 'voip', 'delete_peer_group',
                                              { id => $grpid
                                              },
                                              undef
                                            ))
    {
        $messages{epeermsg} = 'Server.Voip.PeerGroupDeleted';
        $c->session->{messages} = \%messages;
        $c->response->redirect("/peering");
        return;
	}
    $c->response->redirect("/peering");
    return;
}



=head2 create_grp

Create a peering group

=cut

sub create_grp : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/peering.tt';

    my %messages;
    my %settings;

    $settings{name} = $c->request->params->{grpname};
    $messages{cpeererr} = 'Client.Syntax.MalformedPeerGroupName'
        unless $settings{name} =~ /^[a-zA-Z0-9_\-]+/;
    $settings{priority} = $c->request->params->{priority};
    $settings{description} = $c->request->params->{grpdesc};
    $settings{peering_contract_id} = $c->request->params->{peering_contract_id}
        if $c->request->params->{peering_contract_id};
    $messages{cpeererr} = 'Client.Voip.NoPeerContract'
        unless (defined $settings{peering_contract_id} && $settings{peering_contract_id} =~ /^[0-9]+/);

    unless(keys %messages) {
        if($c->model('Provisioning')->call_prov( $c, 'voip', 'create_peer_group',
                                                 { %settings },
                                                 undef
                                               ))
        {
            $messages{cpeermsg} = 'Server.Voip.SavedSettings';
            $c->session->{messages} = \%messages;
            $c->response->redirect("/peering");
            return;
        }
    } else {
        $messages{cpeererr} = 'Client.Voip.InputErrorFound';
    }

    $c->session->{garefill} = \%settings;
    $c->session->{messages} = \%messages;
    $c->response->redirect("/peering#create_group");
    return;
}

=head2 edit_grp

Edit a peering group

=cut

sub edit_grp : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/peering.tt';

    my %messages;
    my %settings;

    my $grpid = $c->request->params->{grpid};
    $settings{priority} = $c->request->params->{priority};
    $settings{description} = $c->request->params->{grpdesc};
    $settings{peering_contract_id} = $c->request->params->{peering_contract_id} || undef;

#$c->log->debug('*** edit grp');

    unless(keys %messages) {
        if($c->model('Provisioning')->call_prov( $c, 'voip', 'update_peer_group',
                                                 { id   => $grpid,
                                                   data => \%settings,
                                                 },
                                                 undef
                                               ))
        {
            $messages{epeermsg} = 'Server.Voip.SavedSettings';
        }
    }
    $c->session->{messages} = \%messages;
    $c->response->redirect("/peering#groups");
    return;
}

sub detail : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/peering_detail.tt';
    
	my $grpid = $c->request->params->{group_id};

    my $peer_details;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_peer_group_details',
														{ id => $grpid },
                                                        \$peer_details
                                                      );
    $c->stash->{grp} = $peer_details;
	$c->stash->{reditid} = $c->request->params->{reditid};
	$c->stash->{peditid} = $c->request->params->{peditid};

    return 1;
}

=head2 create_rule

Create a peering rule for a given group

=cut

sub save_rule : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/peering_detail.tt';

    my %messages;
    my $checkresult;

    my $settings = {
        callee_prefix  => $c->request->params->{callee_prefix} //= undef,
        callee_pattern => $c->request->params->{callee_pattern} //= undef,
        caller_pattern => $c->request->params->{caller_pattern} //= undef,
        description    => $c->request->params->{description} //= undef,
    };
    my $rule_id  = $c->request->params->{ruleid} //= undef;
    my $group_id = $c->request->params->{grpid} //= undef;

    $settings->{callee_prefix} =~ s/^\s+|\s+$//g;
    $settings->{callee_pattern} =~ s/^\s+|\s+$//g;
    $settings->{caller_pattern} =~ s/^\s+|\s+$//g;

    unless ($c->model('Provisioning')->call_prov( $c, 'voip', 'check_sip_uri_prefix', $settings->{callee_prefix}, \$checkresult)) {
        $messages{rule_callee_prefix_err} = 'Client.Syntax.MalformedUri';
        $c->flash->{rule_callee_prefix_err_detail} = $c->session->{prov_error_object} if ($c->session->{prov_error_object});
    }
    unless ($c->model('Provisioning')->call_prov( $c, 'voip', 'check_sip_uri_pattern', $settings->{callee_pattern}, \$checkresult)) {
        $messages{rule_callee_pattern_err} = 'Client.Syntax.MalformedUri';
        $c->flash->{rule_callee_pattern_err_detail} = $c->session->{prov_error_object} if ($c->session->{prov_error_object});
    }
    unless ($c->model('Provisioning')->call_prov( $c, 'voip', 'check_sip_uri_pattern', $settings->{caller_pattern}, \$checkresult)) {
        $messages{rule_caller_pattern_err} = 'Client.Syntax.MalformedUri';
        $c->flash->{rule_caller_pattern_err_detail} = $c->session->{prov_error_object} if ($c->session->{prov_error_object});
    }

    if (keys %messages) {
        $c->session->{messages} = \%messages;
        $c->flash->{restore_rule} = $settings;
    
        if (defined $rule_id and length ($rule_id)) {
            $c->response->redirect("/peering/detail?group_id=$group_id&reditid=$rule_id");
        }
        else {
            $c->response->redirect("/peering/detail?group_id=$group_id");
        }
        $c->detach;
    }

    # data ok, save it
    my $result;

    if (defined $rule_id and length ($rule_id)) {
        $result = $c->model('Provisioning')->call_prov( $c, 'voip', 'update_peer_rule',
            { id   => $rule_id,
              data => $settings,
            },
            undef,
        );
    }
    else {
        $result = $c->model('Provisioning')->call_prov( $c, 'voip', 'create_peer_rule',
            { group_id => $group_id,
              data     => $settings,
            },
            undef,
        );
    }

    if ($result) {
        $messages{erulmsg} = 'Server.Voip.SavedSettings';
        $c->session->{messages} = \%messages;
        $c->response->redirect("/peering/detail?group_id=$group_id");
        return;
	}
	else {
    	$messages{erulerr} = 'Client.Voip.InputErrorFound';
	}
}

=head2 delete_rule

Delete a peering rule

=cut

sub delete_rule : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/peering_detail.tt';

    my %messages;
    my %settings;

    my $grpid = $c->request->params->{grpid};
    my $rule_id = $c->request->params->{ruleid};

    unless(keys %messages) {
        if($c->model('Provisioning')->call_prov( $c, 'voip', 'delete_peer_rule',
                                                 { id => $rule_id
                                                 },
                                                 undef
                                               ))
        {
            $messages{erulmsg} = 'Server.Voip.SavedSettings';
            $c->session->{messages} = \%messages;
            $c->response->redirect("/peering/detail?group_id=$grpid");
            return;
		}
    } else {
    }

    $c->session->{messages} = \%messages;
    $c->response->redirect("/peering/detail?group_id=$grpid");
    return;
}

=head2 create_peer

Create a peering server for a given group

=cut

sub create_peer : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/peering_detail.tt';

    my %messages;
    my %settings;

    my $grpid = $c->request->params->{grpid};
    my $name = $c->request->params->{name};
    my $ip = $c->request->params->{ip};
    my $host = length($c->request->params->{host}) ? $c->request->params->{host} : undef;
    my $port = $c->request->params->{port};
    my $transport = $c->request->params->{transport};
    my $weight = $c->request->params->{weight};

#TODO: add syntax checks here

#    $messages{serverr} = 'Client.Syntax.MalformedPeerGroupName'
#        unless $callee_prefix =~ /^[a-zA-Z0-9_\.\-\@\:]+/;


    unless(keys %messages) {
        if($c->model('Provisioning')->call_prov( $c, 'voip', 'create_peer_host',
                                                 { group_id => $grpid,
                                                   data => {
                                                       name => $name,
                                                       ip => $ip,
                                                       host => $host,
                                                       port => $port,
                                                       transport => $transport,
                                                       weight => $weight,
                                                   },
                                                 },
                                                 undef
                                               ))
        {
            $messages{servmsg} = 'Server.Voip.SavedSettings';
            $c->session->{messages} = \%messages;
            $c->response->redirect("/peering/detail?group_id=$grpid");
            return;
		}
		else
		{
        	$messages{serverr} = 'Client.Voip.InputErrorFound';
		}
    } else {
		# TODO: add proper values here and set them in tt
		my %arefill = ();
#		$arefill{name} = $grpname;
#		$arefill{desc} = $grpdesc;

		$c->stash->{arefill} = \%arefill;
    }

    $c->session->{messages} = \%messages;
    $c->response->redirect("/peering/detail?group_id=$grpid");
    return;
}

=head2 delete_peer

Delete a peering host

=cut

sub delete_peer : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/peering_detail.tt';

    my %messages;
    my %settings;

    my $grpid = $c->request->params->{grpid};
    my $peerid = $c->request->params->{peerid};

    unless(keys %messages) {
        if($c->model('Provisioning')->call_prov( $c, 'voip', 'delete_peer_host',
                                                 { id => $peerid
                                                 },
                                                 undef
                                               ))
        {
            $messages{servmsg} = 'Server.Voip.SavedSettings';
            $c->session->{messages} = \%messages;
            $c->response->redirect("/peering/detail?group_id=$grpid");
            return;
		}
    } else {
    }

    $c->session->{messages} = \%messages;
    $c->response->redirect("/peering/detail?group_id=$grpid");
    return;
}

=head2 edit_peer

Edit a peering host

=cut

sub edit_peer : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/peering_detail.tt';

    my %messages;
    my %settings;

    my $grpid = $c->request->params->{grpid};
    my $peerid = $c->request->params->{peerid};
    my $name = $c->request->params->{name};
    my $ip = $c->request->params->{ip};
    my $host = length($c->request->params->{host}) ? $c->request->params->{host} : undef;
    my $port = $c->request->params->{port};
    my $transport = $c->request->params->{transport};
    my $weight = $c->request->params->{weight};

#    $messages{crulerr} = 'Client.Syntax.MalformedPeerGroupName'
#        unless $callee_prefix =~ /^[a-zA-Z0-9_\.\-\@\:]+/;

    unless(keys %messages) {
        if($c->model('Provisioning')->call_prov( $c, 'voip', 'update_peer_host',
                                                 { id => $peerid,
                                                   data => {
                                                       name => $name,
                                                       ip => $ip,
                                                       host => $host,
                                                       port => $port,
                                                       transport => $transport,
                                                       weight => $weight,
                                                   },
                                                 },
                                                 undef
                                               ))
        {
            $messages{servmsg} = 'Server.Voip.SavedSettings';
            $c->session->{messages} = \%messages;
            $c->response->redirect("/peering/detail?group_id=$grpid");
            return;
		}
		else
		{
        	$messages{serverr} = 'Client.Voip.InputErrorFound';
		}
    } else {
		# TODO: add proper values here and set them in tt
		my %arefill = ();
#		$arefill{name} = $grpname;
#		$arefill{desc} = $grpdesc;

		$c->stash->{arefill} = \%arefill;
    }

    $c->session->{messages} = \%messages;
    $c->response->redirect("/peering/detail?group_id=$grpid");
    return;
}

=head2 preferences

Show preferences for a given peer host.

=cut

sub preferences : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/peering_preferences.tt';

    my $peerid = $c->request->params->{peerid};

    my $peer_details;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_peer_host_details',
                                                        { id => $peerid },
                                                        \$peer_details
                                                      );
    $c->stash->{peer} = $peer_details;

    my $preferences;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_peer_preferences',
                                                        { id => $peerid },
                                                        \$preferences
                                                      );

    my $db_prefs;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_preferences',
                                                        undef, \$db_prefs
                                                      );
    $db_prefs = [ grep { $$_{peer_pref} } @$db_prefs ] if eval { @$db_prefs };
    
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
                  pref_type => 'peer',
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

Update peer host preferences in the database.

=cut

sub update_preferences : Local {
    my ( $self, $c ) = @_;

    my $peerid = $c->request->params->{peerid};

    my $preferences;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_peer_preferences',
                                                        { id => $peerid },
                                                        \$preferences
                                                      );

    my $db_prefs;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_preferences',
                                                        undef, \$db_prefs
                                                      );
    $db_prefs = [ grep { $$_{peer_pref} } @$db_prefs ] if eval { @$db_prefs };

    return unless admin::Utils::prepare_db_prefs($c, $db_prefs, $preferences);

    ### save settings ###

    unless(eval {keys %{$c->session->{messages}} }) {
        if($c->model('Provisioning')->call_prov( $c, 'voip', 'set_peer_preferences',
                                                 { id => $peerid,
                                                   preferences => $preferences,
                                                 },
                                                 undef
                                               ))
        {
            $c->session->{messages}{prefmsg} = 'Server.Voip.SavedSettings';
            $c->response->redirect("preferences?peerid=$peerid");
            return;

        }
    } else {
        $c->session->{messages}{preferr} = 'Client.Voip.InputErrorFound';
    }

    $c->session->{restore_preferences_input} = $preferences;
    $c->response->redirect("preferences?peerid=$peerid&edit_preferences=1");
    return;
}

=head2 edit_list

Add, remove or activate/deactivate entries from a number list preference.

=cut

sub edit_list : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/peering_edit_list.tt';

    my $peerid = $c->request->params->{peerid};

    my $peer_details;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_peer_host_details',
                                                        { id => $peerid },
                                                        \$peer_details
                                                      );
    $c->stash->{peer} = $peer_details;

    my $preferences;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_peer_preferences',
                                                        { id => $peerid },
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

    my $peerid = $c->request->params->{peerid};

    my $preferences;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_peer_preferences',
                                                        { id => $peerid },
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
        $c->model('Provisioning')->call_prov( $c, 'voip', 'set_peer_preferences',
                                              { id => $peerid,
                                                preferences => {
                                                                 $list => $$preferences{$list},
                                                               },
                                              },
                                              undef
                                            );
    } else {
        $c->session->{messages}{numerr} = 'Client.Voip.InputErrorFound';
    }

    $c->response->redirect("edit_list?peerid=$peerid&list_name=$list");
}

=head2 edit_iplist

Add or remove entries from an IP list preference.

=cut

sub edit_iplist : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/peering_edit_iplist.tt';

    my $peerid = $c->request->params->{peerid};

    my $peer_details;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_peer_host_details',
                                                        { id => $peerid },
                                                        \$peer_details
                                                      );
    $c->stash->{peer} = $peer_details;

    my $preferences;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_peer_preferences',
                                                        { id => $peerid },
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

    my $peerid = $c->request->params->{peerid};

    my $preferences;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_peer_preferences',
                                                        { id => $peerid },
                                                        \$preferences
                                                      );

    my $list = $c->request->params->{list_name};

    # input text field to add new entry to IP list
    my $add = $c->request->params->{list_add};

    # delete link next to entries in IP list
    my $del = $c->request->params->{list_del};

    admin::Utils::addel_iplist($c, $preferences, $list, $add, $del);

    unless(eval {keys %{$c->session->{messages}} }) {
        $c->model('Provisioning')->call_prov( $c, 'voip', 'set_peer_preferences',
                                              { id => $peerid,
                                                preferences => {
                                                                 $list => $$preferences{$list},
                                                               },
                                              },
                                              undef
                                            );
    } else {
        $c->session->{messages}{numerr} = 'Client.Voip.InputErrorFound';
    }

    $c->response->redirect("edit_iplist?peerid=$peerid&list_name=$list");
}

=head2 detail 

Show SIP peering contract details.

=cut

sub contract_detail : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/peering_contract_detail.tt';

    my $contract;
    my $contract_id = $c->request->params->{contract_id} || undef;
    if(defined $contract_id) {
        return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_sip_peering_contract_by_id',
                                                            { id => $contract_id },
                                                            \$contract
                                                          );
    }
    if(ref $c->session->{restore_contract_input} eq 'HASH') {
        if($c->config->{billing_features}) {
            $contract->{billing_profile} = $c->session->{restore_contract_input}{billing_profile};
	}
        $contract->{contact} = $c->session->{restore_contract_input}{contact};
        delete $c->session->{restore_contract_input};
    }

    # we only use this to fill the drop-down lists
    if($c->request->params->{edit_contract}) {
        my $billing_profiles;
        return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_billing_profiles',
                                                            undef,
                                                            \$billing_profiles
                                                          );

        $c->stash->{billing_profiles} = [ sort { $$a{data}{name} cmp $$b{data}{name} }
                                            @$billing_profiles ];
    } else {
        if(defined $contract->{billing_profile}) {
            my $profile;
            return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_billing_profile',
                                                                { handle => $contract->{billing_profile} },
                                                                \$profile
                                                              );
            $contract->{billing_profile_name} = $$profile{data}{name};
        }
    }

    $c->stash->{contract} = $contract;
    $c->stash->{contact_form_fields} = admin::Utils::get_contract_contact_form_fields($c,$contract->{contact});
    if($c->config->{billing_features}) {
        $c->stash->{billing_features} = 1;
    }
    $c->stash->{edit_contract} = $c->request->params->{edit_contract};

    return 1;
}

=head2 save_contract 

Create or update details of a SIP peering contract.

=cut

sub save_contract : Local {
    my ( $self, $c ) = @_;

    my %messages;
    my %settings;

    my $contract_id = $c->request->params->{contract_id} || undef;

    my $billing_profile = $c->request->params->{billing_profile};
    $settings{billing_profile} = $billing_profile if defined $billing_profile;
    
    my %contact;
    my $contract_contact_form_fields = admin::Utils::get_contract_contact_form_fields($c,undef);
    if (ref $contract_contact_form_fields eq 'ARRAY') {
      foreach my $form_field (@$contract_contact_form_fields) {
	if (defined $c->request->params->{$form_field->{field}} and length($c->request->params->{$form_field->{field}})) {
	  $contact{$form_field->{field}} = $c->request->params->{$form_field->{field}};
	} else {
          $contact{$form_field->{field}} = undef;
        }
      }
    }
    $settings{contact} = \%contact;

    if(keys %settings or (!$c->config->{billing_features} and !defined $contract_id)) {
        if(defined $contract_id) {
            if($c->model('Provisioning')->call_prov( $c, 'billing', 'update_sip_peering_contract',
                                                     { id   => $contract_id,
                                                       data => \%settings,
                                                     },
                                                     undef))
            {
                $messages{topmsg} = 'Web.Contract.Updated';
                $c->session->{messages} = \%messages;
                $c->response->redirect("/peering");
                return;
            }
        } else {
            if($c->model('Provisioning')->call_prov( $c, 'billing', 'create_sip_peering_contract',
                                                     { data => \%settings },
                                                     \$contract_id))
            {
                $messages{topmsg} = 'Web.Contract.Created';
                $c->session->{messages} = \%messages;
                $c->response->redirect("/peering");
                return;
            }
        }
    }

    $c->session->{messages} = \%messages;
    $c->session->{restore_contract_input} = \%settings;
    $c->response->redirect("/peering/contract_detail?edit_contract=1&amb;contract_id=$contract_id");
    return;
}

=head2 terminate

Terminates a SIP peering contract.

=cut

sub terminate_contract : Local {
    my ( $self, $c ) = @_;

    my %messages;

    my $contract_id = $c->request->params->{contract_id};

    if($c->model('Provisioning')->call_prov( $c, 'billing', 'terminate_sip_peering_contract',
                                             { id => $contract_id },
                                             undef))
    {
        $messages{topmsg} = 'Web.Contract.Deleted';
        $c->session->{messages} = \%messages;
        $c->response->redirect("/peering");
        return;
    }

    $c->session->{messages} = \%messages;
    $c->response->redirect("/peering/contract_detail?edit_contract=1&amb;contract_id=$contract_id");
    return;
}

=head2 delete

Deletes a SIP peering contract.

=cut

sub delete_contract : Local {
    my ( $self, $c ) = @_;

    my %messages;

    my $contract_id = $c->request->params->{contract_id};

    if($c->model('Provisioning')->call_prov( $c, 'billing', 'delete_sip_peering_contract',
                                             { id => $contract_id },
                                             undef))
    {
        $messages{topmsg} = 'Web.Contract.Deleted';
        $c->session->{messages} = \%messages;
        $c->response->redirect("/peering");
        return;
    }

    $c->session->{messages} = \%messages;
    $c->response->redirect("/peering/contract_detail?edit_contract=1&amb;contract_id=$contract_id");
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

=item Andreas Granig <agranig@sipwise.com>

=item Rene Krenn <rkrenn@sipwise.com>

=item Daniel Tiefnig <dtiefnig@sipwise.com>

=back

=head1 COPYRIGHT

The peering controller is Copyright (c) 2009-2010 Sipwise GmbH, Austria.
You should have received a copy of the licences terms together with the
software.

=cut

# ende gelaende
1;
