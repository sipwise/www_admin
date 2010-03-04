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
                                                 \$c->session->{voip_account}
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

    $c->response->redirect("/account");
    return;
}

=head2 detail 

Show account details.

=cut

sub detail : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/account_detail.tt';

    my $account_id = $c->request->params->{account_id} || undef;
    if(defined $account_id) {
        return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_voip_account_by_id',
                                                            { id => $account_id },
                                                            \$c->session->{voip_account}
                                                          );
    } else {
        delete $c->session->{voip_account};
        $c->session->{voip_account}{customer_id} = $c->request->params->{customer_id} || undef;
    }
    if($c->config->{billing_features}) {
        if(defined $account_id) {
            return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_voip_account_balance',
                                                                { id => $account_id },
                                                                \$c->session->{voip_account}{balance}
                                                              );

            $c->session->{voip_account}{balance}{cash_balance} = 0
                unless defined $c->session->{voip_account}{balance}{cash_balance};
            $c->session->{voip_account}{balance}{cash_balance_interval} = 0
                unless defined $c->session->{voip_account}{balance}{cash_balance_interval};
            $c->session->{voip_account}{balance}{free_time_balance} = 0
                unless defined $c->session->{voip_account}{balance}{free_time_balance};
            $c->session->{voip_account}{balance}{free_time_balance_interval} = 0
                unless defined $c->session->{voip_account}{balance}{free_time_balance_interval};

            $c->session->{voip_account}{balance}{cash_balance} = 
                sprintf "%.2f", $c->session->{voip_account}{balance}{cash_balance} / 100;
            $c->session->{voip_account}{balance}{cash_balance_interval} = 
                sprintf "%.2f", $c->session->{voip_account}{balance}{cash_balance_interval} / 100;
        }

        if(ref $c->session->{restore_account_input} eq 'HASH') {
            $c->session->{voip_account}{product} = $c->session->{restore_account_input}{product};
            $c->session->{voip_account}{billing_profile} = $c->session->{restore_account_input}{billing_profile};
            $c->session->{voip_account}{customer_id} = $c->session->{restore_account_input}{customer_id};
            delete $c->session->{restore_account_input};
        }

        if(ref $c->session->{restore_balance_input} eq 'HASH') {
            $c->stash->{balanceadd} = $c->session->{restore_balance_input};
            delete $c->session->{restore_balance_input};
        }

        $c->stash->{edit_account} = $c->request->params->{edit_account};
        $c->stash->{edit_balance} = $c->request->params->{edit_balance};

        # we only use this to fill the drop-down lists
        if($c->request->params->{edit_account}) {
            my $products;
            return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_products',
                                                                undef,
                                                                \$products
                                                              );
            $c->stash->{products} = [ grep { $$_{data}{class} eq 'voip' }
                                        sort { $$a{data}{name} cmp $$b{data}{name} }
                                          eval { @$products }
                                    ];
            my $billing_profiles;
            return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_billing_profiles',
                                                                undef,
                                                                \$billing_profiles
                                                              );

            $c->stash->{billing_profiles} = [ sort { $$a{data}{name} cmp $$b{data}{name} }
                                                eval { @$billing_profiles }
                                            ];
        } else {
            if(defined $c->session->{voip_account}{product}) {
                my $product;
                return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_product',
                                                                    { handle => $c->session->{voip_account}{product} },
                                                                    \$product
                                                                  );
                $c->session->{voip_account}{product_name} = $$product{data}{name};
            }
            if(defined $c->session->{voip_account}{billing_profile}) {
                my $profile;
                return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_billing_profile',
                                                                    { handle => $c->session->{voip_account}{billing_profile} },
                                                                    \$profile
                                                                  );
                $c->session->{voip_account}{billing_profile_name} = $$profile{data}{name};
            }
        }

        $c->stash->{billing_features} = 1;
    }

    delete $c->session->{voip_account}{subscribers}
        if exists $c->session->{voip_account}{subscribers}
           and !defined $c->session->{voip_account}{subscribers}
            or ref $c->session->{voip_account}{subscribers} ne 'ARRAY'
            or $#{$c->session->{voip_account}{subscribers}} == -1;

    $c->stash->{account} = $c->session->{voip_account};
    $c->stash->{account}{is_locked} = 1 if $c->session->{voip_account}{status} eq 'locked';

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

=head1 BUGS AND LIMITATIONS

=over

=item currently none

=back

=head1 SEE ALSO

Provisioning model, Sipwise::Provisioning::Billing, Catalyst

=head1 AUTHORS

Daniel Tiefnig <dtiefnig@sipwise.com>

=head1 COPYRIGHT

The account controller is Copyright (c) 2007-2009 Sipwise GmbH, Austria.
All rights reserved.

=cut

# ende gelaende
1;
