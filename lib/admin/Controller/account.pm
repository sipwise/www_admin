package admin::Controller::account;

use strict;
use warnings;
use base 'Catalyst::Controller';

=head1 NAME

admin::Controller::account - Catalyst Controller

=head1 DESCRIPTION

This provides functionality for VoIP account administration.

=head1 METHODS

=head2 index 

Display search form.

=cut

sub index : Private {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/account.tt';

    if(defined $c->session->{refill_account_id}) {
        $c->stash->{refill_account_id} = $c->session->{refill_account_id};
        delete $c->session->{refill_account_id};
    }
    if(defined $c->session->{refill_external_id}) {
        $c->stash->{refill_external_id} = $c->session->{refill_external_id};
        delete $c->session->{refill_external_id};
    }

    return 1;
}

=head2 getbyid 

Check entered account ID and redirect.

=cut

sub getbyid : Local {
    my ( $self, $c ) = @_;

    my $account_id = $c->request->params->{account_id};

    if(defined $account_id and $account_id =~ /^\d+$/) {

        if($c->model('Provisioning')->call_prov( $c, 'billing', 'get_voip_account_by_id',
                                                 { id => $account_id },
                                                 undef
                                               ))
        {
            $c->response->redirect("/account/detail?account_id=$account_id");
            return;
        }

        delete $c->session->{prov_error} if $c->session->{prov_error} eq 'Client.Voip.NoSuchAccount';
        $c->session->{messages} = { accsearcherr => 'Client.Voip.NoSuchAccount' };
    } else {
        $c->session->{messages} = { accsearcherr => 'Client.Syntax.AccountID' };
    }

    $c->session->{refill_account_id} = $account_id;
    $c->response->redirect("/account");
    return;
}

=head2 getbyextid 

Search for entered external ID and redirect.

=cut

sub getbyextid : Local {
    my ( $self, $c ) = @_;

    my $external_id = $c->request->params->{external_id};
    my $voip_account;

    if(length $external_id) {

        if($c->model('Provisioning')->call_prov( $c, 'billing', 'get_voip_account_by_external_id',
                                                 { external_id => $external_id },
                                                 \$voip_account
                                               ))
        {
            $c->response->redirect("/account/detail?account_id=". $$voip_account{id});
            return;
        }

        delete $c->session->{prov_error} if $c->session->{prov_error} eq 'Client.Voip.NoSuchAccount';
        $c->session->{messages} = { extidsearcherr => 'Client.Voip.NoSuchAccount' };
    } else {
        $c->session->{messages} = { extidsearcherr => 'Web.Syntax.MissingExternalID' };
    }

    $c->session->{refill_external_id} = $external_id;
    $c->response->redirect("/account");
    return;
}

=head2 detail 

Show account details.

=cut

sub detail : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/account_detail.tt';

    my $voip_account;
    my $account_id = $c->request->params->{account_id} || undef;
    if(defined $account_id) {
        return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_voip_account_by_id',
                                                            { id => $account_id },
                                                            \$voip_account
                                                          );
    } else {
        $$voip_account{customer_id} = $c->request->params->{customer_id} || undef;
    }

    my $fraudpref = $self->_get_fraud_preferences($c, $account_id);
    $c->stash->{edit_account} = $c->request->params->{edit_account};

    if($c->config->{billing_features}) {
        if(defined $account_id) {
            return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_voip_account_balance',
                                                                { id => $account_id },
                                                                \$$voip_account{balance}
                                                              );

            $$voip_account{balance}{cash_balance} = 0
                unless defined $$voip_account{balance}{cash_balance};
            $$voip_account{balance}{cash_balance_interval} = 0
                unless defined $$voip_account{balance}{cash_balance_interval};
            $$voip_account{balance}{free_time_balance} = 0
                unless defined $$voip_account{balance}{free_time_balance};
            $$voip_account{balance}{free_time_balance_interval} = 0
                unless defined $$voip_account{balance}{free_time_balance_interval};

            $$voip_account{balance}{cash_balance} = 
                sprintf "%.2f", $$voip_account{balance}{cash_balance} / 100;
            $$voip_account{balance}{cash_balance_interval} = 
                sprintf "%.2f", $$voip_account{balance}{cash_balance_interval} / 100;
        }

        if(ref $c->session->{restore_balance_input} eq 'HASH') {
            $c->stash->{balanceadd} = $c->session->{restore_balance_input};
            delete $c->session->{restore_balance_input};
        }

        $c->stash->{edit_balance} = $c->request->params->{edit_balance};
        $c->stash->{edit_fraud} = $c->request->params->{edit_fraud};

        # we only use this to fill the drop-down lists
        if($c->request->params->{edit_account}) {
            if($c->config->{product_features}) {
                my $products;
                return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_products',
                                                                    undef,
                                                                    \$products
                                                                  );
                $c->stash->{products} = [ grep { $$_{data}{class} eq 'voip' }
                                            sort { $$a{data}{name} cmp $$b{data}{name} }
                                              eval { @$products }
                                        ];
            }
            my $billing_profiles;
            return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_billing_profiles',
                                                                undef,
                                                                \$billing_profiles
                                                              );

            $c->stash->{billing_profiles} = [ sort { $$a{data}{name} cmp $$b{data}{name} }
                                                eval { @$billing_profiles }
                                            ];
        } else {
            if(defined $$voip_account{product}) {
                my $product;
                return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_product',
                                                                    { handle => $$voip_account{product} },
                                                                    \$product
                                                                  );
                $$voip_account{product_name} = $$product{data}{name};
                $$voip_account{currency} = $$product{data}{currency};
            }
            if(defined $$voip_account{billing_profile}) {
                my $profile;
                return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_billing_profile',
                                                                    { handle => $$voip_account{billing_profile} },
                                                                    \$profile
                                                                  );
                $$voip_account{billing_profile_name} = $$profile{data}{name};
                $$voip_account{currency} = $$profile{data}{currency};
            }
        }

        $c->stash->{billing_features} = 1;
    }

    if(ref $c->session->{restore_account_input} eq 'HASH') {
        for(keys %{$c->session->{restore_account_input}}) {
            $$voip_account{$_} = $c->session->{restore_account_input}{$_};
        }
        delete $c->session->{restore_account_input};
    }

    delete $$voip_account{subscribers}
        if exists $$voip_account{subscribers}
           and !defined $$voip_account{subscribers}
            or ref $$voip_account{subscribers} ne 'ARRAY'
            or $#{$$voip_account{subscribers}} == -1;

    foreach my $vas (eval { @{$$voip_account{subscribers}} }) {
        next if $$vas{status} eq 'terminated';
        my $regcon;
        return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_subscriber_registered_devices',
                                                            { username => $$vas{username},
                                                              domain   => $$vas{domain},
                                                            },
                                                            \$regcon
                                                          );
        $$vas{registered_contacts} = join ", ", map { $$_{user_agent} } @$regcon if eval { @$regcon };
    }

    $c->stash->{account} = $voip_account;
    $c->stash->{account}->{fraud} = $fraudpref;
    $c->stash->{account}{is_locked} = 1 if $$voip_account{status} eq 'locked';

    return 1;
}

=head2 save_account 

Create or update details of a VoIP account.

=cut

sub save_account : Local {
    my ( $self, $c ) = @_;

    my %messages;
    my %settings;

    my $account_id = $c->request->params->{account_id} || undef;

    if(defined $c->request->params->{external_id}) {
        $settings{external_id} = $c->request->params->{external_id};
    }

    my $product = $c->request->params->{product};
    $settings{product} = $product if defined $product;

    my $billing_profile = $c->request->params->{billing_profile};
    $settings{billing_profile} = $billing_profile if defined $billing_profile;

    my $customer_id = $c->request->params->{customer_id} || undef;
    $settings{customer_id} = $customer_id if defined $customer_id;

    if(keys %settings or (!$c->config->{billing_features} and !defined $account_id)) {
        if(defined $account_id) {
            if($c->model('Provisioning')->call_prov( $c, 'billing', 'update_voip_account',
                                                     { id   => $account_id,
                                                       data => \%settings,
                                                     },
                                                     undef))
            {
                $messages{accmsg} = 'Server.Voip.SavedSettings';
                $c->session->{messages} = \%messages;
                $c->response->redirect("/account/detail?account_id=$account_id");
                return;
            }
        } else {
            if($c->model('Provisioning')->call_prov( $c, 'billing', 'create_voip_account',
                                                     { data => \%settings },
                                                     \$account_id))
            {
                $messages{accmsg} = 'Web.Account.Created';
                $c->session->{messages} = \%messages;
                $c->response->redirect("/account/detail?account_id=$account_id");
                return;
            }
        }
    }

    $c->session->{messages} = \%messages;
    $c->session->{restore_account_input} = \%settings;
    $c->response->redirect("/account/detail?account_id=$account_id&edit_account=1");
    return;
}

=head2 lock

Locks and unlocks an account.

=cut

sub lock : Local {
    my ( $self, $c ) = @_;

    my $account_id = $c->request->params->{account_id};
    my $lock = $c->request->params->{lock};

    $c->model('Provisioning')->call_prov( $c, 'billing', 'lock_voip_account',
                                          { id       => $account_id,
                                            lock     => $lock,
                                          },
                                          undef
                                        );

    $c->response->redirect("/account/detail?account_id=$account_id");
}

=head2 activate

Activates an account by calling finish on it.

=cut

sub activate : Local {
    my ( $self, $c ) = @_;

    my %messages;

    my $account_id = $c->request->params->{account_id};

    if($c->model('Provisioning')->call_prov( $c, 'billing', 'activate_voip_account',
                                             { id => $account_id },
                                             undef))
    {
        $messages{topmsg} = 'Web.Account.Activated';
    }

    $c->session->{messages} = \%messages;
    $c->response->redirect("/account/detail?account_id=$account_id");
    return;
}

=head2 terminate

Terminates an account.

=cut

sub terminate : Local {
    my ( $self, $c ) = @_;

    my %messages;

    my $account_id = $c->request->params->{account_id};

    if($c->model('Provisioning')->call_prov( $c, 'billing', 'terminate_voip_account',
                                             { id => $account_id },
                                             undef))
    {
        $messages{topmsg} = 'Server.Voip.SubscriberDeleted';
        $c->session->{messages} = \%messages;
        $c->response->redirect("/account");
        return;
    }

    $c->session->{messages} = \%messages;
    $c->response->redirect("/account/detail?account_id=$account_id");
    return;
}

=head2 delete

Deletes an account.

=cut

sub delete : Local {
    my ( $self, $c ) = @_;

    my %messages;

    my $account_id = $c->request->params->{account_id};

    if($c->model('Provisioning')->call_prov( $c, 'billing', 'delete_voip_account',
                                             { id => $account_id },
                                             undef))
    {
        $messages{topmsg} = 'Server.Voip.SubscriberDeleted';
        $c->session->{messages} = \%messages;
        $c->response->redirect("/account");
        return;
    }

    $c->session->{messages} = \%messages;
    $c->response->redirect("/account/detail?account_id=$account_id");
    return;
}

=head2 update_balance

Update a VoIP account cash and free time balance.

=cut

sub update_balance : Local {
    my ( $self, $c ) = @_;

    my %messages;
    my %settings;

    my $account_id = $c->request->params->{account_id};

    my $add_cash = $c->request->params->{add_cash};
    if(defined $add_cash and length $add_cash) {
        $settings{cash} = $add_cash;
        if($settings{cash} =~ /^[+-]?\d+(?:[.,]\d+)?$/) {
            $settings{cash} =~ s/,/./;
            $settings{cash} *= 100;
        } else {
            $messages{addcash} = 'Client.Syntax.CashValue';
        }
    }
    my $add_time = $c->request->params->{add_time};
    if(defined $add_time and length $add_time) {
        $messages{addtime} = 'Client.Syntax.TimeValue'
            unless $add_time =~ /^[+-]?\d+$/;
        $settings{free_time} = $add_time;
    }

    unless(keys %messages) {
        if($c->model('Provisioning')->call_prov( $c, 'billing', 'update_voip_account_balance',
                                                 { id => $account_id,
                                                   data => \%settings,
                                                 },
                                                 undef))
        {
            $messages{balmsg} = 'Server.Voip.SavedSettings';
            $c->session->{messages} = \%messages;
            $c->response->redirect("/account/detail?account_id=$account_id");
            return;
        }
    } else {
        $messages{balerr} = 'Client.Voip.InputErrorFound';
    }

    $c->session->{messages} = \%messages;
    $c->session->{restore_balance_input} = \%settings;
    $c->session->{restore_balance_input}{cash} = $add_cash
        if defined $add_cash and length $add_cash;
    $c->response->redirect("/account/detail?account_id=$account_id&edit_balance=1");
    return;
}

=head2 update_fraud

Update the VoIP account fraud preferences.

=cut

sub update_fraud : Local {
    my ( $self, $c ) = @_;

    my %messages;
    my %settings;

    my $account_id = $c->request->params->{account_id};

    my %settings = ();
   
    $settings{fraud_interval_limit} = $c->request->params->{fraud_interval_limit};
    if(length $settings{fraud_interval_limit}) {
        if($settings{fraud_interval_limit} =~ /^[+]?\d+(?:[.,]\d\d?)?$/) {
            $settings{fraud_interval_limit} =~ s/^\+//;
            $settings{fraud_interval_limit} =~ s/,/./;
            $settings{fraud_interval_limit} *= 100;
        } else {
            $messages{fraud_interval_limit} = 'Client.Syntax.CashValue';
        }
    } else {
        delete $settings{fraud_interval_limit};
    }

    $settings{fraud_interval_lock} = $c->request->params->{fraud_interval_lock}
        if $c->request->params->{fraud_interval_lock};

    if(length $c->request->params->{fraud_interval_notify}) {
        @{$settings{fraud_interval_notify}} = split /\s*,\s*/, $c->request->params->{fraud_interval_notify};
    } else {
        $settings{fraud_interval_notify} = [];
    }

    $settings{fraud_daily_limit} = $c->request->params->{fraud_daily_limit};
    if(length $settings{fraud_daily_limit}) {
        if($settings{fraud_daily_limit} =~ /^[+]?\d+(?:[.,]\d\d?)?$/) {
            $settings{fraud_daily_limit} =~ s/^\+//;
            $settings{fraud_daily_limit} =~ s/,/./;
            $settings{fraud_daily_limit} *= 100;
        } else {
            $messages{fraud_daily_limit} = 'Client.Syntax.CashValue';
        }
    } else {
        delete $settings{fraud_daily_limit};
    }

    $settings{fraud_daily_lock} = $c->request->params->{fraud_daily_lock}
        if $c->request->params->{fraud_daily_lock};

    if(length $c->request->params->{fraud_daily_notify}) {
        @{$settings{fraud_daily_notify}} = split /\s*,\s*/, $c->request->params->{fraud_daily_notify};
    } else {
        $settings{fraud_daily_notify} = [];
    } 

    unless(keys %messages) {
        if($c->model('Provisioning')->call_prov( $c, 'billing', 'set_voip_account_fraud_preferences',
                                                 { id => $account_id,
                                                   data => \%settings,
                                                 },
                                                 undef))
        {
            $messages{fraudmsg} = 'Server.Voip.SavedSettings';
            $c->session->{messages} = \%messages;
            $c->response->redirect("/account/detail?account_id=$account_id#fraud");
            return;
        }
    } else {
        $messages{frauderr} = 'Client.Voip.InputErrorFound';
    }

    $c->session->{messages} = \%messages;
    $c->response->redirect("/account/detail?account_id=$account_id&edit_fraud=1#fraud");
    return;
}

=head2 delete_fraud

Deletes the Voip account fraud limits (aka reset to billing profile defaults)

=cut

sub delete_fraud : Local {
    my ( $self, $c ) = @_;

    my %messages;

    my $account_id = $c->request->params->{account_id};

    unless(keys %messages) {
        if($c->model('Provisioning')->call_prov( $c, 'billing', 'reset_voip_account_fraud_preferences',
                                                 { id => $account_id },
                                                 undef))
        {
            $messages{fraudmsg} = 'Server.Voip.SavedSettings';
            $c->session->{messages} = \%messages;
            $c->response->redirect("/account/detail?account_id=$account_id#fraud");
            return;
        }
    } else {
        $messages{frauderr} = 'Client.Voip.InputErrorFound';
    }

    $c->session->{messages} = \%messages;
    $c->response->redirect("/account/detail?account_id=$account_id#fraud");
    return;
}

sub _get_fraud_preferences : Private {
    my ( $self, $c, $account_id ) = @_;
    my $fraud;
    if($c->model('Provisioning')->call_prov( $c, 'billing', 'get_voip_account_fraud_preferences',
                                             { id => $account_id },
                                             \$fraud) && defined $fraud)
    {
        if(defined $fraud->{fraud_interval_limit}) {
          $fraud->{fraud_interval_limit} = sprintf "%.2f", $fraud->{fraud_interval_limit} /= 100;
        }
        if(defined $fraud->{fraud_daily_limit}) {
          $fraud->{fraud_daily_limit} = sprintf "%.2f", $fraud->{fraud_daily_limit} /= 100;
        }
        $fraud->{fraud_interval_notify} = eval { join ', ', @{$fraud->{fraud_interval_notify}} }; 
        $fraud->{fraud_daily_notify} = eval { join ', ', @{$fraud->{fraud_daily_notify}} };
        return $fraud;
    } else {
        return;
    }
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

The account controller is Copyright (c) 2007-2010 Sipwise GmbH, Austria.
You should have received a copy of the licences terms together with the
software.

=cut

# ende gelaende
1;
