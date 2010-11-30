package admin::Controller::customer;

use strict;
use warnings;
use base 'Catalyst::Controller';

=head1 NAME

admin::Controller::customer - Catalyst Controller

=head1 DESCRIPTION

This provides functionality for customer administration.

=head1 METHODS

=head2 index 

Display search form.

=cut

sub index : Private {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/customer.tt';

    return 1;
}

=head2 search

Search for customers and display results.

=cut

sub search : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/customer.tt';

    my $filter;
    my $limit = 10;
    my $offset = $c->request->params->{offset} || 0;
    $offset = 0 if $offset !~ /^\d+$/;

    if($c->request->params->{use_session}) {
        $filter = $c->session->{search_filter}
            if defined $c->session->{search_filter};
    } else {
        $filter = $c->request->params->{search_string} || '';
        $c->session->{search_filter} = $filter;
    }

    $c->stash->{search_string} = $filter;
    $filter =~ s/\*/\%/;
    $filter =~ s/\?/\_/;

    my $customer_list;
    return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'search_customers',
                                                        { filter => { anything => '%'.$filter.'%',
                                                                      limit    => $limit,
                                                                      offset   => $limit * $offset,
                                                        }           },
                                                        \$customer_list
                                                      );

    $c->stash->{searched} = 1;
    if(ref $$customer_list{customers} eq 'ARRAY' and @{$$customer_list{customers}}) {
        $c->stash->{customer_list} = $$customer_list{customers};
        $c->stash->{total_count} = $$customer_list{total_count};
        $c->stash->{offset} = $offset;
        if($$customer_list{total_count} > @{$$customer_list{customers}}) {
            # paginate!
            $c->stash->{pagination} = admin::Utils::paginate($$customer_list{total_count}, $offset, $limit);
            $c->stash->{max_offset} = ${$c->stash->{pagination}}[-1]{offset};
        }
    }

}

=head2 getbyid 

Check entered customer ID and redirect.

=cut

sub getbyid : Local {
    my ( $self, $c ) = @_;

    my $customer_id = $c->request->params->{customer_id};

    if(defined $customer_id and $customer_id =~ /^\d+$/) {

        if($c->model('Provisioning')->call_prov( $c, 'billing', 'get_customer',
                                                 { id => $customer_id },
                                                 \$c->session->{customer}
                                               ))
        {
            $c->response->redirect("/customer/detail?customer_id=$customer_id");
            return;
        }

        if($c->session->{prov_error} eq 'Client.Billing.NoSuchCustomer') {
            delete $c->session->{prov_error};
            $c->session->{messages} = { custgeterr => 'Client.Billing.NoSuchCustomer' };
        }
    } else {
        $c->session->{messages} = { custgeterr => 'Web.Syntax.Numeric' };
    }

    $c->response->redirect("/customer");
    return;
}

=head2 detail 

Show customer details.

=cut

sub detail : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/customer_detail.tt';

    unless($c->request->params->{new_customer}) {
        my $customer_id = $c->request->params->{customer_id};
        return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_customer',
                                                            { id => $customer_id },
                                                            \$c->session->{customer}
                                                          );
        my $contracts;
        return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_customer_contracts',
                                                            { id => $customer_id },
                                                            \$contracts
                                                          );
        $c->session->{customer}{contracts} = $contracts if eval { @$contracts };
        my $orders;
        return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_customer_orders',
                                                            { id => $customer_id },
                                                            \$orders
                                                          );
        $c->session->{customer}{orders} = $orders if eval { @$orders };

        $c->stash->{customer} = $c->session->{customer};
    }

    if(ref $c->session->{restore_customer_input} eq 'HASH') {
        if(ref $c->stash->{customer} eq 'HASH') {
            $c->stash->{customer} = { %{$c->stash->{customer}}, %{$c->session->{restore_customer_input}} };
        } else {
            $c->stash->{customer} = $c->session->{restore_customer_input};
        }
        delete $c->session->{restore_customer_input};
    }
    if(ref $c->session->{restore_contact_input} eq 'HASH') {
        $c->stash->{customer}{contact} = $c->session->{restore_contact_input};
        delete $c->session->{restore_contact_input};
    }
    if(ref $c->session->{restore_comm_contact_input} eq 'HASH') {
        $c->stash->{customer}{comm_contact} = $c->session->{restore_comm_contact_input};
        delete $c->session->{restore_comm_contact_input};
    }
    if(ref $c->session->{restore_tech_contact_input} eq 'HASH') {
        $c->stash->{customer}{tech_contact} = $c->session->{restore_tech_contact_input};
        delete $c->session->{restore_tech_contact_input};
    }

    $c->stash->{show_pass} = $c->request->params->{show_pass};
    $c->stash->{edit_customer} = $c->request->params->{new_customer} || $c->request->params->{edit_customer};
    $c->stash->{edit_contact} = $c->request->params->{new_customer} || $c->request->params->{edit_contact};
    $c->stash->{edit_commercial} = $c->request->params->{edit_commercial};
    $c->stash->{edit_technical} = $c->request->params->{edit_technical};

    $c->stash->{new_customer} = $c->request->params->{new_customer};

    return 1;
}

=head2 create_customer

Creates a new customer.

=cut

sub create_customer : Local {
    my ( $self, $c ) = @_;

    my (%settings, %messages);

    if(length $c->request->params->{shopuser}) {
        $settings{shopuser} = $c->request->params->{shopuser};
        my $checkresult;
        return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'check_username',
                                                            $settings{shopuser}, \$checkresult
                                                          );
        $messages{username} = 'Client.Syntax.MalformedUsername' unless $checkresult;
    } elsif(length $c->request->params->{shoppass}) {
        $messages{username} = 'Client.Syntax.MissingUsername';
    }
    if(length $c->request->params->{shoppass}) {
        $settings{shoppass} = $c->request->params->{shoppass};
        $messages{password} = 'Client.Voip.PassLength' unless length $settings{shoppass} >= 6;
    } elsif($settings{shopuser}) {
        $messages{password} = 'Client.Voip.PassLength';
    }

    for(qw(gender firstname lastname comregnum company street
           postcode city phonenumber mobilenumber email newsletter))
    {
        if(defined $c->request->params->{$_} and length $c->request->params->{$_}) {
            $settings{contact}{$_} = $c->request->params->{$_};
        }
    }

    $messages{conterr} = 'Client.Billing.ContactIncomplete'
        unless exists $settings{contact}
           and (   exists $settings{contact}{firstname}
                or exists $settings{contact}{lastname}
                or exists $settings{contact}{company});

    unless(keys %messages) {
        my $customer_id;
        if($c->model('Provisioning')->call_prov( $c, 'billing', 'create_customer',
                                                 { data => \%settings },
                                                 \$customer_id))
        {
            $c->session->{messages}{newmsg} = 'Server.Voip.SavedSettings';
            $c->response->redirect("/customer/detail?customer_id=$customer_id");
            return;
        }
    }

    $c->session->{messages} = \%messages;
    $c->session->{restore_customer_input} = \%settings;
    $c->session->{restore_customer_input}{edit_shoppass} = $settings{shoppass};
    $c->session->{restore_contact_input} = $settings{contact};

    $c->response->redirect("/customer/detail?new_customer=1");
    return;
}

=head2 update_customer 

Update details of a customer.

=cut

sub update_customer : Local {
    my ( $self, $c ) = @_;

    my %messages;
    my %settings;

    my $customer_id = $c->request->params->{customer_id};

    if(length $c->request->params->{shopuser}) {
        $settings{shopuser} = $c->request->params->{shopuser};
        my $checkresult;
        return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'check_username',
                                                            $settings{shopuser}, \$checkresult
                                                          );
        $messages{username} = 'Client.Syntax.MalformedUsername' unless $checkresult;
    } elsif(length $c->request->params->{shoppass}) {
        $messages{username} = 'Client.Syntax.MissingUsername';
    } else {
        $settings{shopuser} = undef;
        $settings{shoppass} = undef;
    }
    if(length $c->request->params->{shoppass}) {
        $settings{shoppass} = $c->request->params->{shoppass};
        $messages{password} = 'Client.Voip.PassLength' unless length $settings{shoppass} >= 6;
    }

    if(keys %settings and ! keys %messages) {
        if($c->model('Provisioning')->call_prov( $c, 'billing', 'update_customer',
                                                 { id   => $customer_id,
                                                   data => \%settings,
                                                 },
                                                 undef))
        {
            $messages{accmsg} = 'Server.Voip.SavedSettings';
            $c->session->{messages} = \%messages;
            $c->response->redirect("/customer/detail?customer_id=$customer_id");
            return;
        }
    }

    $c->session->{messages} = \%messages;
    $c->session->{restore_customer_input} = \%settings;
    $c->session->{restore_customer_input}{edit_shoppass} = $settings{shoppass};
    $c->response->redirect("/customer/detail?customer_id=$customer_id&edit_customer=1");
    return;
}

=head2 terminate

Terminates a customer.

=cut

sub terminate : Local {
    my ( $self, $c ) = @_;

    my %messages;
    my $customer_id = $c->request->params->{customer_id};

    if($c->model('Provisioning')->call_prov( $c, 'billing', 'terminate_customer',
                                             { id => $customer_id },
                                             undef))
    {
        $messages{topmsg} = 'Server.Voip.SubscriberDeleted';
        $c->session->{messages} = \%messages;
        $c->response->redirect("/customer");
        return;
    }

    $c->response->redirect("/customer/detail?customer_id=$customer_id");
    return;
}

=head2 delete

Deletes a customer.

=cut

sub delete : Local {
    my ( $self, $c ) = @_;

    my %messages;
    my $customer_id = $c->request->params->{customer_id};

    if($c->model('Provisioning')->call_prov( $c, 'billing', 'delete_customer',
                                             { id => $customer_id },
                                             undef))
    {
        $messages{topmsg} = 'Server.Voip.SubscriberDeleted';
        $c->session->{messages} = \%messages;
        $c->response->redirect("/customer");
        return;
    }

    $c->response->redirect("/customer/detail?customer_id=$customer_id");
    return;
}

=head2 update_contact 

Update details of a customer's contact.

=cut

sub update_contact : Local {
    my ( $self, $c ) = @_;

    my %messages;
    my %settings;

    my $customer_id = $c->request->params->{customer_id};

    my $ctype = $c->request->params->{ctype};

    for(qw(gender firstname lastname comregnum company street
           postcode city phonenumber mobilenumber email newsletter))
    {
        if(defined $c->request->params->{$_} and length $c->request->params->{$_}) {
            $settings{$_} = $c->request->params->{$_};
        } else {
            $settings{$_} = undef;
        }
    }

    unless(keys %messages) {
        if($c->model('Provisioning')->call_prov( $c, 'billing', 'update_customer',
                                                 { id   => $customer_id,
                                                   data => { $ctype => \%settings },
                                                 },
                                                 undef))
        {
            $messages{accmsg} = 'Server.Voip.SavedSettings';
            $c->session->{messages} = \%messages;
            $c->response->redirect("/customer/detail?customer_id=$customer_id");
            return;
        }
    }

    $c->session->{messages} = \%messages;
    $c->session->{'restore_'.$ctype.'_input'} = \%settings;
    $c->response->redirect("/customer/detail?customer_id=$customer_id&edit_customer=1");
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

The customer controller is Copyright (c) 2007-2010 Sipwise GmbH,
Austria. You should have received a copy of the licences terms together
with the software.

=cut

# ende gelaende
1;
