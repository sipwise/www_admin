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

    if($product) {
        return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_product',
                                                            { handle => $product },
                                                            \$c->stash->{product}
                                                          );
        $c->stash->{handle} = $product;
    }

    return 1;
}

=head2 do_edit_product

Change settings for a product in the database or create a new one.

=cut

sub do_edit_product : Local {
    my ( $self, $c ) = @_;

    my %messages;
    my %settings;

    my $product = $c->request->params->{product};

    my $handle = $c->request->params->{handle};

    $settings{class} = $c->request->params->{class};
    $settings{name} = $c->request->params->{name};
    $settings{on_sale} = $c->request->params->{on_sale} ? 1 : 0;
    $settings{price} = $c->request->params->{price} || undef;
    $settings{weight} = $c->request->params->{weight} || undef;
    $settings{billing_profile} = $c->request->params->{billing_profile} || undef;

    if($product) {
        if($c->model('Provisioning')->call_prov( $c, 'billing', 'update_product',
                                                 { handle => $product,
                                                   data   => \%settings,
                                                 },
                                                 undef))
        {
            $messages{prodmsg} = 'Server.Voip.SavedSettings';
            $c->session->{messages} = \%messages;
            $c->response->redirect("/billing#products");
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
            $messages{prodmsg} = 'Server.Voip.SavedSettings';
            $c->session->{messages} = \%messages;
            $c->response->redirect("/billing#products");
            return;
        }
        $c->session->{restore_product_input} = \%settings;
        $c->response->redirect("/billing/edit_product");
        return;
    }

}

=head1 BUGS AND LIMITATIONS

=over

=item missing product delete function

=item missing billing profile functions

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
