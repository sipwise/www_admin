package admin::Controller::subscriber;

use strict;
use warnings;
use base 'Catalyst::Controller';
use admin::Utils;
use HTML::Entities;

=head1 NAME

admin::Controller::subscriber - Catalyst Controller

=head1 DESCRIPTION

This provides functionality for VoIP subscriber administration.

=head1 METHODS

=head2 index

Display search form.

=cut

sub index : Private {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/subscriber.tt';

    return 1;
}

=head2 search

Search for subscribers and display results.

=cut

sub search : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/subscriber.tt';

    my $limit = 10;
    my %filter;
    my %exact;

    if($c->request->params->{use_session}) {
        %filter = %{ $c->session->{search_filter} }
            if defined $c->session->{search_filter};
        %exact = %{ $c->session->{exact_filter} }
            if defined $c->session->{exact_filter};
    } else {
        foreach my $sf (qw(username domain number uuid)) {
            if((    defined $c->request->params->{'search_'.$sf}
                and length $c->request->params->{'search_'.$sf})
               or $c->request->params->{'exact_'.$sf})
            {
                $filter{$sf} = $c->request->params->{'search_'.$sf} || '';
                $exact{$sf} = 1 if $c->request->params->{'exact_'.$sf};
            }
        }
        $filter{terminated} = 1 if $c->request->params->{terminated};
        $c->session->{search_filter} = { %filter };
        $c->session->{exact_filter} = { %exact };
    }

    foreach my $sf (qw(username domain number uuid)) {
        # set values for webform
        $c->stash->{'exact_'.$sf} = $exact{$sf};
        $c->stash->{'search_'.$sf} = $filter{$sf};

        next unless defined $filter{$sf};

        # alter filter for SOAP call
        $filter{$sf} =~ s/\*/\%/g;
        $filter{$sf} =~ s/\?/\_/g;
        unless($exact{$sf}) {
            $filter{$sf} =~ s/^\%*/\%/;
            $filter{$sf} =~ s/\%*$/\%/;
        }
    }
    $c->stash->{terminated} = $filter{terminated};

    my $offset = $c->request->params->{offset} || 0;
    $offset = 0 if $offset !~ /^\d+$/;

    my $subscriber_list;
    return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'search_subscribers',
                                                        { filter => { %filter,
                                                                      limit    => $limit,
                                                                      offset   => $limit * $offset,
                                                                    },
                                                        },
                                                        \$subscriber_list
                                                      );

    $c->stash->{searched} = 1;
    if(ref $$subscriber_list{subscribers} eq 'ARRAY' and @{$$subscriber_list{subscribers}}) {
        $c->stash->{subscriber_list} = $$subscriber_list{subscribers};
        $c->stash->{total_count} = $$subscriber_list{total_count};
        $c->stash->{offset} = $offset;
        if($$subscriber_list{total_count} > @{$$subscriber_list{subscribers}}) {
            # paginate!
            $c->stash->{pagination} = admin::Utils::paginate($$subscriber_list{total_count}, $offset, $limit);
            $c->stash->{max_offset} = ${$c->stash->{pagination}}[-1]{offset};
        }
    }

    return 1;
}

=head2 detail

Display subscriber details.

=cut

sub detail : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/subscriber_detail.tt';

    my $is_new = $c->request->params->{new};
    my $preferences;

    unless($is_new) {
        my $subscriber_id = $c->request->params->{subscriber_id};
        return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_subscriber_byid',
                                                            { subscriber_id => $subscriber_id },
                                                            \$c->session->{subscriber}
                                                          );

        return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_subscriber_preferences',
                                                            { username => $c->session->{subscriber}{username},
                                                              domain => $c->session->{subscriber}{domain},
                                                            },
                                                            \$preferences
                                                          );

        my $regcon;
        return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_registered_contacts',
                                                            { username => $c->session->{subscriber}{username},
                                                              domain   => $c->session->{subscriber}{domain},
                                                            },
                                                            \$regcon
                                                          );
        $c->session->{subscriber}{registered_contacts} = $regcon if eval { @$regcon };

        $c->stash->{subscriber} = $c->session->{subscriber};
        $c->stash->{subscriber}{subscriber_id} = $subscriber_id;
        $c->stash->{subscriber}{is_locked} = $c->model('Provisioning')->localize($c->view($c->config->{view})->
                                                                                     config->{VARIABLES}{site_config}{language},
                                                                                 'Web.Subscriber.Lock'.$$preferences{lock})
            if $$preferences{lock};

    } else {
        $c->stash->{account_id} = $c->request->params->{account_id};
        $c->stash->{edit_subscriber} = 1;
        my $domains;
        return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_domains',
                                                            undef, \$domains
                                                          );
        $c->stash->{domains} = $domains if eval { @$domains };
    }

    ### restore data entered by the user ###

    if(ref $c->session->{restore_subscriber_input} eq 'HASH') {
       if(ref $c->stash->{subscriber} eq 'HASH') {
            $c->stash->{subscriber} = { %{$c->stash->{subscriber}}, %{$c->session->{restore_subscriber_input}} };
        } else {
            $c->stash->{subscriber} = $c->session->{restore_subscriber_input};
        }
        $c->stash->{subscriber}{edit_pass} = $c->session->{restore_subscriber_input}{password}
            if defined $c->session->{restore_subscriber_input}{password};
        $c->stash->{subscriber}{edit_webpass} = $c->session->{restore_subscriber_input}{webpassword}
            if defined $c->session->{restore_subscriber_input}{webpassword};
        delete $c->session->{restore_subscriber_input};
    }

    $c->stash->{show_pass} = $c->request->params->{show_pass};
    $c->stash->{show_webpass} = $c->request->params->{show_webpass};
    $c->stash->{edit_subscriber} = $c->request->params->{edit_subscriber}
        unless $is_new;

    return 1;
}

=head2 update_subscriber

Update subscriber data or create a new subscriber.

=cut

sub update_subscriber : Local {
    my ( $self, $c ) = @_;

    my (%settings, %messages);

    my $subscriber_id = $c->request->params->{subscriber_id};
    if($subscriber_id) {
        return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_subscriber_byid',
                                                            { subscriber_id => $subscriber_id },
                                                            \$c->session->{subscriber}
                                                          );
    } else {
        my $checkresult;
        $c->session->{subscriber}{account_id} = $c->request->params->{account_id};

        $c->session->{subscriber}{username} = $c->request->params->{username};
        return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'check_username',
                                                            $c->session->{subscriber}{username}, \$checkresult
                                                          );
        $messages{username} = 'Client.Syntax.MalformedUsername' unless($checkresult);

        $c->session->{subscriber}{domain} = $c->request->params->{domain};
        return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'check_domain',
                                                            $c->session->{subscriber}{domain}, \$checkresult
                                                          );
        $messages{domain} = 'Client.Syntax.MalformedDomain' unless($checkresult);
    }

    $settings{admin} = 1 if $c->request->params->{admin};

    my $password = $c->request->params->{password};
    if(length $password) {
        $settings{password} = $password;
        if(length $password < 6) {
            $messages{password} = 'Client.Voip.PassLength';
        }
    }
    my $webpassword = $c->request->params->{webpassword};
    if(length $webpassword) {
        $settings{webpassword} = $webpassword;
        if(length $webpassword < 6) {
            $messages{webpassword} = 'Client.Voip.PassLength';
        }
    }

    $settings{webusername} = $c->request->params->{webusername};
    if(length $settings{webusername}) {
        my $checkresult;
        return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'check_username',
                                                            $settings{webusername}, \$checkresult
                                                          );
        $messages{webusername} = 'Client.Syntax.MalformedUsername' unless($checkresult);
    } else {
        $settings{webusername} = $c->session->{subscriber}{username};
    }


    my $cc = $c->request->params->{cc};
    my $ac = $c->request->params->{ac};
    my $sn = $c->request->params->{sn};
    if(length $cc or length $ac or length $sn) {
        $settings{cc} = $cc;
        $settings{ac} = $ac;
        $settings{sn} = $sn;
        my $checkresult;
        return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'check_cc',
                                                            $cc, \$checkresult
                                                          );
        $messages{number_cc} = 'Client.Voip.MalformedCc'
            unless $checkresult;
        return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'check_ac',
                                                            $ac, \$checkresult
                                                          );
        $messages{number_ac} = 'Client.Voip.MalformedAc'
            unless $checkresult;
        return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'check_sn',
                                                            $sn, \$checkresult
                                                          );
        $messages{number_sn} = 'Client.Voip.MalformedSn'
            unless $checkresult;
    } else {
        $settings{cc} = undef;
        $settings{ac} = undef;
        $settings{sn} = undef;
    }

    unless(keys %messages) {
        if($c->model('Provisioning')->call_prov( $c, 'billing', ($subscriber_id
                                                                 ? 'update_voip_account_subscriber'
                                                                 : 'add_voip_account_subscriber'),
                                                 { id         => $c->session->{subscriber}{account_id},
                                                   subscriber => { username => $c->session->{subscriber}{username},
                                                                   domain   => $c->session->{subscriber}{domain},
                                                                   %settings
                                                                 },
                                                 },
                                                 undef))
        {
            $messages{submsg} = 'Server.Voip.SavedSettings';
            $c->session->{messages} = \%messages;
            if($subscriber_id) {
                $c->response->redirect("/subscriber/detail?subscriber_id=$subscriber_id");
            } else {
                return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_subscriber',
                                                                    { username => $c->session->{subscriber}{username},
                                                                      domain   => $c->session->{subscriber}{domain},
                                                                    },
                                                                    \$c->session->{subscriber}
                                                                  );
                $c->response->redirect("/subscriber/detail?subscriber_id=". $c->session->{subscriber}{subscriber_id});
            }
            return;
        }
    } else {
        $messages{suberr} = 'Client.Voip.InputErrorFound';
    }

    $c->session->{messages} = \%messages;
    $c->session->{restore_subscriber_input} = \%settings;
    if($subscriber_id) {
        $c->response->redirect("/subscriber/detail?subscriber_id=$subscriber_id&edit_subscriber=1");
    } else {
        $c->session->{restore_subscriber_input}{username} = $c->session->{subscriber}{username};
        $c->response->redirect("/subscriber/detail?account_id=". $c->session->{subscriber}{account_id} ."&new=1");
    }
    return;
}

=head2 lock

Locks a subscriber.

=cut

sub lock : Local {
    my ( $self, $c ) = @_;

    my $subscriber_id = $c->request->params->{subscriber_id};
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_subscriber_byid',
                                                        { subscriber_id => $subscriber_id },
                                                        \$c->session->{subscriber}
                                                      );

    my $lock = $c->request->params->{lock};
    $c->model('Provisioning')->call_prov( $c, 'billing', 'lock_voip_account_subscriber',
                                          { id       => $c->session->{subscriber}{account_id},
                                            username => $c->session->{subscriber}{username},
                                            domain   => $c->session->{subscriber}{domain},
                                            lock     => $lock,
                                          },
                                          undef
                                        );

    $c->response->redirect("/subscriber/detail?subscriber_id=". $c->request->params->{subscriber_id});
}

=head2 terminate

Terminates a subscriber.

=cut

sub terminate : Local {
    my ( $self, $c ) = @_;

    my %messages;

    my $subscriber_id = $c->request->params->{subscriber_id};
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_subscriber_byid',
                                                        { subscriber_id => $subscriber_id },
                                                        \$c->session->{subscriber}
                                                      );

    if($c->model('Provisioning')->call_prov( $c, 'billing', 'terminate_voip_account_subscriber',
                                             { id       => $c->session->{subscriber}{account_id},
                                               username => $c->session->{subscriber}{username},
                                               domain   => $c->session->{subscriber}{domain},
                                             },
                                             undef))
    {
        $messages{topmsg} = 'Server.Voip.SubscriberDeleted';
        $c->session->{messages} = \%messages;
        $c->response->redirect("/subscriber");
        return;
    }

    $c->session->{messages} = \%messages;
    $c->response->redirect("/subscriber/detail?subscriber_id=$subscriber_id");
    return;
}

sub expire : Local {
    my ( $self, $c ) = @_;

    my $subscriber_id = $c->request->params->{subscriber_id};
    my $contact_id = $c->request->params->{contact_id};

    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_subscriber_byid',
                                                        { subscriber_id => $subscriber_id },
                                                        \$c->session->{subscriber}
                                                      );

    if($c->model('Provisioning')->call_prov( $c, 'voip', 'delete_registered_contact',
                                             { username => $c->session->{subscriber}{username},
                                               domain   => $c->session->{subscriber}{domain},
                                               id       => $contact_id,
                                             },
                                             undef
                                           ))
    {
        $c->session->{messages}{contmsg} = 'Server.Voip.RemovedRegisteredContact';
        $c->response->redirect("/subscriber/detail?subscriber_id=$subscriber_id#activeregs");
    }

    $c->response->redirect("/subscriber/detail?subscriber_id=$subscriber_id");
}

=head2 preferences

Display subscriber preferences.

=cut

sub preferences : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/subscriber_preferences.tt';

    my $preferences;
    my $speed_dial_slots;

    my $subscriber_id = $c->request->params->{subscriber_id};
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_subscriber_byid',
                                                        { subscriber_id => $subscriber_id },
                                                        \$c->session->{subscriber}
                                                      );

    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_subscriber_preferences',
                                                        { username => $c->session->{subscriber}{username},
                                                          domain => $c->session->{subscriber}{domain},
                                                        },
                                                        \$preferences
                                                      );

    # voicebox requires a number
    if(length $c->session->{subscriber}{sn} && $c->config->{voicemail_features}) {
      return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_subscriber_voicebox_preferences',
                                                          { username => $c->session->{subscriber}{username},
                                                            domain   => $c->session->{subscriber}{domain},
                                                          },
                                                          \$c->session->{subscriber}{voicebox_preferences}
                                                        );
    }

    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_speed_dial_slots',
                                                        { username => $c->session->{subscriber}{username},
                                                          domain   => $c->session->{subscriber}{domain},
                                                        },
                                                        \$speed_dial_slots
                                                      );

    if($c->config->{fax_features}) {
        return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_subscriber_fax_preferences',
                                                            { username => $c->session->{subscriber}{username},
                                                              domain   => $c->session->{subscriber}{domain},
                                                            },
                                                            \$c->session->{subscriber}{fax_preferences}
                                                          );
    }

    if($c->config->{subscriber}{audiofile_features}) {
        my $audio_files;
        return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_audio_files',
                                                            { username => $c->session->{subscriber}{username},
                                                              domain   => $c->session->{subscriber}{domain},
                                                            },
                                                            \$audio_files
                                                          );
        $c->session->{subscriber}{audio_files} = $audio_files if eval { @$audio_files };
    }

    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_subscriber_reminder',
                                                        { username => $c->session->{subscriber}{username},
                                                          domain   => $c->session->{subscriber}{domain},
                                                        },
                                                        \$c->session->{subscriber}{reminder}
                                                      );

    $c->stash->{subscriber} = $c->session->{subscriber};
    $c->stash->{subscriber}{subscriber_id} = $subscriber_id;
    $c->stash->{subscriber}{is_locked} = $c->model('Provisioning')->localize($c->view($c->config->{view})->
                                                                                 config->{VARIABLES}{site_config}{language},
                                                                             'Web.Subscriber.Lock'.$$preferences{lock})
        if $$preferences{lock};

    my $db_prefs;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_preferences',
                                                        undef, \$db_prefs
                                                      );
    $c->session->{voip_preferences} = [ grep { $$_{usr_pref} } @$db_prefs ] if eval { @$db_prefs };

    ### restore data entered by the user ###

    if(ref $c->session->{restore_preferences_input} eq 'HASH') {
        if(ref $preferences eq 'HASH') {
            $preferences = { %$preferences, %{$c->session->{restore_preferences_input}} };
        } else {
            $preferences = $c->session->{restore_preferences_input};
        }
        delete $c->session->{restore_preferences_input};
    }
    if(ref $c->session->{restore_vboxprefs_input} eq 'HASH') {
        if(ref $c->stash->{subscriber}{voicebox_preferences} eq 'HASH') {
            $c->stash->{subscriber}{voicebox_preferences} = { %{$c->stash->{subscriber}{voicebox_preferences}},
                                                              %{$c->session->{restore_vboxprefs_input}} };
        } else {
            $c->stash->{subscriber}{voicebox_preferences} = $c->session->{restore_vboxprefs_input};
        }
        delete $c->session->{restore_vboxprefs_input};
    }
    if(ref $c->session->{restore_faxprefs_input} eq 'HASH') {
        if(ref $c->stash->{subscriber}{fax_preferences} eq 'HASH') {
            $c->stash->{subscriber}{fax_preferences} = { %{$c->stash->{subscriber}{fax_preferences}},
                                                         %{$c->session->{restore_faxprefs_input}} };
        } else {
            $c->stash->{subscriber}{fax_preferences} = $c->session->{restore_faxprefs_input};
        }
        delete $c->session->{restore_faxprefs_input};
    }
    if(ref $c->session->{restore_reminder_input} eq 'HASH') {
        if(ref $c->stash->{subscriber}{reminder} eq 'HASH') {
            $c->stash->{subscriber}{reminder} = { %{$c->stash->{subscriber}{reminder}},
                                                  %{$c->session->{restore_reminder_input}} };
        } else {
            $c->stash->{subscriber}{reminder} = $c->session->{restore_reminder_input};
        }
        delete $c->session->{restore_reminder_input};
    }

    ### build preference array for TT ###

    if(ref $c->session->{voip_preferences} eq 'ARRAY') {

      my @stashprefs;

      foreach my $pref (@{$c->session->{voip_preferences}}) {

        # managed separately
        next if $$pref{preference} eq 'lock';

        if($$pref{preference} eq 'cfu'
           or $$pref{preference} eq 'cfb'
           or $$pref{preference} eq 'cft'
           or $$pref{preference} eq 'cfna')
        {
          if(defined $$preferences{$$pref{preference}} and length $$preferences{$$pref{preference}}) {
            my $vbdom = $c->config->{voicebox_domain};
            my $fmdom = $c->config->{fax2mail_domain};
            my $confdom = $c->config->{conference_domain};
            if($$preferences{$$pref{preference}} =~ /\@$vbdom$/) {
              $$preferences{$$pref{preference}} = 'voicebox';
            } elsif($$preferences{$$pref{preference}} =~ /\@$fmdom$/) {
              $$preferences{$$pref{preference}} = 'fax2mail';
            } elsif($$preferences{$$pref{preference}} =~ /\@$confdom$/) {
              $$preferences{$$pref{preference}} = 'conference';
            }
          }
        } elsif(!$c->stash->{ncos_levels} and ($$pref{preference} eq 'ncos' or $$pref{preference} eq 'adm_ncos')) {
          my $ncoslvl;
          return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_ncos_levels',
                                                              undef,
                                                              \$ncoslvl
                                                            );
          $c->stash->{ncos_levels} = $ncoslvl if eval { @$ncoslvl };
        } elsif($$pref{preference} eq 'block_in_list' or $$pref{preference} eq 'block_out_list') {
          eval { @{$$preferences{$$pref{preference}}} = map { s/^([1-9])/+$1/; $_ } @{$$preferences{$$pref{preference}}} };
        }

        push @stashprefs,
             { key         => $$pref{preference},
               data_type   => $$pref{data_type},
               value       => $$preferences{$$pref{preference}},
               max_occur   => $$pref{max_occur},
               description => encode_entities($$pref{description}),
               error       => $c->session->{messages}{$$pref{preference}}
                              ? $c->model('Provisioning')->localize($c->view($c->config->{view})->
                                                                      config->{VARIABLES}{site_config}{language},
                                                                    $c->session->{messages}{$$pref{preference}})
                              : undef,
             };
      }

      $c->stash->{subscriber}{preferences_array} = \@stashprefs;
    }

    my $i = 1;
    my $default_speed_dial_slots = admin::Utils::get_default_slot_list($c);
    my @used_default_speed_dial_slots = ();
    if (eval { @$speed_dial_slots }) {
        foreach my $sdentry (sort {$a->{id} <=> $b->{id}} @$speed_dial_slots) {
            push @{$c->stash->{speed_dial_slots}}, { id          => $$sdentry{id},
                                                     number      => $i++,
                                                     label       => 'Slot ' . $$sdentry{slot} . ': ' . $$sdentry{destination}
                                                   };
            if (grep { $_ eq $$sdentry{slot} } @$default_speed_dial_slots) {
                push @used_default_speed_dial_slots,$$sdentry{slot};
            }
        }
    }
    foreach my $free_slot (@$default_speed_dial_slots) {
        unless (grep { $_ eq $free_slot } @used_default_speed_dial_slots) {
            push @{$c->stash->{speed_dial_slots}}, { id          => '',
                                                     number      => $i++,
                                                     label       => 'Slot ' . $free_slot . ': empty'
                                                   };
        }
    }

    $c->stash->{show_faxpass} = $c->request->params->{show_faxpass};
    $c->stash->{edit_preferences} = $c->request->params->{edit_preferences};
    $c->stash->{edit_voicebox} = $c->request->params->{edit_voicebox};
    $c->stash->{edit_fax} = $c->request->params->{edit_fax};
    $c->stash->{edit_reminder} = $c->request->params->{edit_reminder};

    return 1;
}

sub update_preferences : Local {
    my ( $self, $c ) = @_;

    my %messages;

    my $subscriber_id = $c->request->params->{subscriber_id};
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_subscriber_byid',
                                                        { subscriber_id => $subscriber_id },
                                                        \$c->session->{subscriber}
                                                      );
    my $preferences;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_subscriber_preferences',
                                                        { username => $c->session->{subscriber}{username},
                                                          domain => $c->session->{subscriber}{domain},
                                                        },
                                                        \$preferences
                                                      );
    my $db_prefs;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_preferences',
                                                        undef, \$db_prefs
                                                      );

    foreach my $db_pref (eval { @$db_prefs }) {

        next unless $$db_pref{usr_pref};
        next if $$db_pref{read_only};

        if($$db_pref{preference} eq 'cfu'
                or $$db_pref{preference} eq 'cfb'
                or $$db_pref{preference} eq 'cft'
                or $$db_pref{preference} eq 'cfna')
        {
            my $vbdom = $c->config->{voicebox_domain};
            my $fmdom = $c->config->{fax2mail_domain};
            my $confdom = $c->config->{conference_domain};

            my $fwtype = $$db_pref{preference};
            my $fw_target_select = $c->request->params->{$fwtype .'_target'} || 'disable';

            my $fw_target;
            if($fw_target_select eq 'sipuri') {
                $fw_target = $c->request->params->{$fwtype .'_sipuri'};

                # normalize, so we can do some checks.
                $fw_target =~ s/^sip://i;

                if($fw_target =~ /^\+?\d+$/) {
                    $fw_target = admin::Utils::get_qualified_number_for_subscriber($c, $fw_target);
                    my $checkresult;
                    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'check_E164_number', $fw_target, \$checkresult);
                    $messages{$fwtype} = 'Client.Voip.MalformedNumber'
                        unless $checkresult;
                } elsif($fw_target =~ /^[a-z0-9&=+\$,;?\/_.!~*'()-]+\@[a-z0-9.-]+(:\d{1,5})?$/i) {
                    $fw_target = 'sip:'. lc $fw_target;
                } elsif($fw_target =~ /^[a-z0-9&=+\$,;?\/_.!~*'()-]+$/) {
                    $fw_target = 'sip:'. lc($fw_target) .'@'. $c->session->{subscriber}{domain};
                } else {
                    $messages{$fwtype} = 'Client.Voip.MalformedTarget';
                    $fw_target = $c->request->params->{$fwtype .'_sipuri'};
                }
            } elsif($fw_target_select eq 'voicebox') {
                $fw_target = 'sip:vmu'.$c->session->{subscriber}{cc}.$c->session->{subscriber}{ac}.$c->session->{subscriber}{sn}."\@$vbdom";
            } elsif($fw_target_select eq 'fax2mail') {
                $fw_target = 'sip:'.$c->session->{subscriber}{cc}.$c->session->{subscriber}{ac}.$c->session->{subscriber}{sn}."\@$fmdom";
            } elsif($fw_target_select eq 'conference') {
                $fw_target = 'sip:conf='.$c->session->{subscriber}{cc}.$c->session->{subscriber}{ac}.$c->session->{subscriber}{sn}."\@$confdom";
            }
            $$preferences{$fwtype} = $fw_target;
        } elsif($$db_pref{preference} eq 'cli') {
            $$preferences{cli} = $c->request->params->{cli} or undef;
            if(defined $$preferences{cli} and $$preferences{cli} =~ /^\+?\d+$/) {
                $$preferences{cli} = admin::Utils::get_qualified_number_for_subscriber($c, $$preferences{cli});
                my $checkresult;
                return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'check_E164_number', $$preferences{cli}, \$checkresult);
                $messages{cli} = 'Client.Voip.MalformedNumber'
                    unless $checkresult;
            }
        } elsif($$db_pref{preference} eq 'cc') {
            $$preferences{$$db_pref{preference}} = $c->request->params->{$$db_pref{preference}} || undef;
            if(defined $$preferences{$$db_pref{preference}}) {
                my $checkresult;
                return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'check_cc',
                                                                    $$preferences{$$db_pref{preference}}, \$checkresult
                                                                  );
                $messages{$$db_pref{preference}} = 'Client.Voip.MalformedCc'
                    unless $checkresult;
            }
        } elsif($$db_pref{preference} eq 'ac'
                or $$db_pref{preference} eq 'svc_ac'
                or $$db_pref{preference} eq 'emerg_ac')
        {
            $$preferences{$$db_pref{preference}} = $c->request->params->{$$db_pref{preference}} || undef;
            if(defined $$preferences{$$db_pref{preference}}) {
                my $checkresult;
                return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'check_ac',
                                                                    $$preferences{$$db_pref{preference}}, \$checkresult
                                                                  );
                $messages{$$db_pref{preference}} = 'Client.Voip.MalformedAc'
                    unless $checkresult;
            }
        } elsif($$db_pref{max_occur} != 1) {
            # multi-value preferences are handled separately
        } elsif($$db_pref{data_type} eq 'int' or $$db_pref{data_type} eq 'string') {
            if(length $c->request->params->{$$db_pref{preference}}) {
                $$preferences{$$db_pref{preference}} = $c->request->params->{$$db_pref{preference}};
            } else {
                $$preferences{$$db_pref{preference}} = undef;
            }
        } elsif($$db_pref{data_type} eq 'boolean') {
            $$preferences{$$db_pref{preference}} = $c->request->params->{$$db_pref{preference}} ? 1 : undef;
        } else {
            # wtf? ignoring invalid preference
        }
    }

    if($$preferences{cft}) {
        unless(defined $$preferences{ringtimeout} and $$preferences{ringtimeout} =~ /^\d+$/
           and $$preferences{ringtimeout} < 301 and $$preferences{ringtimeout} > 4)
        {
            $messages{ringtimeout} = 'Client.Voip.MissingRingtimeout';
        }
    }


    ### save settings ###

    unless(keys %messages) {
        if($c->model('Provisioning')->call_prov( $c, 'voip', 'set_subscriber_preferences',
                                                 { username => $c->session->{subscriber}{username},
                                                   domain => $c->session->{subscriber}{domain},
                                                   preferences => $preferences,
                                                 },
                                                 undef
                                               ))
        {
            $messages{prefmsg} = 'Server.Voip.SavedSettings';
            $c->session->{messages} = \%messages;
            $c->response->redirect("/subscriber/preferences?subscriber_id=$subscriber_id#userprefs");
            return;

        }
    } else {
        $messages{preferr} = 'Client.Voip.InputErrorFound';
    }

    $c->session->{messages} = \%messages;
    $c->session->{restore_preferences_input} = $preferences;
    $c->response->redirect("/subscriber/preferences?subscriber_id=$subscriber_id&edit_preferences=1#userprefs");
    return;

}

sub update_reminder : Local {
    my ( $self, $c ) = @_;

    my %messages;

    my $subscriber_id = $c->request->params->{subscriber_id};
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_subscriber_byid',
                                                        { subscriber_id => $subscriber_id },
                                                        \$c->session->{subscriber}
                                                      );
    my $reminder;
    $$reminder{time} = $c->request->params->{time};
    $$reminder{recur} = $c->request->params->{recur} || 'never';

    ### save settings ###

    unless(keys %messages) {
        if($c->model('Provisioning')->call_prov( $c, 'voip', 'set_subscriber_reminder',
                                                 { username => $c->session->{subscriber}{username},
                                                   domain => $c->session->{subscriber}{domain},
                                                   data => $reminder,
                                                 },
                                                 undef
                                               ))
        {
            $messages{remmsg} = 'Server.Voip.SavedSettings';
            $c->session->{messages} = \%messages;
            $c->response->redirect("/subscriber/preferences?subscriber_id=$subscriber_id#reminder");
            return;
        }
    } else {
        $messages{faxerr} = 'Client.Voip.InputErrorFound';
    }

    $c->session->{messages} = \%messages;
    $c->session->{restore_reminder_input} = $reminder;
    $c->response->redirect("/subscriber/preferences?subscriber_id=$subscriber_id&edit_reminder=1#reminder");
    return;
}

sub update_voicebox : Local {
    my ( $self, $c ) = @_;

    my %messages;

    my $subscriber_id = $c->request->params->{subscriber_id};
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_subscriber_byid',
                                                        { subscriber_id => $subscriber_id },
                                                        \$c->session->{subscriber}
                                                      );
    my $vboxprefs;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_subscriber_voicebox_preferences',
                                                        { username => $c->session->{subscriber}{username},
                                                          domain => $c->session->{subscriber}{domain},
                                                        },
                                                        \$vboxprefs
                                                      );
    $$vboxprefs{password} = $c->request->params->{password} || undef;
    if(defined $$vboxprefs{password} and $$vboxprefs{password} !~ /^\d{4}$/) {
        $messages{vpin} = 'Client.Syntax.VoiceBoxPin';
    }

    $$vboxprefs{email} = $c->request->params->{email};
    if(defined $$vboxprefs{email} and length $$vboxprefs{email}) {
        my $checkresult;
        return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'check_email',
                                                            $$vboxprefs{email}, \$checkresult
                                                          );
        $messages{vemail} = 'Client.Syntax.Email' unless($checkresult);
    } else {
        $$vboxprefs{email} = undef;
    }

    $$vboxprefs{attach} = $c->request->params->{attach} ? 1 : 0;
    $$vboxprefs{delete} = $c->request->params->{delete} ? 1 : 0;

    ### save settings ###

    unless(keys %messages) {
        if($c->model('Provisioning')->call_prov( $c, 'voip', 'set_subscriber_voicebox_preferences',
                                                 { username => $c->session->{subscriber}{username},
                                                   domain => $c->session->{subscriber}{domain},
                                                   preferences => $vboxprefs,
                                                 },
                                                 undef
                                               ))
        {
            $messages{vboxmsg} = 'Server.Voip.SavedSettings';
            $c->session->{messages} = \%messages;
            $c->response->redirect("/subscriber/preferences?subscriber_id=$subscriber_id#vboxprefs");
            return;
        }
    } else {
        $messages{vboxerr} = 'Client.Voip.InputErrorFound';
    }

    $c->session->{messages} = \%messages;
    $c->session->{restore_vboxprefs_input} = $vboxprefs;
    $c->response->redirect("/subscriber/preferences?subscriber_id=$subscriber_id&edit_voicebox=1#vboxprefs");
    return;
}

=head2 call_data

Display subscriber call list.

=cut

sub call_data : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/subscriber_call_data.tt';

    my $subscriber_id = $c->request->params->{subscriber_id};
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_subscriber_byid',
                                                        { subscriber_id => $subscriber_id },
                                                        \$c->session->{subscriber}
                                                      );
    $c->stash->{subscriber} = $c->session->{subscriber};
    $c->stash->{subscriber}{subscriber_id} = $subscriber_id;

    my @localized_months = ( "foo" );

    my $cts = $c->session->{subscriber}{create_timestamp};
    if($cts =~ s/^(\d{4}-\d\d)-\d\d \d\d:\d\d:\d\d/$1/) {
        my ($cyear, $cmonth) = split /-/, $cts;
        my ($nyear, $nmonth) = (localtime)[5,4];
        $nyear += 1900;
        $nmonth++;

        for(1 .. 12) {
            push @localized_months,
                $c->model('Provisioning')->localize($c->view($c->config->{view})->
                                                        config->{VARIABLES}{site_config}{language},
                                                    sprintf("Web.Months.%02d", $_));
        }

        my @selectmonths;

        while($cyear < $nyear) {
            my @yearmon;
            for($cmonth .. 12) {
                my $amon = sprintf("%02d", $_);
                unshift @yearmon, { display => $localized_months[$amon] ." $cyear", link => $cyear.$amon };
            }
            unshift @selectmonths, { year => $cyear, months => \@yearmon };
            $cmonth = 1;
            $cyear++;
        }

        my @yearmon;
        for($cmonth .. $nmonth) {
            my $amon = sprintf("%02d", $_);
            unshift @yearmon, { display => $localized_months[$amon] ." $cyear", link => $cyear.$amon };
        }
        unshift @selectmonths, { year => $cyear, months => \@yearmon };

        $c->stash->{subscriber}{selectmonths} = \@selectmonths;
    }

    my $listfilter = $c->request->params->{list_filter};
    if(defined $listfilter) {
        if(length $listfilter) {
            $listfilter =~ s/^\*//;
            $listfilter =~ s/\*$//;
            $c->session->{calllist}{filter} = $listfilter;
        } else {
            delete $c->session->{calllist}{filter};
            undef $listfilter;
        }
    }

    my @localtime = localtime;

    my ($callmonth, $callyear);
    my $monthselect = $c->request->params->{listmonth};
    if(defined $monthselect and $monthselect =~ /^(\d{4})(\d{2})$/) {
        $callyear = $1;
        $callmonth = $2;
        $listfilter = $c->session->{calllist}{filter};
        delete $c->session->{calllist}{start};
        delete $c->session->{calllist}{end};
    } else {
        $callyear = $localtime[5] + 1900;
        $callmonth = $localtime[4] + 1;
        delete $c->session->{calllist}{filter};
        delete $c->session->{calllist}{start};
        delete $c->session->{calllist}{end};
    }

    my $liststart = $c->request->params->{list_start};
    if(defined $liststart) {
        if(length $liststart) {
            $c->stash->{subscriber}{list_start} = $liststart;
            if($liststart =~ /^\d\d\.\d\d\.\d\d\d\d$/) {
                $c->session->{calllist}{start} = $liststart;
            } else {
                $liststart = $c->session->{calllist}{start};
                $c->session->{messages}{msgdate} = 'Client.Syntax.Date';
            }
        } else {
            delete $c->session->{calllist}{start};
            undef $liststart;
        }
    } else {
        $c->stash->{subscriber}{list_start} = $c->session->{calllist}{start};
    }

    my $listend = $c->request->params->{list_end};
    if(defined $listend) {
        if(length $listend) {
            $c->stash->{subscriber}{list_end} = $listend;
            if($listend =~ /^\d\d\.\d\d\.\d\d\d\d$/) {
                $c->session->{calls}{end} = $listend;
            } else {
                $listend = $c->session->{calllist}{end};
                $c->session->{messages}{msgdate} = 'Client.Syntax.Date';
            }
        } else {
            delete $c->session->{calllist}{end};
            undef $listend;
        }
    } else {
        $c->stash->{subscriber}{list_end} = $c->session->{calllist}{end};
    }

    my ($sdate, $edate);
    if(!defined $liststart and !defined $listend) {
        $sdate = { year => $callyear, month => $callmonth };
        $edate = { year => $callyear, month => $callmonth };
        $c->stash->{selected_month} = sprintf "%04d%02d", $callyear, $callmonth;
    } else {
        if(defined $liststart) {
            my ($day, $month, $year) = split /\./, $liststart;
            $sdate = { year => $year, month => $month, day => $day };
        }
        if (defined $listend) {
            my ($day, $month, $year) = split /\./, $listend;
            $edate = { year => $year, month => $month, day => $day };
        }
    }

    my $calls;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_subscriber_calls',
                                                        { username => $c->session->{subscriber}{username},
                                                          domain   => $c->session->{subscriber}{domain},
                                                          filter   => { start_date => $sdate,
                                                                        end_date   => $edate,
                                                                      }
                                                        },
                                                        \$calls
                                                      );

    return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_voip_account_by_id',
                                                        { id => $c->session->{subscriber}{account_id} },
                                                        \$c->session->{voip_account}
                                                      );
    if(eval { defined $c->session->{voip_account}{billing_profile} }) {
        return 1 unless $c->model('Provisioning')->call_prov($c, 'billing', 'get_billing_profile',
                                                             { handle => $c->session->{voip_account}{billing_profile} },
                                                             \$c->session->{voip_account}{billing_profile}
                                                            );
    }

    $c->stash->{call_list} = admin::Utils::prepare_call_list($c, $calls, $listfilter);
    $c->stash->{subscriber}{list_filter} = $listfilter if defined $listfilter;

    undef $c->stash->{call_list} unless eval { @{$c->stash->{call_list}} };

    return;
}


sub edit_list : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/subscriber_edit_list.tt';

    my %messages;

    my $subscriber_id = $c->request->params->{subscriber_id};
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_subscriber_byid',
                                                        { subscriber_id => $subscriber_id },
                                                        \$c->session->{subscriber}
                                                      );
    my $preferences;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_subscriber_preferences',
                                                        { username => $c->session->{subscriber}{username},
                                                          domain => $c->session->{subscriber}{domain},
                                                        },
                                                        \$preferences
                                                      );
    my $list = $c->request->params->{list_name};

    if(defined $$preferences{$list}) {
        my $block_list = ref $$preferences{$list} ? $$preferences{$list} : [ $$preferences{$list} ];

        my @block_list_to_sort;
        foreach my $blockentry (@$block_list) {
            my $active = $blockentry =~ s/^#// ? 0 : 1;
            $blockentry =~ s/^([1-9])/+$1/;
            push @block_list_to_sort, { entry => $blockentry, active => $active };
        }
        my $bg = '';
        my $i = 1;
        foreach my $blockentry (sort {$a->{entry} cmp $b->{entry}} @block_list_to_sort) {
            push @{$c->stash->{list_data}}, { number     => $$blockentry{entry},
                                              background => $bg ? '' : 'tr_alt',
                                              id         => $i++,
                                              active     => $$blockentry{active},
                                            };
            $bg = !$bg;
        }
    }

    $c->stash->{subscriber} = $c->session->{subscriber};
    $c->stash->{subscriber_id} = $subscriber_id;
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

sub do_edit_list : Local {
    my ( $self, $c ) = @_;

    my %messages;

    my $subscriber_id = $c->request->params->{subscriber_id};
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_subscriber_byid',
                                                        { subscriber_id => $subscriber_id },
                                                        \$c->session->{subscriber}
                                                      );
    my $preferences;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_subscriber_preferences',
                                                        { username => $c->session->{subscriber}{username},
                                                          domain => $c->session->{subscriber}{domain},
                                                        },
                                                        \$preferences
                                                      );
    my $list = $c->request->params->{list_name};

    # input text field to add new entry to block list
    my $add = $c->request->params->{block_add};
    if(defined $add) {
        if($add =~ /^\+?[?*0-9\[\]-]+$/) {
            my $ccdp = $c->config->{cc_dial_prefix};
            my $acdp = $c->config->{ac_dial_prefix};
            if($add =~ /^\*/ or $add =~ /^\?/ or $add =~ /^\[/) {
                # do nothing
            } elsif($add =~ s/^\+// or $add =~ s/^$ccdp//) {
                # nothing more to do
            } elsif($add =~ s/^$acdp//) {
                $add = $c->session->{subscriber}{cc} . $add;
            } else {
                $add = $c->session->{subscriber}{cc} . $c->session->{subscriber}{ac} . $add;
            }
            my $blocklist = $$preferences{$list};
            $blocklist = [] unless defined $blocklist;
            $blocklist = [ $blocklist ] unless ref $blocklist;
            $$preferences{$list} = [ @$blocklist, $add ];
        } else {
            $messages{msgadd} = 'Client.Voip.MalformedNumberPattern';
            $c->session->{blockaddtxt} = $add;
        }
    }

    # delete link next to entries in block list
    my $del = $c->request->params->{block_del};
    if(defined $del) {
        my $blocklist = $$preferences{$list};
        if(defined $blocklist) {
            my $ccdp = $c->config->{cc_dial_prefix};
            my $acdp = $c->config->{ac_dial_prefix};
            if($del =~ /^\*/ or $del =~ /^\?/ or $del =~ /^\[/) {
                # do nothing
            } elsif($del =~ s/^\+// or $del =~ s/^$ccdp//) {
                # nothing more to do
            } elsif($del =~ s/^$acdp//) {
                $del = $c->session->{subscriber}{cc} . $del;
            }
            $blocklist = [ $blocklist ] unless ref $blocklist;
            if($c->request->params->{block_stat}) {
                $$preferences{$list} = [ grep { $_ ne $del } @$blocklist ];
            } else {
                $$preferences{$list} = [ grep { $_ ne '#'.$del } @$blocklist ];
            }
        }
    }

    # activate/deactivate link next to entries in block list
    my $act = $c->request->params->{block_act};
    if(defined $act) {
        my $blocklist = $$preferences{$list};
        if(defined $blocklist) {
            my $ccdp = $c->config->{cc_dial_prefix};
            my $acdp = $c->config->{ac_dial_prefix};
            if($act =~ /^\*/ or $act =~ /^\?/ or $act =~ /^\[/) {
                # do nothing
            } elsif($act =~ s/^\+// or $act =~ s/^$ccdp//) {
                # nothing more to do
            } elsif($act =~ s/^$acdp//) {
                $act = $c->session->{subscriber}{cc} . $act;
            }
            $blocklist = [ $blocklist ] unless ref $blocklist;
            if($c->request->params->{block_stat}) {
                $$preferences{$list} = [ grep { $_ ne $act } @$blocklist ];
                push @{$$preferences{$list}}, '#'.$act;
            } else {
                $$preferences{$list} = [ grep { $_ ne '#'.$act } @$blocklist ];
                push @{$$preferences{$list}}, $act;
            }
        }
    }

    unless(keys %messages) {
        $c->model('Provisioning')->call_prov( $c, 'voip', 'set_subscriber_preferences',
                                              { username => $c->session->{subscriber}{username},
                                                domain => $c->session->{subscriber}{domain},
                                                preferences => {
                                                                 $list => $$preferences{$list},
                                                               },
                                              },
                                              undef
                                            );
    } else {
        $messages{numerr} = 'Client.Voip.InputErrorFound';
    }

    $c->session->{messages} = \%messages;
    $c->response->redirect("/subscriber/edit_list?subscriber_id=$subscriber_id&list_name=$list");

}

sub edit_iplist : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/subscriber_edit_iplist.tt';

    my %messages;

    my $subscriber_id = $c->request->params->{subscriber_id};
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_subscriber_by_id',
                                                        { subscriber_id => $subscriber_id },
                                                        \$c->session->{subscriber}
                                                      );
    my $preferences;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_subscriber_preferences',
                                                        { username => $c->session->{subscriber}{username},
                                                          domain => $c->session->{subscriber}{domain},
                                                        },
                                                        \$preferences
                                                      );
    my $list = $c->request->params->{list_name};

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

    $c->stash->{subscriber} = $c->session->{subscriber};
    $c->stash->{subscriber_id} = $subscriber_id;
    $c->stash->{list_name} = $list;

    if(defined $c->session->{listaddtxt}) {
        $c->stash->{listaddtxt} = $c->session->{listaddtxt};
        delete $c->session->{listaddtxt};
    }

    return 1;
}

sub do_edit_iplist : Local {
    my ( $self, $c ) = @_;

    my %messages;

    my $subscriber_id = $c->request->params->{subscriber_id};
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_subscriber_byid',
                                                        { subscriber_id => $subscriber_id },
                                                        \$c->session->{subscriber}
                                                      );
    my $preferences;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_subscriber_preferences',
                                                        { username => $c->session->{subscriber}{username},
                                                          domain => $c->session->{subscriber}{domain},
                                                        },
                                                        \$preferences
                                                      );
    my $list = $c->request->params->{list_name};

    # input text field to add new entry to IP list
    my $add = $c->request->params->{list_add};
    if(defined $add) {
        my $checkresult;
        return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'check_ipnet', $add, \$checkresult);
        if($checkresult) {
            my $iplist = $$preferences{$list};
            $iplist = [] unless defined $iplist;
            $iplist = [ $iplist ] unless ref $iplist;
            $$preferences{$list} = [ @$iplist, $add ];
        } else {
            $messages{msgadd} = 'Client.Syntax.MalformedIPNet';
            $c->session->{listaddtxt} = $add;
        }
    }

    # delete link next to entries in IP list
    my $del = $c->request->params->{list_del};
    if(defined $del) {
        my $iplist = $$preferences{$list};
        if(defined $iplist) {
            $iplist = [ $iplist ] unless ref $iplist;
            $$preferences{$list} = [ grep { $_ ne $del } @$iplist ];
        }
    }

    unless(keys %messages) {
        $c->model('Provisioning')->call_prov( $c, 'voip', 'set_subscriber_preferences',
                                              { username => $c->session->{subscriber}{username},
                                                domain => $c->session->{subscriber}{domain},
                                                preferences => {
                                                                 $list => $$preferences{$list},
                                                               },
                                              },
                                              undef
                                            );
    } else {
        $messages{numerr} = 'Client.Voip.InputErrorFound';
    }

    $c->session->{messages} = \%messages;
    $c->response->redirect("/subscriber/edit_iplist?subscriber_id=$subscriber_id&list_name=$list");
}

sub edit_speed_dial_slots : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/subscriber_edit_speeddial.tt';

    my %messages;

    my $subscriber_id = $c->request->params->{subscriber_id};
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_subscriber_byid',
                                                        { subscriber_id => $subscriber_id },
                                                        \$c->session->{subscriber}
                                                      );
    my $speed_dial_slots;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_speed_dial_slots',
                                                            { username => $c->session->{subscriber}{username},
                                                              domain   => $c->session->{subscriber}{domain},
                                                            },
                                                            \$speed_dial_slots
                                                          );

    my $i = 1;
    my $bg = '';
    my $default_speed_dial_slots = admin::Utils::get_default_slot_list($c);
    my @used_default_speed_dial_slots = ();
    if (eval { @$speed_dial_slots }) {
        foreach my $sdentry (sort {$a->{id} <=> $b->{id}} @$speed_dial_slots) {
            my $updateerrormsg;
            if(defined $c->session->{updateslotidtxt} and $c->session->{updateslotidtxt} eq $$sdentry{id}) {
                if (defined $c->session->{updateslottxt}) {
                    $$sdentry{slot} = $c->session->{updateslottxt};
                    delete $c->session->{updateslottxt};
                }
                if (defined $c->session->{updatedestinationtxt}) {
                    $$sdentry{destination} = $c->session->{updatedestinationtxt};
                    delete $c->session->{updatedestinationtxt};
                }
                delete $c->session->{updateslotidtxt};
                $updateerrormsg = $c->session->{messages}{updateerr} ?
                                    $c->model('Provisioning')->localize($c->view($c->config->{view})->
                                                                      config->{VARIABLES}{site_config}{language},
                                                                      $c->session->{messages}{updateerr})
                                    : undef;
                #delete $c->session->{updateerrmsg};
            }
            push @{$c->stash->{speed_dial_slots}}, { id          => $$sdentry{id},
                                                 number      => $i++,
                                                 background  => $bg ? '' : 'tr_alt',
                                                 slot        => $$sdentry{slot},
                                                 destination => $$sdentry{destination},
                                                 error       => $updateerrormsg
                                               };
            if (grep { $_ eq $$sdentry{slot} } @$default_speed_dial_slots) {
                push @used_default_speed_dial_slots,$$sdentry{slot};
            }
            $bg = !$bg;
        }
    }
    $i = 0;
    foreach my $free_slot (@$default_speed_dial_slots) {
        unless (grep { $_ eq $free_slot } @used_default_speed_dial_slots) {
            $i++;
            push @{$c->stash->{free_speed_dial_slots}}, { number => $i,
                                                          slot   => $free_slot
                                                        };
        }
    }

    $c->stash->{subscriber} = $c->session->{subscriber};
    $c->stash->{subscriber_id} = $subscriber_id;

    if(defined $c->session->{addslottxt}) {
        $c->stash->{addslottxt} = $c->session->{addslottxt};
        delete $c->session->{addslottxt};
    }
    if(defined $c->session->{adddestinationtxt}) {
        $c->stash->{adddestinationtxt} = $c->session->{adddestinationtxt};
        delete $c->session->{adddestinationtxt};
    }

    return 1;
}

sub do_edit_speed_dial_slots : Local {
    my ( $self, $c ) = @_;

    my %messages;

    my $subscriber_id = $c->request->params->{subscriber_id};
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_subscriber_byid',
                                                        { subscriber_id => $subscriber_id },
                                                        \$c->session->{subscriber}
                                                      );

    # add new entry form
    my $add_slot = $c->request->params->{add_slot};
    my $add_destination = $c->request->params->{add_destination};
    if(defined $add_slot) {

        my $checkadd_slot;
        return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'check_vsc_format', $add_slot, \$checkadd_slot);
        my $checkadd_destination;
        my $destination;
        if ($add_destination =~ /^\+?\d+$/) {
            $add_destination = admin::Utils::get_qualified_number_for_subscriber($c, $add_destination);
            my $checkresult;
            return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'check_E164_number', $add_destination, \$checkresult);
            $destination = 'sip:'. $add_destination .'@'. $c->session->{subscriber}{domain}
                if $checkresult;
        } else {
            $destination = $add_destination;
        }
        if ($destination =~ /^sip:.+\@.+$/) {
            $checkadd_destination = 1;
        }

        if($checkadd_slot and $checkadd_destination) {
            $c->model('Provisioning')->call_prov( $c, 'voip', 'create_speed_dial_slot',
                                                  { username => $c->session->{subscriber}{username},
                                                    domain => $c->session->{subscriber}{domain},
                                                    data => {
                                                                 slot        => $add_slot,
                                                                 destination => $add_destination
                                                            },
                                                  },
                                                  undef
                                                );
        } else {
            unless ($checkadd_destination) {
                $c->session->{adddestinationtxt} = $add_destination;
                $messages{msgadd} = 'Client.Syntax.MalformedSpeedDialDestination';
            }
            #we display the slot error in case of both errors occurring at the same time
            #since it should never occur (dropdown box selection of valid vsc strings)
            #and would thus be more severe (system config misconfiguration).
            #we should consider displaying an internal error at all...
            unless ($checkadd_slot) {
                $c->session->{addslottxt} = $add_slot;
                $messages{msgadd} = 'Client.Syntax.MalformedVSC';
            }
            $messages{numerr} = 'Client.Voip.InputErrorFound';
        }

    }

    # delete link forms
    my $delete_slotid = $c->request->params->{delete_id};
    if(defined $delete_slotid) {
        $c->model('Provisioning')->call_prov( $c, 'voip', 'delete_speed_dial_slot',
                                          { username => $c->session->{subscriber}{username},
                                            domain => $c->session->{subscriber}{domain},
                                            id => $delete_slotid
                                          },
                                          undef
                                        );
    }

    # update link forms
    my $update_slotid = $c->request->params->{update_id};
    my $update_slot = $c->request->params->{slot};
    my $update_destination = $c->request->params->{destination};
    if(defined $update_slotid) {

        my $checkupdate_slot;
        return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'check_vsc_format', $update_slot, \$checkupdate_slot);
        my $checkupdate_destination;
        my $destination;
        if ($update_destination =~ /^\+?\d+$/) {
            $update_destination = admin::Utils::get_qualified_number_for_subscriber($c, $update_destination);
            my $checkresult;
            return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'check_E164_number', $update_destination, \$checkresult);
            $destination = 'sip:'. $update_destination .'@'. $c->session->{subscriber}{domain}
                if $checkresult;
        } else {
            $destination = $update_destination;
        }
        if ($destination =~ /^sip:.+\@.+$/) {
            $checkupdate_destination = 1;
        }

        if($checkupdate_slot and $checkupdate_destination) {
            $c->model('Provisioning')->call_prov( $c, 'voip', 'update_speed_dial_slot',
                                                  { username => $c->session->{subscriber}{username},
                                                    domain => $c->session->{subscriber}{domain},
                                                    id => $update_slotid,
                                                    data => {
                                                                     slot        => $update_slot,
                                                                     destination => $update_destination
                                                            },
                                                  },
                                                  undef
                                                );
        } else {
            $c->session->{updateslotidtxt} = $update_slotid;
            unless ($checkupdate_destination) {
                $c->session->{updatedestinationtxt} = $update_destination;
                $messages{updateerr} = 'Client.Syntax.MalformedSpeedDialDestination';
                #$c->session->{updateerrmsg} = 'Client.Syntax.MalformedSpeedDialDestination';
            }
            #we display the slot error in case of both errors occurring at the same time
            #since it should never occur (dropdown box selection of valid vsc strings)
            #and would thus be more severe (system config misconfiguration).
            #we should consider displaying an internal error at all...
            unless ($checkupdate_slot) {
                $c->session->{updateslottxt} = $update_slot;
                $messages{updateerr} = 'Client.Syntax.MalformedVSC';
                #$messages{updateerrmsg} = 'Client.Syntax.MalformedVSC';
            }
            $messages{numerr} = 'Client.Voip.InputErrorFound';
        }

    }

    unless(keys %messages) {
        $messages{nummsg} = 'Server.Voip.SavedSettings';
    }

    $c->session->{messages} = \%messages;
    $c->response->redirect("/subscriber/edit_speed_dial_slots?subscriber_id=$subscriber_id");

}

sub update_fax : Local {
    my ( $self, $c ) = @_;

    my %messages;

    my $subscriber_id = $c->request->params->{subscriber_id};
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_subscriber_by_id',
                                                        { subscriber_id => $subscriber_id },
                                                        \$c->session->{subscriber}
                                                      );
    my $faxprefs;
    $$faxprefs{name} = $c->request->params->{name} || undef;
    $$faxprefs{password} = $c->request->params->{password} if length $c->request->params->{password};
    $$faxprefs{active} = $c->request->params->{active} ? 1 : 0;
    $$faxprefs{send_status} = $c->request->params->{send_status} ? 1 : 0;
    $$faxprefs{send_copy} = $c->request->params->{send_copy} ? 1 : 0;

    ### save settings ###

    unless(keys %messages) {
        if($c->model('Provisioning')->call_prov( $c, 'voip', 'set_subscriber_fax_preferences',
                                                 { username => $c->session->{subscriber}{username},
                                                   domain => $c->session->{subscriber}{domain},
                                                   preferences => $faxprefs,
                                                 },
                                                 undef
                                               ))
        {
            $messages{faxmsg} = 'Server.Voip.SavedSettings';
            $c->session->{messages} = \%messages;
            $c->response->redirect("/subscriber/preferences?subscriber_id=$subscriber_id#faxprefs");
            return;
        }
    } else {
        $messages{faxerr} = 'Client.Voip.InputErrorFound';
    }

    $c->session->{messages} = \%messages;
    $$faxprefs{repass} = $$faxprefs{password};
    $c->session->{restore_faxprefs_input} = $faxprefs;
    $c->response->redirect("/subscriber/preferences?subscriber_id=$subscriber_id&edit_fax=1#faxprefs");
    return;
}

sub edit_destlist : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/subscriber_edit_destlist.tt';

    my %messages;

    my $subscriber_id = $c->request->params->{subscriber_id};
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_subscriber_by_id',
                                                        { subscriber_id => $subscriber_id },
                                                        \$c->session->{subscriber}
                                                      );
    my $preferences;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_subscriber_fax_preferences',
                                                        { username => $c->session->{subscriber}{username},
                                                          domain => $c->session->{subscriber}{domain},
                                                        },
                                                        \$preferences
                                                      );
    my $list = $c->request->params->{list_name};

    if(defined $$preferences{$list}) {
        my $destlist = ref $$preferences{$list} ? $$preferences{$list} : [ $$preferences{$list} ];

        my $bg = '';
        my $i = 1;
        foreach my $entry (sort { $$a{destination} cmp $$b{destination} } @$destlist) {
            push @{$c->stash->{list_data}}, { %$entry,
                                              background => $bg ? '' : 'tr_alt',
                                              id         => $i++,
                                            };
            $bg = !$bg;
        }
    }

    $c->stash->{subscriber} = $c->session->{subscriber};
    $c->stash->{subscriber_id} = $subscriber_id;
    $c->stash->{list_name} = $list;
    $c->stash->{edit_dest} = $c->request->params->{list_edit};

    if(defined $c->session->{arefill}) {
        $c->stash->{arefill} = $c->session->{arefill};
        delete $c->session->{arefill};
    }

    return 1;
}

sub do_edit_destlist : Local {
    my ( $self, $c ) = @_;

    my %messages;
    my %entry;

    my $subscriber_id = $c->request->params->{subscriber_id};
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_subscriber_byid',
                                                        { subscriber_id => $subscriber_id },
                                                        \$c->session->{subscriber}
                                                      );
    my $preferences;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_subscriber_fax_preferences',
                                                        { username => $c->session->{subscriber}{username},
                                                          domain => $c->session->{subscriber}{domain},
                                                        },
                                                        \$preferences
                                                      );
    my $list = $c->request->params->{list_name};

    # delete link in destination list
    # this is also sent by the save link next to entries in edit mode
    my $del = $c->request->params->{list_del};
    if(defined $del) {
        my $destlist = $$preferences{$list};
        if(defined $destlist) {
            $destlist = [ $destlist ] unless ref $destlist;
            $$preferences{$list} = [ grep { $$_{destination} ne $del } @$destlist ];
        }
    }

    # input text field to add new entry to destination list
    # this is also sent (together with a list_del) by the save link in edit mode
    my $add = $c->request->params->{list_add};
    if(defined $add) {
        my $checkresult;
        if($add =~ /^\+?\d+$/) {
          $add = admin::Utils::get_qualified_number_for_subscriber($c, $add);
          return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'check_E164_number', $add, \$checkresult);
        } else {
          return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'check_email', $add, \$checkresult);
        }
        unless($checkresult) {
            $messages{msgadd} = 'Client.Voip.MalformedFaxDestination';
        }
        $entry{destination} = $add;
        $entry{filetype} = $c->request->params->{filetype} || 'TIFF';
        $entry{cc} = $c->request->params->{cc} ? 1 : 0;
        $entry{incoming} = $c->request->params->{incoming} ? 1 : 0;
        $entry{outgoing} = $c->request->params->{outgoing} ? 1 : 0;
        $entry{status} = $c->request->params->{status} ? 1 : 0;

        my $destlist = $$preferences{$list};
        $destlist = [] unless defined $destlist;
        $destlist = [ $destlist ] unless ref $destlist;

        if(grep { lc $$_{destination} eq lc $add } @$destlist) {
            $messages{msgadd} = 'Web.Fax.ExistingFaxDestination';
        } else {
            $$preferences{$list} = [ @$destlist, \%entry ];
        }

        $c->session->{arefill} = \%entry if keys %messages;
    }

    unless(keys %messages) {
        $c->model('Provisioning')->call_prov( $c, 'voip', 'set_subscriber_fax_preferences',
                                              { username => $c->session->{subscriber}{username},
                                                domain => $c->session->{subscriber}{domain},
                                                preferences => {
                                                                 $list => $$preferences{$list},
                                                               },
                                              },
                                              undef
                                            );
    } else {
        $messages{numerr} = 'Client.Voip.InputErrorFound';
    }

    $c->session->{messages} = \%messages;
    $c->response->redirect("/subscriber/edit_destlist?subscriber_id=$subscriber_id&list_name=$list");
}

sub edit_audio_files : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/subscriber_edit_audio_files.tt';

    my $subscriber_id = $c->request->params->{subscriber_id};
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_subscriber_by_id',
                                                        { subscriber_id => $subscriber_id },
                                                        \$c->session->{subscriber}
                                                      );

    $c->stash->{subscriber} = $c->session->{subscriber};
    $c->stash->{subscriber_id} = $subscriber_id;

    my %settings;
    $settings{username} = $c->session->{subscriber}{username};
    $settings{domain} = $c->session->{subscriber}{domain};

    my $audio_files;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_audio_files',
                                                        { %settings },
                                                        \$audio_files
                                                      );
    $c->stash->{audio_files} = $audio_files if eval { @$audio_files };

    $c->stash->{edit_audio} = $c->request->params->{edit_audio};

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

    my $subscriber_id = $c->request->params->{subscriber_id};
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_subscriber_by_id',
                                                        { subscriber_id => $subscriber_id },
                                                        \$c->session->{subscriber}
                                                      );

    $c->stash->{subscriber} = $c->session->{subscriber};
    $c->stash->{subscriber_id} = $subscriber_id;

    $settings{username} = $c->session->{subscriber}{username};
    $settings{domain} = $c->session->{subscriber}{domain};
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
            $c->response->redirect("/subscriber/edit_audio_files?subscriber_id=$subscriber_id");
            return;
        }
    }

    $messages{audioerr} = 'Client.Voip.InputErrorFound';
    $c->session->{messages} = \%messages;
    $c->session->{acrefill} = \%settings;
    $c->response->redirect("/subscriber/edit_audio_files?subscriber_id=$subscriber_id");
    return;
}

=head2 do_update_audio

Update an audio file in the database.

=cut

sub do_update_audio : Local {
    my ( $self, $c ) = @_;

    my %messages;
    my %settings;

    my $subscriber_id = $c->request->params->{subscriber_id};
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_subscriber_by_id',
                                                        { subscriber_id => $subscriber_id },
                                                        \$c->session->{subscriber}
                                                      );

    $c->stash->{subscriber} = $c->session->{subscriber};
    $c->stash->{subscriber_id} = $subscriber_id;

    $settings{username} = $c->session->{subscriber}{username};
    $settings{domain} = $c->session->{subscriber}{domain};
    $settings{handle} = $c->request->params->{handle};
    unless(length $settings{handle}) {
        $c->response->redirect("/subscriber/edit_audio_files?subscriber_id=$subscriber_id");
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
            $c->response->redirect("/subscriber/edit_audio_files?subscriber_id=$subscriber_id");
            return;
        }
        $c->response->redirect("/subscriber/edit_audio_files?subscriber_id=$subscriber_id&amp;edit_audio=$settings{handle}");
        return;
    }

    $messages{audioerr} = 'Client.Voip.InputErrorFound';
    $c->session->{messages} = \%messages;
    $c->session->{aerefill} = $settings{data};
    $c->response->redirect("/subscriber/edit_audio_files?subscriber_id=$subscriber_id&amp;edit_audio=$settings{handle}");
    return;
}

=head2 do_delete_audio

Delete an audio file from the database.

=cut

sub do_delete_audio : Local {
    my ( $self, $c ) = @_;

    my %settings;

    my $subscriber_id = $c->request->params->{subscriber_id};
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_subscriber_by_id',
                                                        { subscriber_id => $subscriber_id },
                                                        \$c->session->{subscriber}
                                                      );

    $c->stash->{subscriber} = $c->session->{subscriber};
    $c->stash->{subscriber_id} = $subscriber_id;

    $settings{username} = $c->session->{subscriber}{username};
    $settings{domain} = $c->session->{subscriber}{domain};
    $settings{handle} = $c->request->params->{handle};
    unless(length $settings{handle}) {
        $c->response->redirect("/subscriber/edit_audio_files?subscriber_id=$subscriber_id");
        return;
    }

    if($c->model('Provisioning')->call_prov( $c, 'voip', 'delete_audio_file',
                                             \%settings,
                                             undef))
    {
        $c->session->{messages} = { provmsg => 'Web.AudioFile.Deleted' };
        $c->response->redirect("/subscriber/edit_audio_files?subscriber_id=$subscriber_id");
        return;
    }

    $c->response->redirect("/subscriber/edit_audio_files?subscriber_id=$subscriber_id");
    return;
}

=head2 listen_audio

Listen to an audio file from the database.

=cut

sub listen_audio : Local {
    my ( $self, $c ) = @_;

    my %settings;

    my $subscriber_id = $c->request->params->{subscriber_id};
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_subscriber_by_id',
                                                        { subscriber_id => $subscriber_id },
                                                        \$c->session->{subscriber}
                                                      );

    $settings{username} = $c->session->{subscriber}{username};
    $settings{domain} = $c->session->{subscriber}{domain};
    $settings{handle} = $c->request->params->{handle};
    unless(length $settings{handle}) {
        $c->response->redirect("/subscriber/edit_audio_files?subscriber_id=$subscriber_id");
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

    $c->response->redirect("/subscriber/edit_audio_files?subscriber_id=$subscriber_id");
    return;
}

=head1 BUGS AND LIMITATIONS

=over

=item currently none

=back

=head1 SEE ALSO

Provisioning model, Catalyst

=head1 AUTHORS

=over

=item Daniel Tiefnig <dtiefnig@sipwise.com>

=item Rene Krenn <rkrenn@sipwise.com>

=back

=head1 COPYRIGHT

The subscriber controller is Copyright (c) 2007-2010 Sipwise GmbH,
Austria. You should have received a copy of the licences terms together
with the software.

=cut

# ende gelaende
1;
