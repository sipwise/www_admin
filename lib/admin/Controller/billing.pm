package admin::Controller::billing;

use strict;
use warnings;
use base 'Catalyst::Controller';

=head1 NAME

admin::Controller::billing - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=head2 index

Display products and billing profiles list.

=cut

sub index : Private {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/billing.tt';

    my $products;
    return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_products',
                                                        undef,
                                                        \$products
                                                      );
    $c->stash->{products} = $$products{result} if eval { @{$$products{result}} };

    my $bilprofs;
    return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_billing_profiles',
                                                        undef,
                                                        \$bilprofs
                                                      );
    $c->stash->{bilprofs} = $$bilprofs{result} if eval { @{$$bilprofs{result}} };

    return 1;
}

=head2 edit_product

Display settings for a product or allow to enter a new one.

=cut

sub edit_product : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/product_edit.tt';

    my $product = $c->request->params->{product};

    if(ref $c->session->{restore_product_input} eq 'HASH') {
        $c->stash->{product}{data} = $c->session->{restore_product_input};
        delete $c->session->{restore_product_input};
        $c->stash->{product}{handle} = $product ? $product : $c->request->params->{handle};

        $c->stash->{product}{data}{price} = 
            sprintf "%.2f", $c->stash->{product}{data}{price} /= 100;
    } elsif($product) {
        return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_product',
                                                            { handle => $product },
                                                            \$c->stash->{product}
                                                          );
        $c->stash->{product}{data}{price} = 
            sprintf "%.2f", $c->stash->{product}{data}{price} /= 100;
    }

    $c->stash->{handle} = $product if $product;

    my $bilprofs;
    return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_billing_profiles',
                                                        undef,
                                                        \$bilprofs
                                                      );
    $c->stash->{bilprofs} = $$bilprofs{result} if eval { @{$$bilprofs{result}} };
    unshift @{$c->stash->{bilprofs}}, { handle => undef, data => { name => '' } };

    return 1;
}

=head2 do_edit_product

Change settings for a product in the database or create a new one.

=cut

sub do_edit_product : Local {
    my ( $self, $c ) = @_;

    my %messages;
    my %settings;

    # existing product handle, if any
    my $product = $c->request->params->{product};
    # new product handle, if any
    my $handle = $c->request->params->{handle};

    $settings{class} = $c->request->params->{class};
    $settings{name} = $c->request->params->{name};
    $settings{on_sale} = $c->request->params->{on_sale} ? 1 : 0;

    $settings{price} = $c->request->params->{price};
    if(length $settings{price}) {
        if($settings{price} =~ /^[+]?\d+(?:[.,]\d\d?)?$/) {
            $settings{price} =~ s/,/./;
            $settings{price} *= 100;
        } else {
            $messages{price} = 'Client.Syntax.CashValue';
        }
    } else {
        $settings{price} = 0;
    }

    $settings{weight} = $c->request->params->{weight};
    if(length $settings{weight}) {
        $messages{weight} = 'Client.Syntax.TimeValue'
            unless $settings{weight} =~ /^[+]?\d+$/;
        $settings{weight} =~ s/^\+//;
    } else {
        $settings{weight} = 0;
    }

    $settings{billing_profile} = $c->request->params->{billing_profile} || undef;

    unless(keys %messages) {
        if($product) {
            if($c->model('Provisioning')->call_prov( $c, 'billing', 'update_product',
                                                     { handle => $product,
                                                       data   => \%settings,
                                                     },
                                                     undef))
            {
                $messages{prodmsg} = 'Web.Product.Updated';
                $c->session->{messages} = \%messages;
                $c->response->redirect("/billing#product");
                return;
            }
            $c->session->{restore_product_input} = \%settings;
            $c->response->redirect("/billing/edit_product?product=$product");
            return;
        } else {
            if($c->model('Provisioning')->call_prov( $c, 'billing', 'create_product',
                                                     { handle => $handle,
                                                       data   => \%settings,
                                                     },
                                                     undef))
            {
                $messages{prodmsg} = 'Web.Product.Created';
                $c->session->{messages} = \%messages;
                $c->response->redirect("/billing#product");
                return;
            }
            $c->session->{restore_product_input} = \%settings;
            $c->response->redirect("/billing/edit_product?handle=$handle");
            return;
        }
    }

    $c->session->{messages} = \%messages;
    $c->session->{restore_product_input} = \%settings;
    if($product) {
        $c->response->redirect("/billing/edit_product?product=$product");
    } else {
        $c->response->redirect("/billing/edit_product?handle=$handle");
    }
    return;
}

=head2 do_delete_product

Delete a product from the database.

=cut

sub do_delete_product : Local {
    my ( $self, $c ) = @_;

    my $product = $c->request->params->{product};

    if($product) {
        if($c->model('Provisioning')->call_prov( $c, 'billing', 'delete_product',
                                                 { handle => $product },
                                                 undef))
        {
            $c->session->{messages} = { prodmsg => 'Web.Product.Deleted' };
            $c->response->redirect("/billing#product");
            return;
        }
    }

    $c->response->redirect("/billing");
    return;
}

=head2 edit_bilprof

Display settings for a billing profile or allow to enter a new one.

=cut

sub edit_bilprof : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/bilprof_edit.tt';

    my $bilprof = $c->request->params->{bilprof};

    if(ref $c->session->{restore_bilprof_input} eq 'HASH') {
        $c->stash->{bilprof}{data} = $c->session->{restore_bilprof_input};
        delete $c->session->{restore_bilprof_input};
        $c->stash->{bilprof}{handle} = $bilprof ? $bilprof : $c->request->params->{handle};

        $c->stash->{bilprof}{data}{interval_charge} = 
            sprintf "%.2f", $c->stash->{bilprof}{data}{interval_charge} /= 100;
        $c->stash->{bilprof}{data}{interval_free_cash} =
            sprintf "%.2f", $c->stash->{bilprof}{data}{interval_free_cash} /= 100;
    } elsif($bilprof) {
        return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_billing_profile',
                                                            { handle => $bilprof },
                                                            \$c->stash->{bilprof}
                                                          );
        $c->stash->{bilprof}{data}{interval_charge} = 
            sprintf "%.2f", $c->stash->{bilprof}{data}{interval_charge} /= 100;
        $c->stash->{bilprof}{data}{interval_free_cash} =
            sprintf "%.2f", $c->stash->{bilprof}{data}{interval_free_cash} /= 100;
    }

    $c->stash->{handle} = $bilprof if $bilprof;

    return 1;
}

=head2 do_edit_bilprof

Change settings for a billing profile in the database or create a new
one.

=cut

sub do_edit_bilprof : Local {
    my ( $self, $c ) = @_;

    my %messages;
    my %settings;

    # existing profile handle, if any
    my $bilprof = $c->request->params->{bilprof};
    # new profile handle, if any
    my $handle = $c->request->params->{handle};

    $settings{name} = $c->request->params->{name};
    $settings{prepaid} = $c->request->params->{prepaid} ? 1 : 0;
    $settings{interval_unit} = $c->request->params->{interval_unit} || 'month';
    $settings{interval_count} = $c->request->params->{interval_count} || 1;

    $settings{interval_charge} = $c->request->params->{interval_charge};
    if(length $settings{interval_charge}) {
        if($settings{interval_charge} =~ /^[+]?\d+(?:[.,]\d\d?)?$/) {
            $settings{interval_charge} =~ s/,/./;
            $settings{interval_charge} *= 100;
        } else {
            $messages{charge} = 'Client.Syntax.CashValue';
        }
    } else {
        $settings{interval_charge} = 0;
    }

    $settings{interval_free_time} = $c->request->params->{interval_free_time};
    if(length $settings{interval_free_time}) {
        $messages{free_time} = 'Client.Syntax.TimeValue'
            unless $settings{interval_free_time} =~ /^[+]?\d+$/;
        $settings{interval_free_time} =~ s/^\+//;
    } else {
        $settings{interval_free_time} = 0;
    }

    $settings{interval_free_cash} = $c->request->params->{interval_free_cash};
    if(length $settings{interval_free_cash}) {
        if($settings{interval_free_cash} =~ /^[+]?\d+(?:[.,]\d\d?)?$/) {
            $settings{interval_free_cash} =~ s/,/./;
            $settings{interval_free_cash} *= 100;
        } else {
            $messages{free_cash} = 'Client.Syntax.CashValue';
        }
    } else {
        $settings{interval_free_cash} = 0;
    }


    unless(keys %messages) {
        if($bilprof) {
            if($c->model('Provisioning')->call_prov( $c, 'billing', 'update_billing_profile',
                                                     { handle => $bilprof,
                                                       data   => \%settings,
                                                     },
                                                     undef))
            {
                $messages{profmsg} = 'Web.Bilprof.Updated';
                $c->session->{messages} = \%messages;
                $c->response->redirect("/billing#bilprof");
                return;
            }
            $c->session->{restore_bilprof_input} = \%settings;
            $c->response->redirect("/billing/edit_bilprof?bilprof=$bilprof");
            return;
        } else {
            if($c->model('Provisioning')->call_prov( $c, 'billing', 'create_billing_profile',
                                                     { handle => $handle,
                                                       data   => \%settings,
                                                     },
                                                     undef))
            {
                $messages{profmsg} = 'Web.Bilprof.Created';
                $c->session->{messages} = \%messages;
                $c->response->redirect("/billing#bilprof");
                return;
            }
            $c->session->{restore_bilprof_input} = \%settings;
            $c->response->redirect("/billing/edit_bilprof?handle=$handle");
            return;
        }
    }

    $c->session->{messages} = \%messages;
    $c->session->{restore_bilprof_input} = \%settings;
    if($bilprof) {
        $c->response->redirect("/billing/edit_bilprof?bilprof=$bilprof");
    } else {
        $c->response->redirect("/billing/edit_bilprof?handle=$handle");
    }
    return;
}

=head2 do_delete_bilprof

Delete a billing profile from the database.

=cut

sub do_delete_bilprof : Local {
    my ( $self, $c ) = @_;

    my $bilprof = $c->request->params->{bilprof};

    if($bilprof) {
        if($c->model('Provisioning')->call_prov( $c, 'billing', 'delete_billing_profile',
                                                 { handle => $bilprof },
                                                 undef))
        {
            $c->session->{messages} = { profmsg => 'Web.Bilprof.Deleted' };
            $c->response->redirect("/billing#bilprof");
            return;
        }
    }

    $c->response->redirect("/billing");
    return;
}

=head2 search_fees

Search billing profile fees and display the result.

=cut

sub search_fees : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/billing_fees.tt';

    my $bilprof = $c->request->params->{bilprof};

    return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_billing_profile',
                                                        { handle => $bilprof },
                                                        \$c->stash->{bilprof}
                                                      );

    my $limit = 10;
    my %filter;
    my %exact;

    if($c->request->params->{use_session}) {
        %filter = %{ $c->session->{search_filter} };
        %exact = %{ $c->session->{exact_filter} };
        $c->stash->{feeerr} = $c->session->{feeerr};
        delete $c->session->{feeerr};
    } else {
        foreach my $sf (qw(destination zone zone_detail)) {
            if((    defined $c->request->params->{'search_'.$sf}
                and length $c->request->params->{'search_'.$sf})
               or $c->request->params->{'exact_'.$sf})
            {
                $filter{$sf} = $c->request->params->{'search_'.$sf} || '';
                $exact{$sf} = 1 if $c->request->params->{'exact_'.$sf};
            }
        }
        $c->session->{search_filter} = { %filter };
        $c->session->{exact_filter} = { %exact };
    }

    foreach my $sf (qw(destination zone zone_detail)) {
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

    my $offset = $c->request->params->{offset} || 0;
    $offset = 0 if $offset !~ /^\d+$/;

    my $fee_list;
    return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'search_billing_profile_fees',
                                                        { handle => $bilprof,
                                                          filter => { %filter,
                                                                      limit    => $limit,
                                                                      offset   => $limit * $offset,
                                                                    },
                                                        },
                                                        \$fee_list
                                                      );

    $c->stash->{searched} = 1;
    if(ref $$fee_list{fees} eq 'ARRAY' and @{$$fee_list{fees}}) {
        $c->stash->{fee_list} = $$fee_list{fees};
        $c->stash->{total_count} = $$fee_list{total_count};
        $c->stash->{offset} = $offset;
        if($$fee_list{total_count} > @{$$fee_list{fees}}) {
            # paginate!
            $c->stash->{pagination} = admin::Utils::paginate($c, $fee_list, $offset, $limit);
            $c->stash->{max_offset} = $#{$c->stash->{pagination}};
            if(@{$$fee_list{fees}} == 1) {
                $c->stash->{last_one} = 1;
            }
        }
    }

    return 1;
}

=head2 set_fees

Set billing profile fees from CSV data.

=cut

sub set_fees : Local {
    my ( $self, $c ) = @_;

    my %messages;
    my @fees;

    my $upload = $c->req->upload('upload_fees');
    $messages{feefileerr} = 'Web.Fees.MissingFilename' unless defined $upload;
    my $fees = eval { $upload->slurp };

    my $bilprof = $c->request->params->{bilprof};
    my $purge = $c->request->params->{purge_existing} ? 1 : 0;
    my $offset = $c->request->params->{offset} || 0;

    my @elements = eval { @{$c->config->{fees_csv}{element_order}} };

    my $line = 0;
    foreach my $fee (split /\r?\n/, $fees) {
        $line++;
        my %keyval;
        my @values = map { length $_ ? $_ : undef } split / *, */, $fee;
        unless(@elements == @values) {
            $messages{feeerr} = 'Web.Fees.Fieldcount';
            $c->session->{feeerr}{line} = $line;
            $messages{feeerrdetail} = 'Web.Fees.FieldsFoundRequired';
            $c->session->{feeerr}{detail} = scalar(@values) . '/' . scalar(@elements);
            last;
        }
        @keyval{@elements} = @values;
        if($keyval{destination} =~ /^\d+$/) {
            $keyval{destination} = '^'. $keyval{destination} .'.*$';
        } elsif($keyval{destination} =~ /^(?:[a-z0-9]+(?:-[a-z0-9]+)*\.)+[a-z]+$/i
                or $keyval{destination} =~ /^[\d.]+$/)
        {
            $keyval{destination} = '^.*@'. $keyval{destination} .'$';
        } elsif($keyval{destination} =~ /^.+\@(?:[a-z0-9]+(?:-[a-z0-9]+)*\.)+[a-z]+$/i
                or $keyval{destination} =~ /^.+\@[\d.]+$/)
        {
            $keyval{destination} = '^'. $keyval{destination} .'$';
        } else {
            $messages{feeerr} = 'Web.Fees.InvalidDestination';
            $c->session->{feeerr}{line} = $line;
            last;
        }
        push @fees, \%keyval;
    }

    unless(keys %messages) {
        if($c->model('Provisioning')->call_prov( $c, 'billing', 'set_billing_profile_fees',
                                                 { handle => $bilprof,
                                                   fees   => \@fees,
                                                   purge_existing => $purge,
                                                 },
                                                 undef))
        {
            $messages{feemsg} = 'Web.Bilprof.Updated';
            $c->session->{messages} = \%messages;
            $c->response->redirect("/billing/search_fees?bilprof=$bilprof&use_session=1&offset=$offset");
            return;
        }
    }
    $c->session->{messages} = \%messages;

    # TODO: add offset?
    $c->response->redirect("/billing/search_fees?bilprof=$bilprof&use_session=1&offset=$offset");
    return;
}

=head2 edit_fee

Display a billing profile fee entry and allow the user to make changes.

=cut

sub edit_fee : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/fee_edit.tt';

    my $bilprof = $c->stash->{bilprof} = $c->request->params->{bilprof};
    my $destination = $c->stash->{destination} = $c->request->params->{destination};
    $c->stash->{offset} = $c->request->params->{offset} || 0;

    if(ref $c->session->{restore_fee_input} eq 'HASH') {
        $c->stash->{fee} = $c->session->{restore_fee_input};
        delete $c->session->{restore_fee_input};
    } else {
        my $fee_list;
        return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'search_billing_profile_fees',
                                                            { handle => $bilprof,
                                                              filter => { destination => $destination },
                                                            },
                                                            \$fee_list
                                                          );

        $c->stash->{searched} = 1;
        if(ref $$fee_list{fees} eq 'ARRAY' and @{$$fee_list{fees}}) {
            if(@{$$fee_list{fees}} > 1) {
                $c->session->{messages}{feeerr} = 'Web.Fees.DuplicatedDestination';
            } else {
                $c->stash->{fee} = $$fee_list{fees}[0];
            }
        } else {
            $c->session->{messages}{feeerr} = 'Web.Fees.NoSuchDestination';
        }
    }

    return 1;
}

=head2 do_edit_fee

Update a billing profile fee entry.

=cut

sub do_edit_fee : Local {
    my ( $self, $c ) = @_;

    my %messages;
    my %settings;

    my $bilprof = $c->request->params->{bilprof};
    my $offset = $c->request->params->{offset};
    $settings{destination} = $c->request->params->{destination};
    if(defined $c->request->params->{new_destination}) {
        $settings{destination} = $c->request->params->{new_destination};
    }
    $settings{zone} = $c->request->params->{zone};
    $settings{zone_detail} = $c->request->params->{zone_detail};
    $settings{onpeak_init_rate} = $c->request->params->{onpeak_init_rate};
    $settings{onpeak_init_interval} = $c->request->params->{onpeak_init_interval};
    $settings{onpeak_follow_rate} = $c->request->params->{onpeak_follow_rate};
    $settings{onpeak_follow_interval} = $c->request->params->{onpeak_follow_interval};
    $settings{offpeak_init_rate} = $c->request->params->{offpeak_init_rate};
    $settings{offpeak_init_interval} = $c->request->params->{offpeak_init_interval};
    $settings{offpeak_follow_rate} = $c->request->params->{offpeak_follow_rate};
    $settings{offpeak_follow_interval} = $c->request->params->{offpeak_follow_interval};
    $settings{use_free_time} = $c->request->params->{use_free_time} ? 1 : 0;

    for(qw(onpeak_init_rate onpeak_init_interval onpeak_follow_rate onpeak_follow_interval
           offpeak_init_rate offpeak_init_interval offpeak_follow_rate offpeak_follow_interval))
    {
        $settings{$_} = undef unless length $settings{$_};
    }

    if($c->model('Provisioning')->call_prov( $c, 'billing', 'set_billing_profile_fees',
                                             { handle => $bilprof,
                                               fees   => [ \%settings ],
                                               purge_existing => 0,
                                             },
                                             undef))
    {
        $c->session->{messages}{stfeemsg} = 'Web.Bilprof.Updated';
        $c->response->redirect("/billing/search_fees?bilprof=$bilprof&use_session=1&offset=$offset#stored");
        return;
    }

    $c->session->{restore_fee_input} = \%settings;
    $c->response->redirect("/billing/edit_fee?bilprof=$bilprof&offset=$offset");
    return;
}

=head2 do_delete_fee

Delete a billing profile fee entry.

=cut

sub do_delete_fee : Local {
    my ( $self, $c ) = @_;

    my $bilprof = $c->request->params->{bilprof};
    my $destination = $c->request->params->{destination};
    my $offset = $c->request->params->{offset};

    if($c->model('Provisioning')->call_prov( $c, 'billing', 'set_billing_profile_fees',
                                             { handle => $bilprof,
                                               fees   => [ { destination => $destination } ],
                                               purge_existing => 0,
                                             },
                                             undef))
    {
        $c->session->{messages}{stfeemsg} = 'Web.Bilprof.Updated';
        $offset-- if $c->request->params->{last_one};
        $c->response->redirect("/billing/search_fees?bilprof=$bilprof&use_session=1&offset=$offset#stored");
        return;
    }

    $c->response->redirect("/billing/search_fees?bilprof=$bilprof&use_session=1&offset=$offset");
    return;
}


=head1 BUGS AND LIMITATIONS

=over

=item functions are missing some syntax checks

=back

=head1 SEE ALSO

Provisioning model, Sipwise::Provisioning::Billing, Catalyst

=head1 AUTHORS

Daniel Tiefnig <dtiefnig@sipwise.com>

=head1 COPYRIGHT

The billing controller is Copyright (c) 2009 Sipwise GmbH, Austria. All
rights reserved.

=cut

# ende gelaende
1;
