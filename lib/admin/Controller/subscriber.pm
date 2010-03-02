package admin::Controller::subscriber;

use strict;
use warnings;
use base 'Catalyst::Controller';
use admin::Utils;

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
        %filter = %{ $c->session->{search_filter} };
        %exact = %{ $c->session->{exact_filter} };
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

        $c->session->{subscriber}{username} = $settings{webusername} = $c->request->params->{username};
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

    my $cc = $c->request->params->{cc};
    my $ac = $c->request->params->{ac};
    my $sn = $c->request->params->{sn};
    if(length $cc or length $ac or length $sn) {
        $settings{cc} = $cc;
        $settings{ac} = $ac;
        $settings{sn} = $sn;
        unless(length $cc and length $ac and length $sn) {
            $messages{number} = 'Client.Voip.MissingNumberPart';
        } else {
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
        }
    } else {
        $settings{cc} = undef;
        $settings{ac} = undef;
        $settings{sn} = undef;
    }

    my $timezone = $c->request->params->{timezone};
    if(length $timezone) {
        $settings{timezone} = $timezone;
        $messages{timezone} = 'Client.Syntax.MalformedTimezone'
            unless $timezone =~ m#^\w+/\w.+$#;
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
    $c->session->{voip_preferences} = $db_prefs if eval { @$db_prefs };

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

    ### build preference array for TT ###

    if(ref $c->session->{voip_preferences} eq 'ARRAY') {

      my $cftarget;
      my @stashprefs;

      foreach my $pref (@{$c->session->{voip_preferences}}) {

        # not a subscriber preference
        next if $$pref{attribute} eq 'cc';
        # managed separately
        next if $$pref{attribute} eq 'lock';

        # only for extensions enabled systems
        next if (   $$pref{attribute} eq 'base_cli'
                 or $$pref{attribute} eq 'base_user'
                 or $$pref{attribute} eq 'extension'
                 or $$pref{attribute} eq 'has_extension' )
                and !$c->config->{extension_features};


        if($$pref{attribute} eq 'cfu'
           or $$pref{attribute} eq 'cfb'
           or $$pref{attribute} eq 'cft'
           or $$pref{attribute} eq 'cfna')
        {
          if(defined $$preferences{$$pref{attribute}} and length $$preferences{$$pref{attribute}}) {
            if($$preferences{$$pref{attribute}} =~ /\@voicebox\.local$/) {
              $$preferences{$$pref{attribute}} = 'voicebox';
            } elsif($$preferences{$$pref{attribute}} =~ /\@fax2mail\.local$/) {
              $$preferences{$$pref{attribute}} = 'fax2mail';
            } else {
              $$preferences{$$pref{attribute}} =~ s/^sip://i;
              if($$preferences{$$pref{attribute}} =~ /^\+?\d+\@/) {
                $$preferences{$$pref{attribute}} =~ s/\@.*$//;
              }
            }
          }
        } elsif($$pref{attribute} eq 'cli') {
          if(defined $$preferences{$$pref{attribute}} and length $$preferences{$$pref{attribute}}) {
            $$preferences{$$pref{attribute}} =~ s/^sip://i;
            $$preferences{$$pref{attribute}} =~ s/\@.*$//
                if $$preferences{$$pref{attribute}} =~ /^\+?\d+\@/;
          }
        } elsif(!$c->stash->{ncos_levels} and ($$pref{attribute} eq 'ncos' or $$pref{attribute} eq 'adm_ncos')) {
          my $ncoslvl;
          return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_ncos_levels',
                                                              undef,
                                                              \$ncoslvl
                                                            );
          $c->stash->{ncos_levels} = $ncoslvl if eval { @$ncoslvl };
        }

        push @stashprefs,
             { key       => $$pref{attribute},
               value     => $$preferences{$$pref{attribute}},
               max_occur => $$pref{max_occur},
               error     => $c->session->{messages}{$$pref{attribute}}
                            ? $c->model('Provisioning')->localize($c->view($c->config->{view})->
                                                                    config->{VARIABLES}{site_config}{language},
                                                                  $c->session->{messages}{$$pref{attribute}})
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
            $$sdentry{destination} =~ s/^sip://i;
            $$sdentry{destination} =~ s/\@.*$//
                if $$sdentry{destination} =~ /^\+?\d+\@/;
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

    if(ref $c->session->{subscriber}{fax_preferences} eq 'HASH' and
       ref $c->session->{subscriber}{fax_preferences}{destinations} eq 'ARRAY')
    {
        for(@{$c->session->{subscriber}{fax_preferences}{destinations}}) {
            if($$_{destination} =~ /^\d+$/) {
                my $scc = $c->session->{subscriber}{cc};
                $$_{destination} = '+'.$$_{destination};
                $$_{destination} =~ s/^\+$scc/0/;
            }
        }
    }

    $c->stash->{show_faxpass} = $c->request->params->{show_faxpass};
    $c->stash->{edit_preferences} = $c->request->params->{edit_preferences};
    $c->stash->{edit_voicebox} = $c->request->params->{edit_voicebox};
    $c->stash->{edit_fax} = $c->request->params->{edit_fax};

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
    ## remove preferences that can't be changed
    delete $$preferences{prepaid};
    delete $$preferences{base_cli};
    delete $$preferences{extension};
    delete $$preferences{base_user};
    delete $$preferences{has_extension};

    ### blocklists ###

    my $block_in_mode = $c->request->params->{block_in_mode};
    if(defined $block_in_mode) {
        $$preferences{block_in_mode} = $block_in_mode eq 'whitelist' ? 1 : 0;
    }
    my $block_out_mode = $c->request->params->{block_out_mode};
    if(defined $block_out_mode) {
        $$preferences{block_out_mode} = $block_out_mode eq 'whitelist' ? 1 : 0;
    }

    $$preferences{block_in_clir} = $c->request->params->{block_in_clir} ? 1 : undef;

    my $adm_block_in_mode = $c->request->params->{adm_block_in_mode};
    if(defined $adm_block_in_mode) {
        $$preferences{adm_block_in_mode} = $adm_block_in_mode eq 'whitelist' ? 1 : 0;
    }
    my $adm_block_out_mode = $c->request->params->{adm_block_out_mode};
    if(defined $adm_block_out_mode) {
        $$preferences{adm_block_out_mode} = $adm_block_out_mode eq 'whitelist' ? 1 : 0;
    }

    $$preferences{adm_block_in_clir} = $c->request->params->{adm_block_in_clir} ? 1 : undef;

    if(defined $c->request->params->{ncos}) {
        if(length $c->request->params->{ncos}) {
            $$preferences{ncos} = $c->request->params->{ncos};
        } else {
            $$preferences{ncos} = undef;
        }
    }

    if(defined $c->request->params->{adm_ncos}) {
        if(length $c->request->params->{adm_ncos}) {
            $$preferences{adm_ncos} = $c->request->params->{adm_ncos};
        } else {
            $$preferences{adm_ncos} = undef;
        }
    }

    ### call forwarding ###
    foreach my $fwtype (qw(cfu cfb cft cfna)) {
        my $fw_target_select = $c->request->params->{$fwtype .'_target'} || 'disable';

        my $fw_target;
        if($fw_target_select eq 'sipuri') {
            $fw_target = $c->request->params->{$fwtype .'_sipuri'};

            # normalize, so we can do some checks.
            $fw_target =~ s/^sip://i;
            if($fw_target =~ /^\+?\d+\@[a-z0-9.-]+$/i) {
                $fw_target =~ s/\@.+$//;
            }

            if($fw_target =~ /^\+?\d+$/) {
                if($fw_target =~ /^\+[1-9][0-9]+$/) {
                    $fw_target = 'sip:'. $fw_target .'@'. $c->session->{subscriber}{domain};
                } elsif($fw_target =~ /^00[1-9][0-9]+$/) {
                    $fw_target =~ s/^00/+/;
                    $fw_target = 'sip:'. $fw_target .'@'. $c->session->{subscriber}{domain};
                } elsif($fw_target =~ /^0[1-9][0-9]+$/) {
                    $fw_target =~ s/^0/'+'.$c->session->{subscriber}{cc}/e;
                    $fw_target = 'sip:'. $fw_target .'@'. $c->session->{subscriber}{domain};
                } else {
                    $messages{$fwtype} = 'Client.Voip.MalformedNumber';
                    $fw_target = $c->request->params->{$fwtype .'_sipuri'};
                }
            } elsif($fw_target =~ /^[a-z0-9&=+\$,;?\/_.!~*'()-]+\@[a-z0-9.-]+$/i) {
                $fw_target = 'sip:'. lc $fw_target;
            } elsif($fw_target =~ /^[a-z0-9&=+\$,;?\/_.!~*'()-]+$/) {
                $fw_target = 'sip:'. lc($fw_target) .'@'. $c->session->{subscriber}{domain};
            } else {
                $messages{$fwtype} = 'Client.Voip.MalformedTarget';
                $fw_target = $c->request->params->{$fwtype .'_sipuri'};
            }
        } elsif($fw_target_select eq 'voicebox') {
            $fw_target = 'sip:vmu'.$c->session->{subscriber}{cc}.$c->session->{subscriber}{ac}.$c->session->{subscriber}{sn}.'@voicebox.local';
        } elsif($fw_target_select eq 'fax2mail') {
            $fw_target = 'sip:'.$c->session->{subscriber}{cc}.$c->session->{subscriber}{ac}.$c->session->{subscriber}{sn}.'@fax2mail.local';
        }
        $$preferences{$fwtype} = $fw_target;
    }

    $$preferences{ringtimeout} = undef;
    $$preferences{ringtimeout} = $c->request->params->{ringtimeout} || undef;
    unless(defined $$preferences{ringtimeout} and $$preferences{ringtimeout} =~ /^\d+$/
       and $$preferences{ringtimeout} < 301 and $$preferences{ringtimeout} > 4)
    {
        $messages{ringtimeout} = 'Client.Voip.MissingRingtimeout'
            if $$preferences{cft};
    }

    ### outgoing calls ###

    $$preferences{cli} = $c->request->params->{cli} or undef;
    if(defined $$preferences{cli} and $$preferences{cli} =~ /^\d+$/) {
        $$preferences{cli} = 'sip:'.$$preferences{cli}.'@'.$c->session->{subscriber}{domain};
    }

    $$preferences{clir} = $c->request->params->{clir} ? 1 : undef;

    $$preferences{cc} = $c->request->params->{cc} || undef;
    if(defined $$preferences{cc} and $$preferences{cc} !~ /^[1-9]\d*$/) {
        $messages{cc} = 'Client.Voip.MalformedCc';
    }
    $$preferences{ac} = $c->request->params->{ac} || undef;
    if(defined $$preferences{ac} and $$preferences{ac} !~ /^[1-9]\d*$/) {
        $messages{ac} = 'Client.Voip.MalformedAc';
    }
    $$preferences{svc_ac} = $c->request->params->{svc_ac} || undef;
    if(defined $$preferences{svc_ac} and $$preferences{svc_ac} !~ /^[1-9]\d*$/) {
        $messages{svc_ac} = 'Client.Voip.MalformedAc';
    }
    $$preferences{emerg_ac} = $c->request->params->{emerg_ac} || undef;
    if(defined $$preferences{emerg_ac} and $$preferences{emerg_ac} !~ /^[1-9]\d*$/) {
        $messages{emerg_ac} = 'Client.Voip.MalformedAc';
    }

    ### malicious call trace ###

    $$preferences{mct} = $c->request->params->{mct} ? 1 : undef;

    ### subscriber activation flag ###

    $$preferences{in_use} = $c->request->params->{in_use} ? 1 : undef;

    ### allowed IPs override ###

    $$preferences{ignore_allowed_ips} = $c->request->params->{ignore_allowed_ips} ? 1 : undef;

    ### preselection handling ###

    $$preferences{on_preselect} = $c->request->params->{on_preselect};

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
            if($add =~ /^[1-9\[]/) {
                $add =~ s/^/$c->session->{subscriber}{cc}.$c->session->{subscriber}{ac}/e;
            } elsif($add =~ /^0[^0]/) {
                $add =~ s/^0/$c->session->{subscriber}{cc}/e;
            }
            $add =~ s/^\+/00/;
            $add =~ s/^00+//;
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
            $del =~ s/^\+//;
            $del =~ s/^0/$c->session->{subscriber}{cc}/e;
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
            $act =~ s/^\+//;
            $act =~ s/^0/$c->session->{subscriber}{cc}/e;
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
            } else {
                $$sdentry{destination} =~ s/^sip://i;
                $$sdentry{destination} =~ s/\@.*$//
                    if $$sdentry{destination} =~ /^\+?\d+\@/;
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
        if ($add_destination =~ /^\d+$/) {
            $destination = 'sip:'. $add_destination .'@'. $c->session->{subscriber}{domain};
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
        if ($update_destination =~ /^\d+$/) {
            $destination = 'sip:'. $update_destination .'@'. $c->session->{subscriber}{domain};
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
            if($$entry{destination} =~ /^\d+$/) {
                my $scc = $c->session->{subscriber}{cc};
                $$entry{destination} = '+'.$$entry{destination};
                $$entry{destination} =~ s/^\+$scc/0/;
            }
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
    # this is also sent by the save link next to entries in edit mode
    my $add = $c->request->params->{list_add};
    if(defined $add) {
        my $checkresult;
        if($add =~ /^\d+$/) {
            if($add =~ /^\+[1-9][0-9]+$/) {
                $add =~ s/^\+//;
            } elsif($add =~ /^00[1-9][0-9]+$/) {
                $add =~ s/^00//;
            } elsif($add =~ /^0[1-9][0-9]+$/) {
                $add =~ s/^0/$c->session->{subscriber}{cc}/e;
            } else {
                $add = $c->session->{subscriber}{cc} . $c->session->{subscriber}{ac} . $add;
            }
          return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'check_E164_number', $add, \$checkresult);
        } else {
          return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'check_email', $add, \$checkresult);
        }
        unless($checkresult) {
            $messages{msgadd} = 'Client.Voip.MalformedFaxDestination';
            $c->session->{arefill}{destination} = $add;
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
        $$preferences{$list} = [ @$destlist, \%entry ];

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

Daniel Tiefnig <dtiefnig@sipwise.com>

=head1 COPYRIGHT

The subscriber controller is Copyright (c) 2007 Sipwise GmbH, Austria. All
rights reserved.

=cut

# ende gelaende
1;
