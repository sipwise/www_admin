package admin::Controller::subscriber;

use strict;
use warnings;
use base 'Catalyst::Controller';
use admin::Utils;
use HTML::Entities;

my @WEEKDAYS = qw(Monday Tuesday Wednesday Thursday Friday Saturday Sunday);

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
        foreach my $sf (qw(username domain number uuid external_id)) {
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

    foreach my $sf (qw(username domain number uuid external_id)) {
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
    my ($preferences, $subscriber);

    unless($is_new) {
        my $subscriber_id = $c->request->params->{subscriber_id};
        return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_voip_account_subscriber_by_id',
                                                            { subscriber_id => $subscriber_id },
                                                            \$subscriber
                                                          );

        return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_subscriber_preferences',
                                                            { username => $$subscriber{username},
                                                              domain => $$subscriber{domain},
                                                            },
                                                            \$preferences
                                                          );

        my $regcon;
        return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_subscriber_registered_devices',
                                                            { username => $$subscriber{username},
                                                              domain   => $$subscriber{domain},
                                                            },
                                                            \$regcon
                                                          );
        $$subscriber{registered_contacts} = $regcon if eval { @$regcon };

        my $regpeer;
        return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_subscriber_registered_peer',
                                                            { username => $$subscriber{username},
                                                              domain   => $$subscriber{domain},
                                                            },
                                                            \$regpeer
                                                          );
        if(defined $$regpeer{last_registration}) {
            $$regpeer{contacts_short} = substr($$regpeer{contacts}, 0, 60) . '...';
            $$regpeer{contacts} =~ s/</\&lt;/g;
            $$regpeer{contacts} =~ s/>/\&gt;/g;
            $$regpeer{contacts_short} =~ s/</\&lt;/g;
            $$regpeer{contacts_short} =~ s/>/\&gt;/g;
            $$subscriber{registered_peer} = $regpeer;
        }
        
        eval { $$subscriber{alias_numbers} = [ sort @{$$subscriber{alias_numbers}} ] };
        $c->stash->{subscriber} = $subscriber;
        $c->stash->{subscriber}{subscriber_id} = $subscriber_id;
        $c->stash->{subscriber}{is_locked} = $c->model('Provisioning')->localize($c, $c->view($c->config->{view})->
                                                                                         config->{VARIABLES}{site_config}{language},
                                                                                 'Web.Subscriber.Lock'.$$preferences{lock})
            if $$preferences{lock};
        $c->stash->{subscriber}{lock} = ($$preferences{lock} or 'none');

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
        $c->stash->{subscriber}{selected_domain} = $c->session->{restore_subscriber_input}{selected_domain}
            if defined $c->session->{restore_subscriber_input}{selected_domain};
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
    my $subscriber;

    my $subscriber_id = $c->request->params->{subscriber_id};
    if($subscriber_id) {
        return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_voip_account_subscriber_by_id',
                                                            { subscriber_id => $subscriber_id },
                                                            \$subscriber
                                                          );
    } else {
        my $checkresult;
        $$subscriber{account_id} = $c->request->params->{account_id};

        $$subscriber{username} = $c->request->params->{username};
        return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'check_username',
                                                            { username => $$subscriber{username}}, \$checkresult
                                                          );
        $messages{username} = 'Client.Syntax.MalformedUsername' unless($checkresult);

        $$subscriber{domain} = $c->request->params->{domain};
        return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'check_domain',
                                                            { domain => $$subscriber{domain} }, \$checkresult
                                                          );
        $messages{domain} = 'Client.Syntax.MalformedDomain' unless($checkresult);
    }

    if(defined $c->request->params->{external_id}) {
        $settings{external_id} = $c->request->params->{external_id};
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
                                                            { username => $settings{webusername} }, \$checkresult
                                                          );
        $messages{webusername} = 'Client.Syntax.MalformedUsername' unless($checkresult);
    } else {
        $settings{webusername} = $$subscriber{username};
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
                                                            { cc => $cc }, \$checkresult
                                                          );
        $messages{number_cc} = 'Client.Voip.MalformedCc'
            unless $checkresult;
        return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'check_ac',
                                                            { ac => $ac }, \$checkresult
                                                          );
        $messages{number_ac} = 'Client.Voip.MalformedAc'
            unless $checkresult;
        return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'check_sn',
                                                            { sn => $sn }, \$checkresult
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
                                                 { id         => $$subscriber{account_id},
                                                   subscriber => { username => $$subscriber{username},
                                                                   domain   => $$subscriber{domain},
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
                return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_voip_account_subscriber',
                                                                    { id       => $$subscriber{account_id},
                                                                      username => $$subscriber{username},
                                                                      domain   => $$subscriber{domain},
                                                                    },
                                                                    \$subscriber
                                                                  );
                $c->response->redirect("/subscriber/detail?subscriber_id=". $$subscriber{subscriber_id});
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
        $c->session->{restore_subscriber_input}{username} = $$subscriber{username};
        $c->session->{restore_subscriber_input}{selected_domain} = $$subscriber{domain};
        $c->response->redirect("/subscriber/detail?account_id=". $$subscriber{account_id} ."&new=1");
    }
    return;
}

sub edit_aliases : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/subscriber_edit_aliases.tt';

    my %messages;
    my $subscriber;

    my $subscriber_id = $c->request->params->{subscriber_id};
    return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_voip_account_subscriber_by_id',
                                                        { subscriber_id => $subscriber_id },
                                                        \$subscriber
                                                      );
    return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_voip_account_subscriber',
                                                        { id       => $$subscriber{account_id},
                                                          username => $$subscriber{username},
                                                          domain   => $$subscriber{domain},
                                                        },
                                                        \$subscriber
                                                      );

    eval {
        $$subscriber{alias_numbers} =
            [ sort { $$a{cc}.$$a{ac}.$$a{sn} cmp $$b{cc}.$$b{ac}.$$b{sn} }
                   @{$$subscriber{alias_numbers}} ];
    };
    $c->stash->{subscriber} = $subscriber;
    $c->stash->{subscriber_id} = $subscriber_id;

    if(defined $c->session->{aliasadd}) {
        $c->stash->{aliasadd} = $c->session->{aliasadd};
        delete $c->session->{aliasadd};
    }

    return 1;
}

sub do_edit_aliases : Local {
    my ( $self, $c ) = @_;

    my %messages;
    my $subscriber;

    my $subscriber_id = $c->request->params->{subscriber_id};
    return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_voip_account_subscriber_by_id',
                                                        { subscriber_id => $subscriber_id },
                                                        \$subscriber
                                                      );
    my $acid = $$subscriber{account_id};
    return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_voip_account_subscriber',
                                                        { id       => $acid,
                                                          username => $$subscriber{username},
                                                          domain   => $$subscriber{domain},
                                                        },
                                                        \$subscriber
                                                      );

    # delete button next to entries in alias list
    if(    defined $c->request->params->{alias_del_cc}
       and defined $c->request->params->{alias_del_ac}
       and defined $c->request->params->{alias_del_sn} )
    {
        my $cc = $c->request->params->{alias_del_cc};
        my $ac = $c->request->params->{alias_del_ac};
        my $sn = $c->request->params->{alias_del_sn};
        my $aliaslist = $$subscriber{alias_numbers};
        if(defined $aliaslist) {
            $$subscriber{alias_numbers} = [ grep { $$_{cc} ne $cc or $$_{ac} ne $ac or $$_{sn} ne $sn } @$aliaslist ];
        }
    }

    # input text fields to add new entry to list
    if(    defined $c->request->params->{alias_add_cc}
       and defined $c->request->params->{alias_add_ac}
       and defined $c->request->params->{alias_add_sn} )
    {
        my $cc = $c->request->params->{alias_add_cc};
        my $ac = $c->request->params->{alias_add_ac};
        my $sn = $c->request->params->{alias_add_sn};
        my $checkresult;

        return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'check_cc',
                                                            { cc => $cc }, \$checkresult
                                                          );
        $messages{number_cc} = 'Client.Voip.MalformedCc'
            unless $checkresult;
        return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'check_ac',
                                                            { ac => $ac }, \$checkresult
                                                          );
        $messages{number_ac} = 'Client.Voip.MalformedAc'
            unless $checkresult;
        return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'check_sn',
                                                            { sn => $sn }, \$checkresult
                                                          );
        $messages{number_sn} = 'Client.Voip.MalformedSn'
            unless $checkresult;

        unless(keys %messages) {
            my $aliaslist = $$subscriber{alias_numbers};
            $aliaslist = [] unless defined $aliaslist;
            $$subscriber{alias_numbers} = [ @$aliaslist, { cc => $cc, ac => $ac, sn => $sn } ];
        } else {
            $c->session->{aliasadd} = { cc => $cc, ac => $ac, sn => $sn };
        }
    }

    unless(keys %messages) {
        $c->model('Provisioning')->call_prov( $c, 'billing', 'update_voip_account_subscriber',
                                              { id         => $acid,
                                                subscriber => { username      => $$subscriber{username},
                                                                domain        => $$subscriber{domain},
                                                                alias_numbers => $$subscriber{alias_numbers},
                                                              },
                                              },
                                              undef
                                            );
    } else {
        $messages{aliaserr} = 'Client.Voip.InputErrorFound';
    }

    $c->session->{messages} = \%messages;
    $c->response->redirect("/subscriber/edit_aliases?subscriber_id=$subscriber_id");

}

=head2 lock

Locks a subscriber.

=cut

sub lock : Local {
    my ( $self, $c ) = @_;

    my $subscriber;

    my $subscriber_id = $c->request->params->{subscriber_id};
    return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_voip_account_subscriber_by_id',
                                                        { subscriber_id => $subscriber_id },
                                                        \$subscriber
                                                      );

    my $lock = $c->request->params->{lock};
    $c->model('Provisioning')->call_prov( $c, 'billing', 'lock_voip_account_subscriber',
                                          { id       => $$subscriber{account_id},
                                            username => $$subscriber{username},
                                            domain   => $$subscriber{domain},
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
    my $subscriber;

    my $subscriber_id = $c->request->params->{subscriber_id};
    return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_voip_account_subscriber_by_id',
                                                        { subscriber_id => $subscriber_id },
                                                        \$subscriber
                                                      );

    if($c->model('Provisioning')->call_prov( $c, 'billing', 'terminate_voip_account_subscriber',
                                             { id       => $$subscriber{account_id},
                                               username => $$subscriber{username},
                                               domain   => $$subscriber{domain},
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

    my $subscriber;

    my $subscriber_id = $c->request->params->{subscriber_id};
    my $contact_id = $c->request->params->{contact_id};

    return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_voip_account_subscriber_by_id',
                                                        { subscriber_id => $subscriber_id },
                                                        \$subscriber
                                                      );

    if($c->model('Provisioning')->call_prov( $c, 'voip', 'delete_subscriber_registered_device',
                                             { username => $$subscriber{username},
                                               domain   => $$subscriber{domain},
                                               id       => $contact_id,
                                             },
                                             undef
                                           ))
    {
        $c->session->{messages}{contmsg} = 'Server.Voip.RemovedRegisteredContact';
        $c->response->redirect("/subscriber/detail?subscriber_id=$subscriber_id#activeregs");
	return;
    }

    $c->response->redirect("/subscriber/detail?subscriber_id=$subscriber_id");
}

sub add_permanent_contact : Local {
    my ( $self, $c ) = @_;

    my $subscriber;

    my $subscriber_id = $c->request->params->{subscriber_id};
    my $contact = $c->request->params->{contact};

    unless($contact =~ /^sip\:[a-zA-Z0-9\-\_\.\!\~\*\'\(\)\%\+]+\@[a-zA-Z0-9\-\.\[\]\:]+(\:\d{1,5})?$/) {
        $c->session->{messages}{conterr} = 'Client.Syntax.MalformedUri';
        $c->response->redirect("/subscriber/detail?subscriber_id=$subscriber_id#activeregs");
        return;
    }

    return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_voip_account_subscriber_by_id',
                                                        { subscriber_id => $subscriber_id },
                                                        \$subscriber
                                                      );

    if($c->model('Provisioning')->call_prov( $c, 'voip', 'create_subscriber_registered_device',
                                             { username => $$subscriber{username},
                                               domain   => $$subscriber{domain},
                                               contact  => $contact,
                                             },
                                             undef
                                           ))
    {
        $c->session->{messages}{contmsg} = 'Server.Voip.AddedRegisteredContact';
        $c->response->redirect("/subscriber/detail?subscriber_id=$subscriber_id#activeregs");
	return;
    }

    $c->response->redirect("/subscriber/detail?subscriber_id=$subscriber_id");
}

=head2 preferences

Display subscriber preferences.

=cut

sub preferences : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/subscriber_preferences.tt';

    my $subscriber;

    my $preferences;
    my $speed_dial_slots;
    my $cf_dsets;
    my $cf_tsets;
    my $cf_maps;
    my $trusted_sources;
    my $callthru_clis;

    my $subscriber_id = $c->request->params->{subscriber_id};
    return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_voip_account_subscriber_by_id',
                                                        { subscriber_id => $subscriber_id },
                                                        \$subscriber
                                                      );

    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_subscriber_preferences',
                                                        { username => $$subscriber{username},
                                                          domain   => $$subscriber{domain},
                                                        },
                                                        \$preferences
                                                      );

    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_subscriber_cf_maps',
                                                        { username => $$subscriber{username},
                                                          domain => $$subscriber{domain},
                                                        },
                                                        \$cf_maps,
                                                      );

    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_subscriber_cf_destination_sets',
                                                        { username => $$subscriber{username},
                                                          domain => $$subscriber{domain},
                                                        },
                                                        \$cf_dsets,
                                                      );

    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_subscriber_cf_time_sets',
                                                        { username => $$subscriber{username},
                                                          domain => $$subscriber{domain},
                                                        },
                                                        \$cf_tsets,
                                                      );
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_subscriber_trusted_sources',
                                                        { username => $$subscriber{username},
                                                          domain => $$subscriber{domain},
                                                        },
                                                        \$trusted_sources,
                                                      );
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_ccmap_entries',
                                                        { username => $$subscriber{username},
                                                          domain   => $$subscriber{domain},
                                                        },
                                                        \$callthru_clis
                                                      );
    # voicebox requires a number
    if(length $$subscriber{sn} && $c->config->{voicemail_features}) {
      return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_subscriber_voicebox_preferences',
                                                          { username => $$subscriber{username},
                                                            domain   => $$subscriber{domain},
                                                          },
                                                          \$$subscriber{voicebox_preferences}
                                                        );
    }

    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_speed_dial_slots',
                                                        { username => $$subscriber{username},
                                                          domain   => $$subscriber{domain},
                                                        },
                                                        \$speed_dial_slots
                                                      );

    if($c->config->{fax_features}) {
        return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_subscriber_fax_preferences',
                                                            { username => $$subscriber{username},
                                                              domain   => $$subscriber{domain},
                                                            },
                                                            \$$subscriber{fax_preferences}
                                                          );
    }

    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_subscriber_reminder',
                                                        { username => $$subscriber{username},
                                                          domain   => $$subscriber{domain},
                                                        },
                                                        \$$subscriber{reminder}
                                                      );

    $c->stash->{cf_dsets} = $cf_dsets;
    $c->stash->{cf_tsets} = $cf_tsets;
    $c->stash->{cf_maps} = $cf_maps;
    $c->stash->{callthru_clis} = $callthru_clis;
    $c->stash->{subscriber} = $subscriber;
    $c->stash->{subscriber}{subscriber_id} = $subscriber_id;

    $c->stash->{subscriber}{is_locked} = $c->model('Provisioning')->localize($c, $c->view($c->config->{view})->
        config->{VARIABLES}{site_config}{language},
        'Web.Subscriber.Lock'.$$preferences{lock})
    if $$preferences{lock};

    $c->stash->{trusted_sources} = $trusted_sources;

    my $db_prefs;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_preferences',
                                                        undef, \$db_prefs
                                                      );
    my $voip_preferences;
    $voip_preferences = [ grep { $$_{usr_pref} } @$db_prefs ] if eval { @$db_prefs };

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
    
    $c->stash->{tsrc_edit_id} = $c->request->params->{tsrc_edit_id};
    if(ref $c->session->{restore_trusted_source} eq 'HASH') {
        my $done = 0;

        for my $ts (@{$c->stash->{trusted_sources}}) {
            next if ($ts->{id} != $c->stash->{tsrc_edit_id} );

            for my $key (keys %{$c->session->{restore_trusted_source}}) {
                $ts->{$key} = $c->session->{restore_trusted_source}{$key};
            }
            $done++;
        }
        if (!$done) {
            for my $key (keys %{$c->session->{restore_trusted_source}}) {
                $c->stash->{$key} = $c->session->{restore_trusted_source}{$key};
            }
        }
        delete $c->session->{restore_trusted_source};
    }

    ### build preference array for TT ###

    if(ref $voip_preferences eq 'ARRAY') {

      my @stashprefs;

      foreach my $pref (@$voip_preferences) {

        # managed separately
        next if $$pref{preference} eq 'lock';

        if(!$c->stash->{ncos_levels} and ($$pref{preference} eq 'ncos' or $$pref{preference} eq 'adm_ncos')) {
          my $ncoslvl;
          return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_ncos_levels',
                                                              undef,
                                                              \$ncoslvl
                                                            );
          $c->stash->{ncos_levels} = $ncoslvl if eval { @$ncoslvl };
        } elsif(!$c->stash->{rewrite_rule_sets} and $$pref{preference} eq 'rewrite_rule_set') {
          my $rules;
          return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_rewrite_rule_sets',
                                                              undef,
                                                              \$rules
                                                            );
          $c->stash->{rewrite_rule_sets} = $rules if eval { @$rules };
        }
        elsif ($$pref{data_type} eq 'enum') {

            my $enum_options;
            return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_enum_options', 
                { preference_id => $$pref{id},
                  pref_type => 'usr', 
                }, 
                \$enum_options );

            $$preferences{$$pref{preference}} = { 
                selected => $$preferences{$$pref{preference}},
                options => $enum_options,
            } if eval { @$enum_options };
        }
        elsif ($$pref{preference} eq 'sound_set') {
            my $sound_sets;
            return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_sound_sets', 
                {},
                \$sound_sets );

            $$preferences{$$pref{preference}} = { 
                selected => $$preferences{$$pref{preference}},
                options => $sound_sets,
            } if eval { @$sound_sets };
        }

        push @stashprefs,
             { key         => $$pref{preference},
               data_type   => $$pref{data_type},
               value       => $$preferences{$$pref{preference}},
               max_occur   => $$pref{max_occur},
               description => encode_entities($$pref{description}),
               error       => $c->session->{messages}{$$pref{preference}}
                              ? $c->model('Provisioning')->localize($c, $c->view($c->config->{view})->
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
    $c->stash->{meditid} = $c->request->params->{meditid};
    # $c->stash->{tsrc_edit_id} = $c->request->params->{tsrc_edit_id};

    return 1;
}

sub update_preferences : Local {
    my ( $self, $c ) = @_;

    my %messages;
    my $subscriber;

    my $subscriber_id = $c->request->params->{subscriber_id};
    return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_voip_account_subscriber_by_id',
                                                        { subscriber_id => $subscriber_id },
                                                        \$subscriber
                                                      );
    my $preferences;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_subscriber_preferences',
                                                        { username => $$subscriber{username},
                                                          domain   => $$subscriber{domain},
                                                        },
                                                        \$preferences
                                                      );
    my $db_prefs;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_preferences',
                                                        undef, \$db_prefs
                                                      );

    foreach my $db_pref (eval { @$db_prefs }) {

        next unless $$db_pref{usr_pref};
        delete $$preferences{$$db_pref{preference}}, next
            if $$db_pref{read_only};

        for (qw/cli user_cli emergency_cli/) {
            next unless (defined $c->request->params->{$_} and $c->request->params->{$_} ne '');

            if ($$db_pref{preference} eq $_) {
                $$preferences{$_} = $c->request->params->{$_} or undef;
                my $checkresult;
                return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'check_sip_username', { sip_username => $$preferences{$_} }, \$checkresult);
                $messages{$_} = 'Client.Syntax.InvalidSipUsername'
                    unless $checkresult;
            }
        }

        if($$db_pref{preference} eq 'cc') {
            $$preferences{$$db_pref{preference}} = $c->request->params->{$$db_pref{preference}} || undef;
            if(defined $$preferences{$$db_pref{preference}}) {
                my $checkresult;
                return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'check_cc',
                                                                    { cc => $$preferences{$$db_pref{preference}} }, \$checkresult
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
                                                                    { ac => $$preferences{$$db_pref{preference}} }, \$checkresult
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
        } elsif($$db_pref{data_type} eq 'enum') {
            # zero length value means user chose to not set this preference
            $$preferences{$$db_pref{preference}} = (length($c->request->params->{$$db_pref{preference}}) > 0 )
                ?  $c->request->params->{$$db_pref{preference}}
                :  undef
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
                                                 { username => $$subscriber{username},
                                                   domain   => $$subscriber{domain},
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

sub update_callforward : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/subscriber_preferences.tt';

    my %cfmap;
    $cfmap{id} = $c->request->params->{map_id};
    $cfmap{destination_set_id} = (defined $c->request->params->{dest} && $c->request->params->{dest} != "0") ? $c->request->params->{dest} : undef;
    $cfmap{time_set_id} = (defined $c->request->params->{time} && $c->request->params->{time} != "0") ? $c->request->params->{time} : undef;
    $cfmap{type} = $c->request->params->{type};

    my $subscriber_id = $c->request->params->{subscriber_id};
    $c->stash->{subscriber_id} = $subscriber_id;

    my %messages;

    my $subscriber;
    return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_voip_account_subscriber_by_id',
                                                        { subscriber_id => $subscriber_id },
                                                        \$subscriber,
                                                      );
    $c->stash->{subscriber} = $subscriber;

    my $ret;
    unless(defined $cfmap{id}) {
      delete $cfmap{id};
      $ret = $c->model('Provisioning')->call_prov( $c, 'voip', 'create_subscriber_cf_map',
                                                        { username => $subscriber->{username},
                                                          domain => $subscriber->{domain},
                                                          data => \%cfmap,
                                                        },
                                                        undef,
                                                      );
    } else {
      $ret = $c->model('Provisioning')->call_prov( $c, 'voip', 'update_subscriber_cf_map',
                                                        { username => $subscriber->{username},
                                                          domain => $subscriber->{domain},
                                                          data => \%cfmap,
                                                        },
                                                        undef,
                                                      );
    }
    if($ret)
    {
      $messages{cfmsg} = 'Server.Voip.SavedSettings';
      $c->session->{messages} = \%messages;
      $c->response->redirect("/subscriber/preferences?subscriber_id=$subscriber_id#callforward");
    }
    else
    {
      $messages{cferr} = 'Client.Voip.InputErrorFound';
      $c->session->{messages} = \%messages;
      $c->response->redirect("/subscriber/preferences?subscriber_id=$subscriber_id&meditid=$cfmap{id}#callforward");
    }
}

sub delete_callforward : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/subscriber_preferences.tt';

    my $cfmid = $c->request->params->{map_id};

    my $subscriber_id = $c->request->params->{subscriber_id};
    $c->stash->{subscriber_id} = $subscriber_id;

    my %messages;

    my $subscriber;
    return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_voip_account_subscriber_by_id',
                                                        { subscriber_id => $subscriber_id },
                                                        \$subscriber,
                                                      );
    $c->stash->{subscriber} = $subscriber;

    if($c->model('Provisioning')->call_prov( $c, 'voip', 'delete_subscriber_cf_map',
                                                        { username => $subscriber->{username},
                                                          domain   => $subscriber->{domain},
                                                          id       => $cfmid,
                                                        },
                                                        undef,
                                                      ))
    {
      $messages{cfmsg} = 'Server.Voip.SavedSettings';
      $c->session->{messages} = \%messages;
      $c->response->redirect("/subscriber/preferences?subscriber_id=$subscriber_id#callforward");
    }
    else
    {
      $messages{cferr} = 'Client.Voip.InputErrorFound';
      $c->session->{messages} = \%messages;
      $c->response->redirect("/subscriber/preferences?subscriber_id=$subscriber_id#callforward");
    }
}

sub update_reminder : Local {
    my ( $self, $c ) = @_;

    my %messages;
    my $subscriber;

    my $subscriber_id = $c->request->params->{subscriber_id};
    return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_voip_account_subscriber_by_id',
                                                        { subscriber_id => $subscriber_id },
                                                        \$subscriber
                                                      );
    my $reminder;
    $$reminder{time} = $c->request->params->{time};
    $$reminder{recur} = $c->request->params->{recur} || 'never';

    ### save settings ###

    unless(keys %messages) {
        if($c->model('Provisioning')->call_prov( $c, 'voip', 'set_subscriber_reminder',
                                                 { username => $$subscriber{username},
                                                   domain   => $$subscriber{domain},
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
    my $subscriber;

    my $subscriber_id = $c->request->params->{subscriber_id};
    return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_voip_account_subscriber_by_id',
                                                        { subscriber_id => $subscriber_id },
                                                        \$subscriber
                                                      );
    my $vboxprefs;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_subscriber_voicebox_preferences',
                                                        { username => $$subscriber{username},
                                                          domain   => $$subscriber{domain},
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
                                                            { email => $$vboxprefs{email} }, \$checkresult
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
                                                 { username => $$subscriber{username},
                                                   domain => $$subscriber{domain},
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
    my $subscriber;
    return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_voip_account_subscriber_by_id',
                                                        { subscriber_id => $subscriber_id },
                                                        \$subscriber
                                                      );
    $c->stash->{subscriber} = $subscriber;
    $c->stash->{subscriber}{subscriber_id} = $subscriber_id;

    my @localized_months = ( "foo" );

    my $cts = $$subscriber{create_timestamp};
    if($cts =~ s/^(\d{4}-\d\d)-\d\d \d\d:\d\d:\d\d/$1/) {
        my ($cyear, $cmonth) = split /-/, $cts;
        my ($nyear, $nmonth) = (localtime)[5,4];
        $nyear += 1900;
        $nmonth++;

        for(1 .. 12) {
            push @localized_months,
                $c->model('Provisioning')->localize($c, $c->view($c->config->{view})->
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
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_subscriber_cdrs',
                                                        { username => $$subscriber{username},
                                                          domain   => $$subscriber{domain},
                                                          filter   => { start_date => $sdate,
                                                                        end_date   => $edate,
                                                                      }
                                                        },
                                                        \$calls
                                                      );

    my $account;
    return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_voip_account_by_id',
                                                        { id => $$subscriber{account_id} },
                                                        \$account
                                                      );
    my $bilprof = {};
    if(eval { defined $$account{billing_profile} }) {
        return 1 unless $c->model('Provisioning')->call_prov($c, 'billing', 'get_billing_profile',
                                                             { handle => $$account{billing_profile} },
                                                             \$bilprof
                                                            );
    }

    $c->stash->{cdr_list} = $calls;
    $c->stash->{call_list} = admin::Utils::prepare_call_list($c, $$subscriber{username}, $$subscriber{domain}, $calls, $listfilter, $bilprof);
    $c->stash->{subscriber}{list_filter} = $listfilter if defined $listfilter;

    undef $c->stash->{call_list} unless eval { @{$c->stash->{call_list}} };

    return;
}

sub sipstats : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/subscriber_sipstats.tt';

    my $subscriber_id = $c->request->params->{subscriber_id};
    my $subscriber;
    return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_voip_account_subscriber_by_id',
                                                        { subscriber_id => $subscriber_id },
                                                        \$subscriber
                                                      );
    $c->stash->{subscriber} = $subscriber;
    $c->stash->{subscriber}{subscriber_id} = $subscriber_id;

    my $calls;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_subscriber_sipstat_calls',
                                                        { username => $$subscriber{username},
                                                          domain   => $$subscriber{domain},
                                                        },
                                                        \$calls
                                                      );
    $c->stash->{calls} = $calls;

    return;
}

sub sipstats_pcap : Local {
    my ( $self, $c ) = @_;

    $c->stash->{template} = 'tt/subscriber_sipstats.tt';
    my $subscriber_id = $c->request->params->{subscriber_id};
    my $callid = $c->request->params->{callid};
    my $subscriber;
    return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_voip_account_subscriber_by_id',
                                                        { subscriber_id => $subscriber_id },
                                                        \$subscriber
                                                      );
    $c->stash->{subscriber} = $subscriber;
    $c->stash->{subscriber}{subscriber_id} = $subscriber_id;

    my $packets;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_subscriber_sipstat_packets',
                                                        { username => $$subscriber{username},
                                                          domain   => $$subscriber{domain},
                                                          callid   => $callid,
                                                        },
                                                        \$packets
                                                      );
    my $pcap = admin::Utils::generate_pcap($packets);
    my $filename = $callid . '.pcap';
    $c->stash->{current_view} = 'Plain';
    $c->stash->{content_type} = 'application/octet-stream';
    $c->stash->{content_disposition} = qq[attachment; filename="$filename"];
    $c->stash->{content} = eval { $pcap };
    return;
}

sub sipstats_callmap_png : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/subscriber_sipstats_call.tt';

    my $subscriber_id = $c->request->params->{subscriber_id};
    my $callid = $c->request->params->{callid};
    my $subscriber;
    return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_voip_account_subscriber_by_id',
                                                        { subscriber_id => $subscriber_id },
                                                        \$subscriber
                                                      );
    $c->stash->{callid} = $callid;
    $c->stash->{subscriber} = $subscriber;
    $c->stash->{subscriber}{subscriber_id} = $subscriber_id;

    my $calls;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_subscriber_sipstat_messages',
                                                        { username => $$subscriber{username},
                                                          domain   => $$subscriber{domain},
                                                          callid   => $callid,
                                                        },
                                                        \$calls
                                                      );
    my $png = admin::Utils::generate_callmap_png($c, $calls);
    my $filename = $callid . '.png';
    $c->stash->{current_view} = 'Plain';
    $c->stash->{content_type} = 'image/png';
    $c->stash->{content_disposition} = qq[attachment; filename="$filename"];
    $c->stash->{content} = eval { $png };

    return;
}

sub sipstats_callmap : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/subscriber_sipstats_call.tt';

    my $subscriber_id = $c->request->params->{subscriber_id};
    my $callid = $c->request->params->{callid};
    my $subscriber;
    return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_voip_account_subscriber_by_id',
                                                        { subscriber_id => $subscriber_id },
                                                        \$subscriber
                                                      );
    $c->stash->{callid} = $callid;
    $c->stash->{subscriber} = $subscriber;
    $c->stash->{subscriber}{subscriber_id} = $subscriber_id;

    my $calls;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_subscriber_sipstat_messages',
                                                        { username => $$subscriber{username},
                                                          domain   => $$subscriber{domain},
                                                          callid   => $callid,
                                                        },
                                                        \$calls
                                                      );
    $c->stash->{canvas} = admin::Utils::generate_callmap($c, $calls);

    return;
}

sub sipstats_packet : Local {
    my ( $self, $c ) = @_;
    #$c->stash->{template} = 'tt/subscriber_sipstats_call.tt';

    my $subscriber_id = $c->request->params->{subscriber_id};
    my $pkgid = $c->request->params->{pkgid};
    my $subscriber;
    return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_voip_account_subscriber_by_id',
                                                        { subscriber_id => $subscriber_id },
                                                        \$subscriber
                                                      );
    $c->stash->{subscriber} = $subscriber;
    $c->stash->{subscriber}{subscriber_id} = $subscriber_id;

    my $pkg;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_subscriber_sipstat_message',
                                                        { username => $$subscriber{username},
                                                          domain   => $$subscriber{domain},
                                                          packetid   => $pkgid,
                                                        },
                                                        \$pkg
                                                      );
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = 
      localtime($pkg->{timestamp});
    my $tstamp = sprintf("%04i-%02i-%02i %02i:%02i:%02i.%03i",
      $year+1900, $mon+1, $mday, $hour, $min, $sec, int(($pkg->{timestamp}-int($pkg->{timestamp}))*1000));
    $pkg->{payload} = encode_entities($pkg->{payload});
    $pkg->{payload} =~ s/\r//g;
    $pkg->{payload} =~ s/([^\n]{120})/$1<br\/>/g;
    $pkg->{payload} =~ s/^([^\n]+)\n/<b>$1<\/b>\n/;
    $pkg->{payload} = $tstamp.' ('.$pkg->{timestamp}.')<br/>'.
      $pkg->{src_ip}.':'.$pkg->{src_port}.' &rarr; '. $pkg->{dst_ip}.':'.$pkg->{dst_port}.'<br/><br/>'.
      $pkg->{payload};
    $pkg->{payload} =~ s/\n([a-zA-Z0-9\-_]+\:)/\n<b>$1<\/b>/g;
    $pkg->{payload} =~ s/\n/<br\/>/g;
    $c->stash->{current_view} = 'Plain';
    $c->stash->{content_type} = 'text/html';
    $c->stash->{content} = eval { $pkg->{payload} };

    return;
}

sub edit_cf : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/subscriber_callforward.tt';

    $c->stash->{seditid} = $c->request->params->{seditid};
    $c->stash->{teditid} = $c->request->params->{teditid};

    my %messages;

    my $subscriber_id = $c->request->params->{subscriber_id};
    $c->stash->{subscriber_id} = $subscriber_id;

    my $subscriber;
    return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_voip_account_subscriber_by_id',
                                                        { subscriber_id => $subscriber_id },
                                                        \$subscriber,
                                                      );
    $c->stash->{subscriber} = $subscriber;

    my $dsets;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_subscriber_cf_destination_sets',
                                                        { username => $subscriber->{username},
                                                          domain => $subscriber->{domain},
                                                        },
                                                        \$dsets,
                                                      );

    my $vbdom = $c->config->{voicebox_domain};
    my $fmdom = $c->config->{fax2mail_domain};
    my $confdom = $c->config->{conference_domain};

    foreach my $dset(@{$dsets})
    {
      foreach my $dest(@{$dset->{destinations}})
      {
        if($dest->{destination} =~ /\@$vbdom$/) {
          $dest->{destination} = 'voicebox';
        } elsif($dest->{destination} =~ /\@$fmdom$/) {
          $dest->{destination} = 'fax2mail';
        } elsif($dest->{destination} =~ /\@$confdom$/) {
          $dest->{destination} = 'conference';
        } elsif($dest->{destination} =~ /^callthrough\@app\.local$/) {
          $dest->{destination} = 'callthru';
	}
      }
    }

    $c->stash->{dsets} = $dsets;

    return 1;
}

sub edit_cf_saveset : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/subscriber_callforward.tt';

    my $dset_id = $c->request->params->{seditid};
    $c->stash->{seditid} = $dset_id;

    my $subscriber_id = $c->request->params->{subscriber_id};
    $c->stash->{subscriber_id} = $subscriber_id;

    my %messages;
    my %dset;

    $dset{name} = $c->request->params->{dsetname};
    $dset{id} = $dset_id;

    my $subscriber;
    return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_voip_account_subscriber_by_id',
                                                        { subscriber_id => $subscriber_id },
                                                        \$subscriber,
                                                      );
    $c->stash->{subscriber} = $subscriber;

    if($c->model('Provisioning')->call_prov( $c, 'voip', 'update_subscriber_cf_destination_set',
                                                        { username => $subscriber->{username},
                                                          domain => $subscriber->{domain},
                                                          data => \%dset,
                                                        },
                                                        undef,
                                                      ))
    {
      $messages{esetmsg} = 'Server.Voip.SavedSettings';
      $c->session->{messages} = \%messages;
      $c->response->redirect("/subscriber/edit_cf?subscriber_id=$subscriber_id");
    }
    else
    {
      $c->session->{messages} = \%messages;
      $messages{eseterr} = 'Client.Voip.InputErrorFound';
      $c->response->redirect("/subscriber/edit_cf?subscriber_id=$subscriber_id&seditid=$dset_id");
    }
}

sub edit_cf_delset : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/subscriber_callforward.tt';

    my $dset_id = $c->request->params->{seditid};

    my $subscriber_id = $c->request->params->{subscriber_id};
    $c->stash->{subscriber_id} = $subscriber_id;

    my %messages;

    my $subscriber;
    return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_voip_account_subscriber_by_id',
                                                        { subscriber_id => $subscriber_id },
                                                        \$subscriber,
                                                      );
    $c->stash->{subscriber} = $subscriber;

    if($c->model('Provisioning')->call_prov( $c, 'voip', 'delete_subscriber_cf_destination_set',
                                                        { username => $subscriber->{username},
                                                          domain   => $subscriber->{domain},
                                                          id       => $dset_id,
                                                        },
                                                        undef,
                                                      ))
    {
      $messages{esetmsg} = 'Server.Voip.SavedSettings';
    }
    else
    {
      $messages{eseterr} = 'Client.Voip.InputErrorFound';
    }
    $c->session->{messages} = \%messages;
    $c->response->redirect("/subscriber/edit_cf?subscriber_id=$subscriber_id");
}

sub edit_cf_createset : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/subscriber_callforward.tt';

    my $subscriber_id = $c->request->params->{subscriber_id};
    $c->stash->{subscriber_id} = $subscriber_id;
    
    my %messages;
    my %dset;

    $dset{name} = $c->request->params->{dsetname};

    my $subscriber;
    return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_voip_account_subscriber_by_id',
                                                        { subscriber_id => $subscriber_id },
                                                        \$subscriber,
                                                      );
    $c->stash->{subscriber} = $subscriber;

    if($c->model('Provisioning')->call_prov( $c, 'voip', 'create_subscriber_cf_destination_set',
                                                        { username => $subscriber->{username},
                                                          domain => $subscriber->{domain},
                                                          data => \%dset,
                                                        },
                                                        undef,
                                                      ))
    {
      $messages{esetmsg} = 'Server.Voip.SavedSettings';
    }
    else
    {
      $messages{eseterr} = 'Client.Voip.InputErrorFound';
    }
    $c->session->{messages} = \%messages;
    $c->response->redirect("/subscriber/edit_cf?subscriber_id=$subscriber_id");
}

sub edit_cf_savedst : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/subscriber_callforward.tt';

    my $fwtype = $c->request->params->{type};
    $c->stash->{type} = $fwtype;
    my $dset_id = $c->request->params->{seditid};
    my $dest_id = $c->request->params->{teditid};

    my $subscriber_id = $c->request->params->{subscriber_id};
    $c->stash->{subscriber_id} = $subscriber_id;

    my $subscriber;
    return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_voip_account_subscriber_by_id',
                                                        { subscriber_id => $subscriber_id },
                                                        \$subscriber,
                                                      );
    $c->stash->{subscriber} = $subscriber;

    my %messages;
    my %dest;

    my $vbdom = $c->config->{voicebox_domain};
    my $fmdom = $c->config->{fax2mail_domain};
    my $confdom = $c->config->{conference_domain};

    my $fw_timeout = $c->request->params->{'dest_timeout'} || 300;
    my $fw_target_select = $c->request->params->{'dest_target'} || 'disable';
    my $fw_target;

    my ($check_sip_uri, $check_sip_username);
    if($fw_target_select eq 'sipuri') {
        $fw_target = $c->request->params->{'dest_sipuri'};

        return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'check_sip_uri', { sip_uri => $fw_target }, \$check_sip_uri);
        return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'check_sip_username', { sip_username => $fw_target }, \$check_sip_username);

        $messages{edesterr} = 'Client.Voip.MalformedTarget'
            unless ($check_sip_uri or $check_sip_username);

    } elsif($fw_target_select eq 'voicebox') {
      $fw_target = 'sip:vmu'.$$subscriber{cc}.$$subscriber{ac}.$$subscriber{sn}."\@$vbdom";
    } elsif($fw_target_select eq 'fax2mail') {
      $fw_target = 'sip:'.$$subscriber{cc}.$$subscriber{ac}.$$subscriber{sn}."\@$fmdom";
    } elsif($fw_target_select eq 'conference') {
      $fw_target = 'sip:conf='.$$subscriber{cc}.$$subscriber{ac}.$$subscriber{sn}."\@$confdom";
    } elsif($fw_target_select eq 'callthru') {
      $fw_target = 'sip:callthrough@app.local';
    }

    my $prio = $c->request->params->{priority};

    if(keys %messages) {
      $messages{preferr} = 'Client.Voip.InputErrorFound';
      $c->session->{messages} = \%messages;
      $c->response->redirect("/subscriber/edit_cf?subscriber_id=$subscriber_id&teditid=$dest_id");
      return;
    }

    $dest{destination} = $fw_target;
    $dest{priority} = $prio;
    $dest{timeout} = $fw_timeout;

    if($dest_id)
    {
      # update
      $dest{id} = $dest_id;
      if($c->model('Provisioning')->call_prov( $c, 'voip', 'update_subscriber_cf_destination',
                                                          { username => $subscriber->{username},
                                                            domain   => $subscriber->{domain},
                                                            set_id   => $dset_id,
                                                            data     => \%dest,
                                                          },
                                                          undef,
                                                        ))
      {
        $messages{edestmsg} = 'Server.Voip.SavedSettings';
        $c->session->{messages} = \%messages;
        $c->response->redirect("/subscriber/edit_cf?subscriber_id=$subscriber_id");
      }
      else
      {
        $c->session->{messages} = \%messages;
        $messages{edesterr} = 'Client.Voip.InputErrorFound';
        $c->response->redirect("/subscriber/edit_cf?subscriber_id=$subscriber_id&teditid=$dest_id");
      }
    }
    else
    {
      # create
      if($c->model('Provisioning')->call_prov( $c, 'voip', 'create_subscriber_cf_destination',
                                                          { username => $subscriber->{username},
                                                            domain   => $subscriber->{domain},
                                                            set_id   => $dset_id,
                                                            data     => \%dest,
                                                          },
                                                          undef,
                                                        ))
      {
        $messages{edestmsg} = 'Server.Voip.SavedSettings';
        $c->session->{messages} = \%messages;
        $c->response->redirect("/subscriber/edit_cf?subscriber_id=$subscriber_id");
      }
      else
      {
        $c->session->{messages} = \%messages;
        $messages{edesterr} = 'Client.Voip.InputErrorFound';
        $c->response->redirect("/subscriber/edit_cf?subscriber_id=$subscriber_id&seditid=$dset_id#dset$dset_id");
      }
    }
}

sub edit_cf_deldest : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/subscriber_callforward.tt';

    my $dset_id = $c->request->params->{seditid};
    my $dest_id = $c->request->params->{teditid};

    my $subscriber_id = $c->request->params->{subscriber_id};
    $c->stash->{subscriber_id} = $subscriber_id;

    my $subscriber;
    return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_voip_account_subscriber_by_id',
                                                        { subscriber_id => $subscriber_id },
                                                        \$subscriber,
                                                      );
    $c->stash->{subscriber} = $subscriber;

    my %messages;

    if($c->model('Provisioning')->call_prov( $c, 'voip', 'delete_subscriber_cf_destination',
                                                        { username => $subscriber->{username},
                                                          domain   => $subscriber->{domain},
                                                          set_id   => $dset_id,
                                                          id       => $dest_id,
                                                        },
                                                        undef,
                                                      ))
    {
      $messages{esetmsg} = 'Server.Voip.SavedSettings';
    }
    else
    {
      $messages{eseterr} = 'Client.Voip.InputErrorFound';
    }
    $c->session->{messages} = \%messages;
    $c->response->redirect("/subscriber/edit_cf?subscriber_id=$subscriber_id");
}

sub edit_cf_updatepriority : Local {
    my ( $self, $c ) = @_;

    my %messages;
    my %settings;

    my $prio = 0;

    my $dests = $c->request->params->{'dest[]'};

    foreach my $dest_id(@$dests)
    {
       my $dest = undef;
       $c->model('Provisioning')->call_prov( $c, 'voip', 'update_subscriber_cf_destination_by_id',
           { id   => $dest_id,
             data => {
               priority => $prio,
             },
           },
           undef
        );
        $prio++;
    }

    $c->session->{messages} = \%messages;
    $c->response->redirect("/");
    return;
}

sub edit_cf_times : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/subscriber_callforward_times.tt';

    my %messages;

    my $subscriber_id = $c->request->params->{subscriber_id};
    $c->stash->{subscriber_id} = $subscriber_id;
    return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_voip_account_subscriber_by_id',
                                                        { subscriber_id => $subscriber_id },
                                                        \$c->session->{subscriber}
                                                      );
    $c->stash->{subscriber} = $c->session->{subscriber};

    my $tsets;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_subscriber_cf_time_sets',
                                                        { username => $c->session->{subscriber}{username},
                                                          domain => $c->session->{subscriber}{domain},
                                                        },
                                                        \$tsets,
                                                      );

    foreach my $tset (@{$tsets}) {
      foreach my $per (@{$tset->{periods}}) {
        $self->period_expand($per);
      }
    }

    $c->stash->{tsets} = $tsets;
    $c->stash->{seditid} = $c->request->params->{seditid};
    $c->stash->{peditid} = $c->request->params->{peditid};

    return 1;
}

sub edit_cf_time_saveset : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/subscriber_callforward_times.tt';

    my $tset_id = $c->request->params->{seditid};
    $c->stash->{seditid} = $tset_id;

    my $subscriber_id = $c->request->params->{subscriber_id};
    $c->stash->{subscriber_id} = $subscriber_id;

    my %messages;
    my %tset;

    $tset{name} = $c->request->params->{tsetname};
    $tset{id} = $tset_id;

    my $subscriber;
    return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_voip_account_subscriber_by_id',
                                                        { subscriber_id => $subscriber_id },
                                                        \$subscriber,
                                                      );
    $c->stash->{subscriber} = $subscriber;

    if($c->model('Provisioning')->call_prov( $c, 'voip', 'update_subscriber_cf_time_set',
                                                        { username => $subscriber->{username},
                                                          domain => $subscriber->{domain},
                                                          data => \%tset,
                                                        },
                                                        undef,
                                                      ))
    {
      $messages{esetmsg} = 'Server.Voip.SavedSettings';
      $c->session->{messages} = \%messages;
      $c->response->redirect("/subscriber/edit_cf_times?subscriber_id=$subscriber_id");
    }
    else
    {
      $c->session->{messages} = \%messages;
      $messages{eseterr} = 'Client.Voip.InputErrorFound';
      $c->response->redirect("/subscriber/edit_cf_times?subscriber_id=$subscriber_id&seditid=$tset_id");
    }
}

sub edit_cf_time_delset : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/subscriber_callforward_times.tt';

    my $tset_id = $c->request->params->{seditid};

    my $subscriber_id = $c->request->params->{subscriber_id};
    $c->stash->{subscriber_id} = $subscriber_id;

    my %messages;

    my $subscriber;
    return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_voip_account_subscriber_by_id',
                                                        { subscriber_id => $subscriber_id },
                                                        \$subscriber,
                                                      );
    $c->stash->{subscriber} = $subscriber;

    if($c->model('Provisioning')->call_prov( $c, 'voip', 'delete_subscriber_cf_time_set',
                                                        { username => $subscriber->{username},
                                                          domain   => $subscriber->{domain},
                                                          id       => $tset_id,
                                                        },
                                                        undef,
                                                      ))
    {
      $messages{esetmsg} = 'Server.Voip.SavedSettings';
    }
    else
    {
      $messages{eseterr} = 'Client.Voip.InputErrorFound';
    }
    $c->session->{messages} = \%messages;
    $c->response->redirect("/subscriber/edit_cf_times?subscriber_id=$subscriber_id");
}

sub edit_cf_times_createset : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/subscriber_callforward_times.tt';

    my $subscriber_id = $c->request->params->{subscriber_id};
    $c->stash->{subscriber_id} = $subscriber_id;
    
    my %messages;
    my %tset;

    $tset{name} = $c->request->params->{tsetname};

    my $subscriber;
    return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_voip_account_subscriber_by_id',
                                                        { subscriber_id => $subscriber_id },
                                                        \$subscriber,
                                                      );
    $c->stash->{subscriber} = $subscriber;

    if($c->model('Provisioning')->call_prov( $c, 'voip', 'create_subscriber_cf_time_set',
                                                        { username => $subscriber->{username},
                                                          domain => $subscriber->{domain},
                                                          data => \%tset,
                                                        },
                                                        undef,
                                                      ))
    {
      $messages{esetmsg} = 'Server.Voip.SavedSettings';
    }
    else
    {
      $messages{eseterr} = 'Client.Voip.InputErrorFound';
    }
    $c->session->{messages} = \%messages;
    $c->response->redirect("/subscriber/edit_cf_times?subscriber_id=$subscriber_id");
}

sub edit_cf_times_saveperiod : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/subscriber_callforward_times.tt';

    my $subscriber_id = $c->request->params->{subscriber_id};
    $c->stash->{subscriber_id} = $subscriber_id;
    my $tset_id = $c->request->params->{seditid};
    $c->stash->{seditid} = $tset_id;
    my $period_id = $c->request->params->{peditid};
    $c->stash->{peditid} = $period_id;
    
    my %messages;
    my %period;

    $period{year} = $c->request->params->{year};
    $period{from_year} = $c->request->params->{from_year};
    $period{to_year} = $c->request->params->{to_year};
    $period{month} = $c->request->params->{month};
    $period{from_month} = $c->request->params->{from_month};
    $period{to_month} = $c->request->params->{to_month};
    $period{mday} = $c->request->params->{mday};
    $period{from_mday} = $c->request->params->{from_mday};
    $period{to_mday} = $c->request->params->{to_mday};
    $period{wday} = $c->request->params->{wday};
    $period{from_wday} = $c->request->params->{from_wday};
    $period{to_wday} = $c->request->params->{to_wday};
    $period{hour} = $c->request->params->{hour};
    $period{from_hour} = $c->request->params->{from_hour};
    $period{to_hour} = $c->request->params->{to_hour};
    $period{minute} = $c->request->params->{minute};
    $period{from_minute} = $c->request->params->{from_minute};
    $period{to_minute} = $c->request->params->{to_minute};

    $self->period_collapse(\%period);

    $period{id} = $period_id if(defined $period_id);

    my $subscriber;
    return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_voip_account_subscriber_by_id',
                                                        { subscriber_id => $subscriber_id },
                                                        \$subscriber,
                                                      );
    $c->stash->{subscriber} = $subscriber;

    my $ret;
    unless(defined $period_id) 
    {
      $ret = $c->model('Provisioning')->call_prov( $c, 'voip', 'create_subscriber_cf_time_period',
                                                        { username => $subscriber->{username},
                                                          domain   => $subscriber->{domain},
                                                          set_id   => $tset_id,
                                                          data     => \%period,
                                                        },
                                                        undef,
                                                      );
    } 
    else 
    {
      $ret = $c->model('Provisioning')->call_prov( $c, 'voip', 'update_subscriber_cf_time_period',
                                                        { username => $subscriber->{username},
                                                          domain   => $subscriber->{domain},
                                                          set_id   => $tset_id,
                                                          data     => \%period,
                                                        },
                                                        undef,
                                                      );
    }

    if($ret)
    {
      $messages{esetmsg} = 'Server.Voip.SavedSettings';
    }
    else
    {
      $messages{eseterr} = 'Client.Voip.InputErrorFound';
    }
    $c->session->{messages} = \%messages;
    $c->response->redirect("/subscriber/edit_cf_times?subscriber_id=$subscriber_id#".$tset_id."set");
}

sub period_collapse : Private {
    my ($self, $period) = @_;

    if(defined $period->{year}) {
      # nothing to be done 
    }
    elsif(defined $period->{from_year} && defined $period->{to_year}) {
      if(int($period->{from_year}) > int($period->{to_year})) {
        return -1;
      }
      $period->{year} = $period->{from_year} . "-" . $period->{to_year};
    }
    else {
      # skip if incomplete
      delete $period->{year};
    }
    delete $period->{from_year};
    delete $period->{to_year};

    if(defined $period->{month}) {
      # nothing to be done 
    }
    elsif(defined $period->{from_month} && defined $period->{to_month}) {
      $period->{month} = $period->{from_month} . "-" . $period->{to_month};
    }
    else {
      # skip if incomplete
      delete $period->{month};
    }
    delete $period->{from_month};
    delete $period->{to_month};

    if(defined $period->{mday}) {
      # nothing to be done 
    }
    elsif(defined $period->{from_mday} && defined $period->{to_mday}) {
      $period->{mday} = $period->{from_mday} . "-" . $period->{to_mday};
    }
    else {
      # skip if incomplete
      delete $period->{mday};
    }
    delete $period->{from_mday};
    delete $period->{to_mday};

    if(defined $period->{wday}) {
      # nothing to be done 
    }
    elsif(defined $period->{from_wday} && defined $period->{to_wday}) {
      $period->{wday} = $period->{from_wday} . "-" . $period->{to_wday};
    }
    else {
      # skip if incomplete
      delete $period->{wday};
    }
    delete $period->{from_wday};
    delete $period->{to_wday};

    if(defined $period->{hour}) {
      # nothing to be done 
    }
    elsif(defined $period->{from_hour} && defined $period->{to_hour}) {
      $period->{hour} = $period->{from_hour} . "-" . $period->{to_hour};
    }
    else {
      # skip if incomplete
      delete $period->{hour};
    }
    delete $period->{from_hour};
    delete $period->{to_hour};

    if(defined $period->{minute}) {
      # nothing to be done 
    }
    elsif(defined $period->{from_minute} && defined $period->{to_minute}) {
      $period->{minute} = $period->{from_minute} . "-" . $period->{to_minute};
    }
    else {
      # skip if incomplete
      delete $period->{minute};
    }
    delete $period->{from_minute};
    delete $period->{to_minute};

    return 0;
}

sub period_expand : Private {
    my ($self, $period) = @_;

    if(defined $period->{year} && $period->{year} =~ /^\d+$/) {
      # nothing to be done 
    }
    elsif(defined $period->{year} && $period->{year} =~ /^(\d+)\-(\d+)$/) {
      $period->{from_year} = $1;
      $period->{to_year} = $2;
      delete $period->{year};
    }
    else {
      # skip if incomplete
      delete $period->{year};
    }

    if(defined $period->{month} && $period->{month} =~ /^\d+$/) {
      # nothing to be done 
    }
    elsif(defined $period->{month} && $period->{month} =~ /^(\d+)\-(\d+)$/) {
      $period->{from_month} = $1;
      $period->{to_month} = $2;
      delete $period->{month};
    }
    else {
      # skip if incomplete
      delete $period->{month};
    }

    if(defined $period->{mday} && $period->{mday} =~ /^\d+$/) {
      # nothing to be done 
    }
    elsif(defined $period->{mday} && $period->{mday} =~ /^(\d+)\-(\d+)$/) {
      $period->{from_mday} = $1;
      $period->{to_mday} = $2;
      delete $period->{mday};
    }
    else {
      # skip if incomplete
      delete $period->{mday};
    }

    if(defined $period->{wday} && $period->{wday} =~ /^\d+$/) {
      # nothing to be done 
    }
    elsif(defined $period->{wday} && $period->{wday} =~ /^(\d+)\-(\d+)$/) {
      $period->{from_wday} = $1;
      $period->{to_wday} = $2;
      delete $period->{wday};
    }
    else {
      # skip if incomplete
      delete $period->{wday};
    }

    if(defined $period->{hour} && $period->{hour} =~ /^\d+$/) {
      # nothing to be done 
    }
    elsif(defined $period->{hour} && $period->{hour} =~ /^(\d+)\-(\d+)$/) {
      $period->{from_hour} = $1;
      $period->{to_hour} = $2;
      delete $period->{hour};
    }
    else {
      # skip if incomplete
      delete $period->{hour};
    }

    if(defined $period->{minute} && $period->{minute} =~ /^\d+$/) {
      # nothing to be done 
    }
    elsif(defined $period->{minute} && $period->{minute} =~ /^(\d+)\-(\d+)$/) {
      $period->{from_minute} = $1;
      $period->{to_minute} = $2;
      delete $period->{minute};
    }
    else {
      # skip if incomplete
      delete $period->{minute};
    }

    return 0;
}

sub edit_cf_time_delperiod : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/subscriber_callforward_times.tt';

    my $period_id = $c->request->params->{peditid};
    my $tset_id = $c->request->params->{seditid};

    my $subscriber_id = $c->request->params->{subscriber_id};
    $c->stash->{subscriber_id} = $subscriber_id;

    my %messages;

    my $subscriber;
    return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_voip_account_subscriber_by_id',
                                                        { subscriber_id => $subscriber_id },
                                                        \$subscriber,
                                                      );
    $c->stash->{subscriber} = $subscriber;

    if($c->model('Provisioning')->call_prov( $c, 'voip', 'delete_subscriber_cf_time_period',
                                                        { username => $subscriber->{username},
                                                          domain => $subscriber->{domain},
                                                          set_id   => $tset_id,
                                                          id       => $period_id,
                                                        },
                                                        undef,
                                                      ))
    {
      $messages{esetmsg} = 'Server.Voip.SavedSettings';
    }
    else
    {
      $messages{eseterr} = 'Client.Voip.InputErrorFound';
    }
    $c->session->{messages} = \%messages;
    $c->response->redirect("/subscriber/edit_cf_times?subscriber_id=$subscriber_id#".$tset_id."set");
}

sub save_trusted_source : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/subscriber_preferences.tt';
    
    my %ts;
    my $tsrc_id = $c->request->params->{tsrc_edit_id} || 0;
    
    for ('src_ip', 'protocol', 'from_pattern') {
        $ts{$_} = $c->request->params->{$_};
        $ts{$_} =~ s/^\s+//; 
        $ts{$_} =~ s/\s+$//; 
    }

    my ( %messages, $checkresult );
    $c->model('Provisioning')->call_prov( $c, 'voip', 'check_ip', { ip => $ts{src_ip} }, \$checkresult);
    $messages{src_ip_err} = 'Client.Syntax.MalformedIP' unless $checkresult;

    $c->model('Provisioning')->call_prov( $c, 'voip', 'check_sip_transport_protocol', { protocol => $ts{protocol} }, \$checkresult);
    $messages{protocol_err} = 'Client.Syntax.UnknownProtocol' unless $checkresult;

    if (length $ts{from_pattern}) { # allow empty sipuri
        unless ($c->model('Provisioning')->call_prov( $c, 'voip', 'check_sip_uri_pattern', { pattern => $ts{from_pattern} }, \$checkresult)) {
            $messages{from_pattern_err} = 'Client.Syntax.MalformedUri';
            $c->flash->{from_pattern_err_detail} = $c->session->{prov_error_object} if ($c->session->{prov_error_object});
        }
    }
    else {
         $ts{from_pattern} = undef;
    }

    my $subscriber;
    return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_voip_account_subscriber_by_id',
        { subscriber_id => $c->request->params->{subscriber_id} },
        \$subscriber
    );
    
    # restore action
    if (keys %messages) {
        $c->session->{messages} = \%messages;
        $c->session->{restore_trusted_source} = { 
            src_ip => $c->request->params->{src_ip},
            protocol => $c->request->params->{protocol},
            from_pattern => $c->request->params->{from_pattern},
        };
        if (defined $tsrc_id && $tsrc_id != 0) {
            $c->response->redirect( '/subscriber/preferences?subscriber_id='. $subscriber->{subscriber_id} .'&tsrc_edit_id='. $tsrc_id .'#trusted_sources')
        }
        else {
            $c->response->redirect('/subscriber/preferences?subscriber_id=' . $subscriber->{subscriber_id} . '#trusted_sources');
        }
        $c->detach;
    } 

    my $ret;
    if (defined $tsrc_id && $tsrc_id != 0) {
        $ret = $c->model('Provisioning')->call_prov( $c, 'voip', 'update_subscriber_trusted_source',
            { username => $subscriber->{username},
              domain => $subscriber->{domain},
              id => $tsrc_id, 
              data => \%ts,
            },
            undef,
        );
    }
    else {
        $ret = $c->model('Provisioning')->call_prov( $c, 'voip', 'create_subscriber_trusted_source',
            { username => $subscriber->{username},
              domain => $subscriber->{domain},
              data => \%ts,
            },
            undef,
        );
    }
    
    if ($ret) {
        $messages{tsrc_msg} = 'Server.Voip.SavedSettings';
    }
    else {
        $messages{tsrc_err} = 'Client.Voip.InputErrorFound';
    }
    
    $c->response->redirect('/subscriber/preferences?subscriber_id=' . $subscriber->{subscriber_id} . '#trusted_sources');
}

sub delete_trusted_source : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/subscriber_preferences.tt';
   
    $c->stash->{subscriber_id} = $c->request->params->{subscriber_id};
    
    my $subscriber;
    return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_voip_account_subscriber_by_id',
        { subscriber_id => $c->stash->{subscriber_id} },
        \$subscriber
    );
    
    my %messages;
    if (! $c->model('Provisioning')->call_prov( 
        $c, 'voip', 'delete_subscriber_trusted_source',
        { username => $subscriber->{username},
          domain => $subscriber->{domain},
          id => $c->request->params->{tsrc_id}, 
        },
        undef ))
    {
        $messages{tsrc_err} = 'Client.Voip.InputErrorFound';
    }

    $c->session->{messages} = \%messages;
    $c->response->redirect('/subscriber/preferences?subscriber_id=' . $c->stash->{subscriber_id} . '#trusted_sources');
}

sub edit_list : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/subscriber_edit_list.tt';

    my %messages;

    my $subscriber_id = $c->request->params->{subscriber_id};
    my $subscriber;
    return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_voip_account_subscriber_by_id',
                                                        { subscriber_id => $subscriber_id },
                                                        \$subscriber
                                                      );
    my $preferences;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_subscriber_preferences',
                                                        { username => $subscriber->{username},
                                                          domain => $subscriber->{domain},
                                                        },
                                                        \$preferences
                                                      );
    my $list = $c->request->params->{list_name};

    if(defined $$preferences{$list}) {
        my $block_list = ref $$preferences{$list} ? $$preferences{$list} : [ $$preferences{$list} ];

        my @block_list_to_sort;
        foreach my $blockentry (@$block_list) {
            my $active = $blockentry =~ s/^#// ? 0 : 1;
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

    $c->stash->{subscriber} = $subscriber;
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
    $c->stash->{template} = 'tt/subscriber_edit_list.tt';

    my %messages;
    my $subscriber;

    my $subscriber_id = $c->request->params->{subscriber_id};
    return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_voip_account_subscriber_by_id',
                                                        { subscriber_id => $subscriber_id },
                                                        \$subscriber
                                                      );
    my $preferences;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_subscriber_preferences',
                                                        { username => $$subscriber{username},
                                                          domain   => $$subscriber{domain},
                                                        },
                                                        \$preferences
                                                      );
    my $list = $c->request->params->{list_name};

    my $add = $c->request->params->{block_add};
    my $del = $c->request->params->{block_del};
    my $act = $c->request->params->{block_act};

    if (defined $add) { # input text field to add new entry to block list
        my $checkresult;
        $add =~ s/ //g;
        return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'check_sip_username_shell_pattern', { pattern => $add }, \$checkresult);

        if ($checkresult) {
            my $blocklist = $$preferences{$list};
            $blocklist = [] unless defined $blocklist;
            $blocklist = [ $blocklist ] unless ref $blocklist;
            $$preferences{$list} = [ @$blocklist, $add ];
        }
        else {
            $messages{msgadd} = 'Client.Syntax.InvalidSipUsernamePattern';
            $c->session->{blockaddtxt} = $add;
        }
    }
    elsif (defined $del) { # delete link next to entries in block list
        my $blocklist = $$preferences{$list};
        if (defined $blocklist) {
            $blocklist = [ $blocklist ] unless ref $blocklist;
            if($c->request->params->{block_stat}) {
                $$preferences{$list} = [ grep { $_ ne $del } @$blocklist ];
            } else {
                $$preferences{$list} = [ grep { $_ ne '#'.$del } @$blocklist ];
            }
        }
    }
    elsif (defined $act) { # activate/deactivate link next to entries in block list
        my $blocklist = $$preferences{$list};
        if (defined $blocklist) {
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
            { username => $$subscriber{username},
              domain   => $$subscriber{domain},
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
    my $subscriber;

    my $subscriber_id = $c->request->params->{subscriber_id};
    return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_voip_account_subscriber_by_id',
                                                        { subscriber_id => $subscriber_id },
                                                        \$subscriber
                                                      );
    my $preferences;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_subscriber_preferences',
                                                        { username => $$subscriber{username},
                                                          domain   => $$subscriber{domain},
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

    $c->stash->{subscriber} = $subscriber;
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
    my $subscriber;

    my $subscriber_id = $c->request->params->{subscriber_id};
    return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_voip_account_subscriber_by_id',
                                                        { subscriber_id => $subscriber_id },
                                                        \$subscriber
                                                      );
    my $preferences;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_subscriber_preferences',
                                                        { username => $$subscriber{username},
                                                          domain   => $$subscriber{domain},
                                                        },
                                                        \$preferences
                                                      );
    my $list = $c->request->params->{list_name};

    # input text field to add new entry to IP list
    my $add = $c->request->params->{list_add};
    if(defined $add) {
        my $checkresult;
        return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'check_ipnet', { ipnet => $add }, \$checkresult);
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
                                              { username => $$subscriber{username},
                                                domain   => $$subscriber{domain},
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
    my $subscriber;

    my $subscriber_id = $c->request->params->{subscriber_id};
    return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_voip_account_subscriber_by_id',
                                                        { subscriber_id => $subscriber_id },
                                                        \$subscriber
                                                      );
    my $speed_dial_slots;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_speed_dial_slots',
                                                            { username => $$subscriber{username},
                                                              domain   => $$subscriber{domain},
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
                                    $c->model('Provisioning')->localize($c, $c->view($c->config->{view})->
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

    $c->stash->{subscriber} = $subscriber;
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
    my $subscriber;

    my $subscriber_id = $c->request->params->{subscriber_id};
    return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_voip_account_subscriber_by_id',
                                                        { subscriber_id => $subscriber_id },
                                                        \$subscriber
                                                      );

    # add new entry form
    my $add_slot = $c->request->params->{add_slot};
    my $add_destination = $c->request->params->{add_destination};
    if(defined $add_slot) {

        my ($check_slot, $check_sip_username, $check_sip_uri);
        
        return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'check_vsc_format', { slot => $add_slot }, \$check_slot);
        return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'check_sip_uri', { sip_uri => $add_destination }, \$check_sip_uri);
        return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'check_sip_username', { sip_username => $add_destination }, \$check_sip_username);

        if ($check_slot and ($check_sip_username or $check_sip_uri)) {
            $c->model('Provisioning')->call_prov( $c, 'voip', 'create_speed_dial_slot',
                                                  { username => $$subscriber{username},
                                                    domain   => $$subscriber{domain},
                                                    data => {
                                                                 slot        => $add_slot,
                                                                 destination => $add_destination
                                                            },
                                                  },
                                                  undef
                                                );
        } else {
            unless ($check_sip_username or $check_sip_uri) { 
                $c->session->{adddestinationtxt} = $add_destination;
                $messages{msgadd} = 'Client.Syntax.MalformedSpeedDialDestination'
            }

            unless ($check_slot) {
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
                                          { username => $$subscriber{username},
                                            domain   => $$subscriber{domain},
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
        return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'check_vsc_format', { slot => $update_slot }, \$checkupdate_slot);
        my $checkupdate_destination;
        my $destination;
        if ($update_destination =~ /^\+?\d+$/) {
            $update_destination = admin::Utils::get_qualified_number_for_subscriber($c, $update_destination);
            my $checkresult;
            return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'check_E164_number', { e164number => $update_destination }, \$checkresult);
            $destination = 'sip:'. $update_destination .'@'. $$subscriber{domain}
                if $checkresult;
        } else {
            $destination = $update_destination;
        }
        if ($destination =~ /^sip:.+\@.+$/) {
            $checkupdate_destination = 1;
        }

        if($checkupdate_slot and $checkupdate_destination) {
            $c->model('Provisioning')->call_prov( $c, 'voip', 'update_speed_dial_slot',
                                                  { username => $$subscriber{username},
                                                    domain   => $$subscriber{domain},
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
    my $subscriber;

    my $subscriber_id = $c->request->params->{subscriber_id};
    return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_voip_account_subscriber_by_id',
                                                        { subscriber_id => $subscriber_id },
                                                        \$subscriber
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
                                                 { username => $$subscriber{username},
                                                   domain => $$subscriber{domain},
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
    my $subscriber;

    my $subscriber_id = $c->request->params->{subscriber_id};
    return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_voip_account_subscriber_by_id',
                                                        { subscriber_id => $subscriber_id },
                                                        \$subscriber
                                                      );
    my $preferences;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_subscriber_fax_preferences',
                                                        { username => $$subscriber{username},
                                                          domain   => $$subscriber{domain},
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

    $c->stash->{subscriber} = $subscriber;
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
    my $subscriber;

    my $subscriber_id = $c->request->params->{subscriber_id};
    return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_voip_account_subscriber_by_id',
                                                        { subscriber_id => $subscriber_id },
                                                        \$subscriber
                                                      );
    my $preferences;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_subscriber_fax_preferences',
                                                        { username => $$subscriber{username},
                                                          domain   => $$subscriber{domain},
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
          return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'check_E164_number', { e164number => $add }, \$checkresult);
        } else {
          return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'check_email', { email => $add }, \$checkresult);
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
                                              { username => $$subscriber{username},
                                                domain   => $$subscriber{domain},
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

sub edit_callthru_list : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/subscriber_edit_callthru_list.tt';

    my %messages;
    my $subscriber;

    my $subscriber_id = $c->request->params->{subscriber_id};
    return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_voip_account_subscriber_by_id',
                                                        { subscriber_id => $subscriber_id },
                                                        \$subscriber
                                                      );
    $c->stash->{subscriber} = $subscriber;
    $c->stash->{subscriber_id} = $subscriber_id;

    my $callthru_clis;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_ccmap_entries',
                                                        { username => $$subscriber{username},
                                                          domain   => $$subscriber{domain},
                                                        },
                                                        \$callthru_clis
                                                      );
    $c->stash->{callthru_clis} = $callthru_clis;
    $c->stash->{editid} = $c->request->params->{editid};

    return 1;
}

sub do_edit_callthru_list : Local {
    my ( $self, $c ) = @_;

    my %messages;
    my $subscriber;

    my $subscriber_id = $c->request->params->{subscriber_id};
    $c->response->redirect("/subscriber/edit_callthru_list?subscriber_id=$subscriber_id") unless
        $c->model('Provisioning')->call_prov( $c, 'billing', 'get_voip_account_subscriber_by_id',
                                                        { subscriber_id => $subscriber_id },
                                                        \$subscriber
                                                      );
    
    my $action = $c->request->params->{action};

    if($action eq "add") {
        if($c->model('Provisioning')->call_prov( $c, 'voip', 'create_ccmap_entry',
                                                        { username => $$subscriber{username},
                                                          domain   => $$subscriber{domain},
							  data => {
                                                             auth_key => $c->request->params->{auth_key},
							  },
                                                        },
                                                      ))
        {
            $messages{msg} = 'Server.Voip.SavedSettings';
            $c->session->{messages} = \%messages;
            $c->response->redirect("/subscriber/edit_callthru_list?subscriber_id=$subscriber_id");
            return;
        } else {
            $messages{err} = 'Client.Voip.InputErrorFound';
        }
    } elsif($action eq "delete") {
        if($c->model('Provisioning')->call_prov( $c, 'voip', 'delete_ccmap_entry',
                                                        { username => $$subscriber{username},
                                                          domain   => $$subscriber{domain},
                                                          id => $c->request->params->{editid},
                                                        },
                                                      ))
        {
            $messages{msg} = 'Server.Voip.SavedSettings';
            $c->session->{messages} = \%messages;
            $c->response->redirect("/subscriber/edit_callthru_list?subscriber_id=$subscriber_id");
            return;
        } else {
            $messages{err} = 'Client.Voip.InputErrorFound';
        }
    } elsif($action eq "save") {
        if($c->model('Provisioning')->call_prov( $c, 'voip', 'update_ccmap_entry',
                                                        { username => $$subscriber{username},
                                                          domain   => $$subscriber{domain},
                                                          id => $c->request->params->{editid},
							  data => {
                                                              auth_key => $c->request->params->{auth_key},
							  },
                                                        },
                                                      ))
        {
            $messages{msg} = 'Server.Voip.SavedSettings';
            $c->session->{messages} = \%messages;
            $c->response->redirect("/subscriber/edit_callthru_list?subscriber_id=$subscriber_id");
            return;
        } else {
            $messages{err} = 'Client.Voip.InputErrorFound';
        }
    }
    
    $c->session->{messages} = \%messages;
    $c->response->redirect("/subscriber/edit_callthru_list?subscriber_id=$subscriber_id");

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
