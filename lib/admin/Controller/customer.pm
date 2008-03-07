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

    my $search_string = $c->request->params->{search_string};
    
    my $customer_list;
    return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'search_customers',
                                                        { filter => { anything => '%'.$search_string.'%' } },
                                                        \$customer_list
                                                      );

    $c->stash->{customer_list} = $$customer_list{customers}
        if ref $$customer_list{customers} eq 'ARRAY';
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
    $c->session->{customer}{contracts} = $$contracts{result};
    my $orders;
    return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_customer_orders',
                                                        { id => $customer_id },
                                                        \$orders
                                                      );
    $c->session->{customer}{orders} = $$orders{result};

    $c->stash->{customer} = $c->session->{customer};

    if(ref $c->session->{restore_customer_input} eq 'HASH') {
        $c->stash->{customer} = $c->session->{restore_customer_input};
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
# there's currently nothing to edit
#    $c->stash->{edit_customer} = $c->request->params->{edit_customer};
    $c->stash->{edit_contact} = $c->request->params->{edit_contact};
    $c->stash->{edit_commercial} = $c->request->params->{edit_commercial};
    $c->stash->{edit_technical} = $c->request->params->{edit_technical};

    return 1;
}

=head2 create_customer

Creates a new customer. Not yet implemented.

=cut

sub create_customer : Local {
    my ( $self, $c ) = @_;

    my $customer_id;
    if($c->model('Provisioning')->call_prov( $c, 'billing', 'create_customer',
                                             {
                                             },
                                             \$customer_id))
    {
        $c->response->redirect("/customer/detail?customer_id=$customer_id");
        return;
    }

    $c->response->redirect("/customer");
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

    if(defined $c->request->params->{shopuser} and length $c->request->params->{shopuser}) {
        $settings{shopuser} = $c->request->params->{shopuser};
        my $checkresult;
        return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'check_username',
                                                            $settings{shopuser}, \$checkresult
                                                          );
        $messages{username} = 'Client.Syntax.MalformedUsername' unless $checkresult;
    }
    if(defined $c->request->params->{shoppass} and length $c->request->params->{shoppass}) {
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

    if(defined $c->request->params->{gender} and length $c->request->params->{gender}) {
        $settings{gender} = $c->request->params->{gender};
    } else {
        $settings{gender} = undef;
    }
    if(defined $c->request->params->{firstname} and length $c->request->params->{firstname}) {
        $settings{firstname} = $c->request->params->{firstname};
    } else {
        $settings{firstname} = undef;
    }
    if(defined $c->request->params->{lastname} and length $c->request->params->{lastname}) {
        $settings{lastname} = $c->request->params->{lastname};
    } else {
        $settings{lastname} = undef;
    }
    if(defined $c->request->params->{comregnum} and length $c->request->params->{comregnum}) {
        $settings{comregnum} = $c->request->params->{comregnum};
    } else {
        $settings{comregnum} = undef;
    }
    if(defined $c->request->params->{company} and length $c->request->params->{company}) {
        $settings{company} = $c->request->params->{company};
    } else {
        $settings{company} = undef;
    }
    if(defined $c->request->params->{street} and length $c->request->params->{street}) {
        $settings{street} = $c->request->params->{street};
    } else {
        $settings{street} = undef;
    }
    if(defined $c->request->params->{postcode} and length $c->request->params->{postcode}) {
        $settings{postcode} = $c->request->params->{postcode};
    } else {
        $settings{postcode} = undef;
    }
    if(defined $c->request->params->{phonenumber} and length $c->request->params->{phonenumber}) {
        $settings{phonenumber} = $c->request->params->{phonenumber};
    } else {
        $settings{phonenumber} = undef;
    }
    if(defined $c->request->params->{mobilenumber} and length $c->request->params->{mobilenumber}) {
        $settings{mobilenumber} = $c->request->params->{mobilenumber};
    } else {
        $settings{mobilenumber} = undef;
    }
    if(defined $c->request->params->{email} and length $c->request->params->{email}) {
        $settings{email} = $c->request->params->{email};
    } else {
        $settings{email} = undef;
    }
    if(defined $c->request->params->{newsletter} and $c->request->params->{newsletter}) {
        $settings{newsletter} = 1;
    } else {
        $settings{newsletter} = 0;
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

The account controller is Copyright (c) 2007 Sipwise GmbH, Austria. All
rights reserved.

=cut

# ende gelaende
1;
