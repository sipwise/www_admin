package admin::Controller::billing;

use strict;
use warnings;
use base 'Catalyst::Controller';

my @WEEKDAYS = qw(Sunday Monday Tuesday Wednesday Thursday Friday Saturday);

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

    $c->stash->{field_order} = join ', ', eval { @{$c->config->{fees_csv}{element_order}} };

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
        foreach(@{$$fee_list{fees}}) {
            $$_{destination} = $self->_denormalize_destination($c, $$_{destination});
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
        $keyval{destination} = $self->_normalize_destination($c, $keyval{destination});
        unless(defined $keyval{destination}) {
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

    $destination = $self->_normalize_destination($c, $destination)
        if defined $destination;

    if(ref $c->session->{restore_fee_input} eq 'HASH') {
        $c->stash->{fee} = $c->session->{restore_fee_input};
        delete $c->session->{restore_fee_input};
    } elsif(defined $destination) {
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
                $c->stash->{fee}{destination} = $self->_denormalize_destination($c, $c->stash->{fee}{destination});
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
    $settings{destination} = $self->_normalize_destination($c, $settings{destination})
        if defined $settings{destination};
    if(defined $c->request->params->{new_destination}) {
        $settings{destination} = $self->_normalize_destination($c, $c->request->params->{new_destination});
        unless(defined $settings{destination}) {
            $messages{destination} = 'Web.Fees.InvalidDestination';
        }
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

    $settings{destination} = $self->_denormalize_destination($c, $settings{destination})
        if defined $settings{destination};
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

    $destination = $self->_normalize_destination($c, $destination);

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

=head2 show_peaktimes

Shows the lists of offpeak times.

=cut

sub show_peaktimes : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/peaktimes.tt';

    my $bilprof = $c->request->params->{bilprof};
    return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_billing_profile',
                                                        { handle => $bilprof },
                                                        \$c->stash->{bilprof}
                                                      );

    my $edit_weekday = $c->request->params->{edit_weekday};
    $c->stash->{edit_weekday} = $edit_weekday
        if defined $edit_weekday;

    my $show_year = $c->request->params->{show_year};
    $c->stash->{show_year} = $show_year
        if defined $show_year;
    my $edit_date = $c->request->params->{edit_date};
    $c->stash->{edit_date} = $edit_date
        if defined $edit_date;

    my $peaktimes;
    return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_billing_profile_offpeak_times',
                                                        { handle => $bilprof },
                                                        \$peaktimes
                                                      );
    my @weekdays;
    for(0 .. 6) {
        $weekdays[$_] = { name => $WEEKDAYS[$_] };
    }
    $$peaktimes{weekdays} = [] unless defined eval { @{$$peaktimes{weekdays}} };
    foreach (sort { $$a{day} <=> $$b{day} } @{$$peaktimes{weekdays}}) {
        if(defined $c->session->{restore_peaktimes}
           and defined $edit_weekday and $$_{day} == $edit_weekday)
        {
            my $rpt = $c->session->{restore_peaktimes};
            if(defined $$rpt{startold} or defined $$rpt{endold}) {
                for(eval { @{$$_{ranges}} }) {
                    if($$_{start} eq $$rpt{startold} and $$_{end} eq $$rpt{endold}) {
                        $$_{restore_start} = $$rpt{start};
                        $$_{restore_end} = $$rpt{end};
                    }
                }
            } else {
                $c->stash->{newrange}{start} = $$rpt{start};
                $c->stash->{newrange}{end} = $$rpt{end};
            }
        }
        $weekdays[$$_{day}]{ranges} = $$_{ranges};
    }
    $c->stash->{offpeaktimes}{weekdays} = \@weekdays;

    if(defined eval { @{$$peaktimes{special}} }) {
        my @dates;
        my %years;
        for(sort { $$a{date} cmp $$b{date} } @{$$peaktimes{special}}) {
            my $year = (split /-/, $$_{date})[0];
            $years{$year} = 0;
            if($year == $show_year) {
                push @dates, { date => $$_{date}, ranges => [ sort { $$a{start} cmp $$b{start} } eval { @{$$_{ranges}} } ]};
            }
        }
        $c->stash->{years} = [ reverse sort keys %years ];
        $c->stash->{dates} = \@dates if @dates;
    }

    if(defined $c->session->{restore_peaktimes} and $edit_date eq 'new') {
        my $rpt = $c->session->{restore_peaktimes};
        $c->stash->{newrange}{start} = $$rpt{start};
        $c->stash->{newrange}{end} = $$rpt{end};
        $c->stash->{newrange}{date} = $$rpt{date};
    }

    delete $c->session->{restore_peaktimes};
    return 1;
}

=head2 do_edit_peaktime

Modifies a peaktime range entry in the database or creates a new one.

=cut

sub do_edit_peaktime : Local {
    my ( $self, $c ) = @_;

    my %messages;

    my $bilprof = $c->request->params->{bilprof};
    my $weekday = $c->request->params->{weekday};
    my $show_year = $c->request->params->{show_year};
    my $date = $c->request->params->{date};
    my $edit_date = $c->request->params->{edit_date};
    my $start = $c->request->params->{start};
    my $end = $c->request->params->{end};
    my $startold = $c->request->params->{startold};
    my $endold = $c->request->params->{endold};

    my $delete = 0;
    if(!defined $start and !defined $end) {
        $delete = 1;
    } else {
        if($start) {
            $messages{epeakerr} = 'Client.Syntax.MalformedDaytime' unless $start =~ /^(?:[01]?\d|2[0-3]):[0-5]?\d:[0-5]?\d$/
        } else {
            $start = '00:00:00';
        }
        if($end) {
            $messages{epeakerr} = 'Client.Syntax.MalformedDaytime' unless $end =~ /^(?:[01]?\d|2[0-3]):[0-5]?\d:[0-5]?\d$/
        } else {
            $end = '23:59:59';
        }
    }

    if(defined $date) {
        $messages{epeakerr} = 'Client.Syntax.Date' unless $date =~ /^\d{4}-\d\d-\d\d$/;
        $c->response->redirect("/billing/show_peaktimes?bilprof=$bilprof&show_year=$show_year&edit_date=". ($edit_date ? $edit_date : $date) ."#special");
    } else {
        $c->response->redirect("/billing/show_peaktimes?bilprof=$bilprof&edit_weekday=$weekday");
    }

    my $peaktimes;
    return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_billing_profile_offpeak_times',
                                                        { handle => $bilprof },
                                                        \$peaktimes
                                                      );

    my @oldpeaktimes;
    if(defined $weekday) {
        for(eval { @{$$peaktimes{weekdays}} }) {
            if($$_{day} == $weekday) {
                @oldpeaktimes = eval { @{$$_{ranges}} };
                last;
            }
        }
    } else {
        for(eval { @{$$peaktimes{special}} }) {
            if($$_{date} eq $date) {
                @oldpeaktimes = eval { @{$$_{ranges}} };
                last;
            }
        }
    }

    if($startold and $endold) {
        @oldpeaktimes = grep { !($$_{start} eq $startold and $$_{end} eq $endold) and
                               !($$_{start} eq $start and $$_{end} eq $end) } @oldpeaktimes;
    } else {
        @oldpeaktimes = grep { !($$_{start} eq $start and $$_{end} eq $end) } @oldpeaktimes;
    }

    unless(keys %messages) {
        if($c->model('Provisioning')->call_prov( $c, 'billing', 'set_billing_profile_offpeak_times',
                                                 { handle        => $bilprof,
                                                   offpeak_times => {
                                                       (defined $weekday ? 'weekdays' : 'special') => [
                                                           {
                                                             defined $weekday ? ('day'  => $weekday)
                                                                              : ('date' => $date),
                                                             ranges => [
                                                                 @oldpeaktimes,
                                                                 ($delete ? () : 
                                                                   {
                                                                     start => $start,
                                                                     end   => $end,
                                                                   }
                                                                 ),
                                                             ]
                                                           },
                                                       ],
                                                   }
                                                 },
                                                 undef))
        {
            if(defined $edit_date and $edit_date eq 'new') {
                my $year = (split /-/, $date)[0];
                $c->response->redirect("/billing/show_peaktimes?bilprof=$bilprof&show_year=$year#special");
            }
            $messages{epeakmsg} = 'Web.Fees.SavedPeaktimes';
            $c->session->{messages} = \%messages;
            return;
        }
    }

    $c->session->{messages} = \%messages;
    $c->session->{restore_peaktimes} = {
        date  => $date,
        start => $start, end => $end,
        startold => $startold, endold => $endold
    };
    return;
}

sub _normalize_destination : Private {
    my ($self, $c, $destination) = @_;

    if($destination =~ /^\d+$/) {
        $destination = '^' . $destination . '.*$';
    } elsif($destination =~ /^(?:[a-z0-9]+(?:-[a-z0-9]+)*\.)+[a-z]+$/i
            or $destination =~ /^[\d.]+$/)
    {
        $destination =~ s/\./\\./g;
        $destination = '^.*@'. $destination .'$';
    } elsif($destination =~ /^.+\@(?:[a-z0-9]+(?:-[a-z0-9]+)*\.)+[a-z]+$/i
            or $destination =~ /^.+\@[\d.]+$/)
    {
        $destination =~ s/\./\\./g;
        $destination = '^'. $destination .'$';
    } else {
        return undef;
    }

    return $destination;
}

sub _denormalize_destination : Private {
    my ($self, $c, $destination) = @_;

    $destination =~ s/\\\././g;
    $destination =~ s/\$$//;
    $destination =~ s/^\^//;
    $destination =~ s/\.\*$//;
    $destination =~ s/^\.\*\@//;

    return $destination;
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
