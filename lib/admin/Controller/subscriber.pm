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
            $c->stash->{pagination} = admin::Utils::paginate($c, $subscriber_list, $offset, $limit);
            $c->stash->{max_offset} = $#{$c->stash->{pagination}};
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
        # voicebox requires a number
        if(length $c->session->{subscriber}{sn}) {
          return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_subscriber_voicebox_preferences',
                                                              { username => $c->session->{subscriber}{username},
                                                                domain   => $c->session->{subscriber}{domain},
                                                              },
                                                              \$c->session->{subscriber}{voicebox_preferences}
                                                            );
        }
        my $regcon;
        return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_registered_contacts',
                                                            { username => $c->session->{subscriber}{username},
                                                              domain   => $c->session->{subscriber}{domain},
                                                            },
                                                            \$regcon
                                                          );

        $c->session->{subscriber}{registered_contacts} = $$regcon{result} if $$regcon{result};
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
        $c->stash->{domains} = $$domains{result};
    }

    my $db_prefs;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_preferences',
                                                        undef, \$db_prefs
                                                      );
    $c->session->{voip_preferences} = $$db_prefs{result};

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
            if($$preferences{$$pref{attribute}} =~ /voicebox\.local$/) {
              $$cftarget{voicebox} = 1;
            } else {
              $$cftarget{sipuri} = $$preferences{$$pref{attribute}};
              $$cftarget{sipuri} =~ s/^sip://i;
              if($$cftarget{sipuri} =~ /^\+?\d+\@/) {
                $$cftarget{sipuri} =~ s/\@.*$//;
              }
            }
          }
        } elsif($$pref{attribute} eq 'cli') {
          if(defined $$preferences{$$pref{attribute}} and length $$preferences{$$pref{attribute}}) {
            $$preferences{$$pref{attribute}} =~ s/^sip://i;
            $$preferences{$$pref{attribute}} =~ s/\@.*$//
                if $$preferences{$$pref{attribute}} =~ /^\+?\d+\@/;
          }
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

      # OMG
      # reorder preferences so "cftarget" appears just above "cfu" and friends
      foreach my $stashpref (@stashprefs) {
        if($$stashpref{key} eq 'cfu') {
          push @{$c->stash->{subscriber}{preferences_array}},
               { key       => 'cftarget',
                 value     => $cftarget,
                 max_occur => 1,
                 error     => $c->session->{messages}{cftarget}
                              ? $c->model('Provisioning')->localize($c->view($c->config->{view})->
                                                                      config->{VARIABLES}{site_config}{language},
                                                                    $c->session->{messages}{cftarget})
                              : undef,
               };
        }
        push @{$c->stash->{subscriber}{preferences_array}}, $stashpref;
      }
    }

    $c->stash->{show_pass} = $c->request->params->{show_pass};
    $c->stash->{show_webpass} = $c->request->params->{show_webpass};
    $c->stash->{edit_subscriber} = $c->request->params->{edit_subscriber}
        unless $is_new;
    $c->stash->{edit_preferences} = $c->request->params->{edit_preferences};
    $c->stash->{edit_voicebox} = $c->request->params->{edit_voicebox};

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
            $messages{number_cc} = 'Client.Voip.MalformedCc'
                unless $cc =~ /^[1-9][0-9]{0,2}$/;
            $messages{number_ac} = 'Client.Voip.MalformedAc'
                unless $ac =~ /^[1-9][0-9]{0,4}$/;
            $messages{number_sn} = 'Client.Voip.MalformedSn'
                unless $sn =~ /^[1-9][0-9]+$/;
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

    my $block_in_list = $c->request->params->{block_in_list};

    ### call forwarding ###

    my $fw_target_select = $c->request->params->{fw_target};
    unless($fw_target_select) {
        $messages{target} = 'Client.Voip.MalformedTargetClass';
    }
    my $fw_target;
    if($fw_target_select eq 'sipuri') {
        $fw_target = $c->request->params->{fw_sipuri};

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
                $messages{target} = 'Client.Voip.MalformedNumber';
                $fw_target = $c->request->params->{fw_sipuri};
            }
        } elsif($fw_target =~ /^[a-z0-9&=+\$,;?\/_.!~*'()-]+\@[a-z0-9.-]+$/i) {
            $fw_target = 'sip:'. lc $fw_target;
        } elsif($fw_target =~ /^[a-z0-9&=+\$,;?\/_.!~*'()-]+$/) {
            $fw_target = 'sip:'. lc($fw_target) .'@'. $c->session->{subscriber}{domain};
        } else {
            $messages{target} = 'Client.Voip.MalformedTarget';
            $fw_target = $c->request->params->{fw_sipuri};
        }
    } elsif($fw_target_select eq 'voicebox') {
        $fw_target = 'sip:vmu'.$c->session->{subscriber}{cc}.$c->session->{subscriber}{ac}.$c->session->{subscriber}{sn}.'@voicebox.local';
    } else {
        # wtf?
    }

    my $cfu = $c->request->params->{cfu};
    my $cfb = $c->request->params->{cfb};
    my $cft = $c->request->params->{cft};
    my $cfna = $c->request->params->{cfna};

    # clear all forwards
    $$preferences{cfu} = undef;
    $$preferences{cft} = undef;
    $$preferences{cfb} = undef;
    $$preferences{cfna} = undef;
    $$preferences{ringtimeout} = undef;

    unless(defined $cfu or defined $cfb or defined $cft or defined $cfna) {
        delete $messages{target} if exists $messages{target};
    } else {
        if(defined $cfu) {
            # forward unconditionally
            $$preferences{cfu} = $fw_target;
        } else {
            if(defined $cfb) {
                $$preferences{cfb} = $fw_target;
            }
            if(defined $cft) {
                $$preferences{cft} = $fw_target;
            }
            if(defined $cfna) {
                $$preferences{cfna} = $fw_target;
            }
        }
    }

    if(defined $$preferences{cft}) {
        $$preferences{ringtimeout} = $c->request->params->{ringtimeout};
        unless(defined $$preferences{ringtimeout} and $$preferences{ringtimeout} =~ /^\d+$/
           and $$preferences{ringtimeout} < 301 and $$preferences{ringtimeout} > 4)
        {
            $messages{ringtimeout} = 'Client.Voip.MissingRingtimeout';
        }
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
            $c->response->redirect("/subscriber/detail?subscriber_id=$subscriber_id#userprefs");
            return;

        }
    } else {
        $messages{preferr} = 'Client.Voip.InputErrorFound';
    }

    $c->session->{messages} = \%messages;
    $c->session->{restore_preferences_input} = $preferences;
    $c->response->redirect("/subscriber/detail?subscriber_id=$subscriber_id&edit_preferences=1#userprefs");
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
            $c->response->redirect("/subscriber/detail?subscriber_id=$subscriber_id#vboxprefs");
            return;
        }
    } else {
        $messages{vboxerr} = 'Client.Voip.InputErrorFound';
    }

    $c->session->{messages} = \%messages;
    $c->session->{restore_vboxprefs_input} = $vboxprefs;
    $c->response->redirect("/subscriber/detail?subscriber_id=$subscriber_id&edit_voicebox=1#vboxprefs");
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
                                              background => $bg ? '' : 'alt',
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
    $c->stash->{block_in_clir} = $$preferences{block_in_clir};

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
