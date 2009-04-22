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
