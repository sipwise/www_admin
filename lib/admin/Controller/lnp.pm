package admin::Controller::lnp;

use strict;
use warnings;
use base 'Catalyst::Controller';

=head1 NAME

admin::Controller::lnp - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=head2 index

Display and edit LNP providers and numbers.

=cut

sub index : Private {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/lnp.tt';

    my $providers;
    return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_lnp_providers',
                                                        undef,
                                                        \$providers
                                                      );
    $c->stash->{providers} = $providers if eval { @$providers };


    $c->stash->{edit_provider} = $c->request->params->{edit_provider};
    $c->stash->{edit_number} = $c->request->params->{edit_number};

    if(exists $c->session->{searched_lnp_numbers}) {
        $c->stash->{searched_numbers} = $c->session->{searched_lnp_numbers};
        $self->_do_search_numbers($c, $c->session->{searched_lnp_numbers})
            unless exists $c->session->{lnp_numbers}{numbers};
    }
    if(ref $c->session->{lnp_numbers}{numbers} eq 'ARRAY' and
       @{$c->session->{lnp_numbers}{numbers}})
    {
        my $nums = $c->session->{lnp_numbers};
        $c->stash->{numbers} = $$nums{numbers};
        $c->stash->{num_total_count} = $$nums{total_count};
        if($$nums{total_count} > @{$$nums{numbers}}) {
            # paginate!
            $c->stash->{pagination} =
                admin::Utils::paginate($$nums{total_count}, $c->session->{searched_lnp_numbers}{offset}, $c->session->{searched_lnp_numbers}{limit});
            $c->stash->{max_offset} = ${$c->stash->{pagination}}[-1]{offset};
            # delete_number will decrease offset if no number remains on current page
            if(@{$$nums{numbers}} == 1) {
                $c->stash->{last_one} = 1;
            }
        }
    }

    if(exists $c->session->{parefill}) {
        $c->stash->{parefill} = $c->session->{parefill};
        delete $c->session->{parefill};
    }
    if(exists $c->session->{narefill}) {
        $c->stash->{narefill} = $c->session->{narefill};
        delete $c->session->{narefill};
    }
    if(exists $c->session->{nerefill}) {
        $c->stash->{nerefill} = $c->session->{nerefill};
        delete $c->session->{nerefill};
    } elsif($c->request->params->{edit_number}) {
        foreach my $num (eval { @{$c->session->{lnp_numbers}{numbers}} }) {
            if($$num{id} == $c->request->params->{edit_number}) {
                $c->stash->{nerefill} = $num;
                last;
            }
        }
    }

    return 1;
}

=head2 do_create_provider

Create a new LNP provider in the database.

=cut

sub do_create_provider : Local {
    my ( $self, $c ) = @_;

    my %messages;
    my %settings;

    $settings{id} = $c->request->params->{id};
    unless(defined $settings{id} and $settings{id} =~ /^\d+$/) {
        $messages{paddidmsg} = 'Web.Syntax.ID';
    }
    $settings{name} = $c->request->params->{name};
    unless(length $settings{name}) {
        $messages{paddnamsg} = 'Web.Syntax.LNPProvName';
    }

    unless(keys %messages) {
        if($c->model('Provisioning')->call_prov( $c, 'billing', 'create_lnp_provider',
                                                 { %settings },
                                                 undef))
        {
            $messages{provmsg} = 'Web.LNPProvider.Created';
            $c->session->{messages} = \%messages;
            $c->response->redirect("/lnp");
            return;
        }
    }

    $messages{proverr} = 'Client.Voip.InputErrorFound';
    $c->session->{messages} = \%messages;
    $c->session->{parefill} = \%settings;
    $c->response->redirect("/lnp");
    return;
}

=head2 do_update_provider

Update settings of an LNP provider in the database.

=cut

sub do_update_provider : Local {
    my ( $self, $c ) = @_;

    my %messages;
    my %settings;

    my $provider = $c->request->params->{id};
    unless(defined $provider and $provider =~ /^\d+$/) {
        $c->response->redirect("/lnp");
        return;
    }
    my $name = $c->request->params->{name};
    unless(length $name) {
        $messages{peditnamsg} = 'Web.Syntax.LNPProvName';
    }

    unless(keys %messages) {
        if($c->model('Provisioning')->call_prov( $c, 'billing', 'update_lnp_provider',
                                                 { id   => $provider,
                                                   name => $name,
                                                 },
                                                 undef))
        {
            $messages{provmsg} = 'Web.LNPProvider.Updated';
            $c->session->{messages} = \%messages;
            delete $c->session->{lnp_numbers};
            $c->response->redirect("/lnp");
            return;
        }
        $c->response->redirect("/lnp?edit_provider=$provider");
        return;
    }

    $messages{proverr} = 'Client.Voip.InputErrorFound';
    $c->session->{messages} = \%messages;
    $c->response->redirect("/lnp?edit_provider=$provider");
    return;
}

=head2 do_delete_provider

Delete an LNP provider from the database.

=cut

sub do_delete_provider : Local {
    my ( $self, $c ) = @_;

    my $provider = $c->request->params->{id};
    unless(defined $provider and $provider =~ /^\d+$/) {
        $c->response->redirect("/lnp");
        return;
    }

    if($c->model('Provisioning')->call_prov( $c, 'billing', 'delete_lnp_provider',
                                             { id => $provider },
                                             undef))
    {
        $c->session->{messages} = { provmsg => 'Web.LNPProvider.Deleted' };
        delete $c->session->{lnp_numbers};
        $c->response->redirect("/lnp");
        return;
    }

    $c->response->redirect("/lnp");
    return;
}

=head2 search_numbers

Search LNP numbers in the database.

=cut

sub search_numbers : Local {
    my ( $self, $c ) = @_;

    my %filter;

    $filter{lnp_provider_id} = $c->request->params->{search_provid}
        if $c->request->params->{search_provid};
    $filter{number} = $c->request->params->{search_number}
        if $c->request->params->{search_number};
    $filter{exact_number} = $c->request->params->{exact_number};
    $filter{offset} = $c->request->params->{offset} || 0;
    $filter{limit} = 10;

    $self->_do_search_numbers($c, \%filter);
    $c->session->{searched_lnp_numbers} = \%filter;

    $c->response->redirect("/lnp#search_numbers");
    return;
}

=head2 do_create_number

Create a new ported number in the database.

=cut

sub do_create_number : Local {
    my ( $self, $c ) = @_;

    my %messages;
    my %settings;

    $settings{number} = $c->request->params->{number};
    $settings{number} =~ s/^00//;
    $settings{number} =~ s/^\+//;
    $settings{lnp_provider_id} = $c->request->params->{lnp_provider_id};
    $settings{start} = $c->request->params->{start}
        if $c->request->params->{start};
    $settings{end} = $c->request->params->{end}
        if $c->request->params->{end};

    unless(keys %messages) {
        if($c->model('Provisioning')->call_prov( $c, 'billing', 'create_lnp_number',
                                                 { data => \%settings },
                                                 undef))
        {
            $messages{cnumsg} = 'Web.LNPNumber.Created';
            $c->session->{messages} = \%messages;
            delete $c->session->{lnp_numbers};
            $c->response->redirect("/lnp#create_number");
            return;
        }
    }

    $c->session->{messages} = \%messages;
    $c->session->{narefill} = \%settings;
    $c->response->redirect("/lnp#create_number");
    return;
}

=head2 do_update_number

Update an existing ported number in the database.

=cut

sub do_update_number : Local {
    my ( $self, $c ) = @_;

    my %messages;
    my %settings;

    my $id = $c->request->params->{id};
    unless(defined $id and $id =~ /^\d+$/) {
        $c->response->redirect("/lnp");
        return;
    }

    $settings{number} = $c->request->params->{number};
    $settings{number} =~ s/^00//;
    $settings{number} =~ s/^\+//;
    $settings{lnp_provider_id} = $c->request->params->{lnp_provider_id};
    $settings{start} = $c->request->params->{start}
        if $c->request->params->{start};
    $settings{end} = $c->request->params->{end}
        if $c->request->params->{end};

    unless(keys %messages) {
        if($c->model('Provisioning')->call_prov( $c, 'billing', 'update_lnp_number',
                                                 { id   => $id,
                                                   data => \%settings
                                                 },
                                                 undef))
        {
            $messages{cnumsg} = 'Web.LNPNumber.Updated';
            $c->session->{messages} = \%messages;
            delete $c->session->{lnp_numbers};
            $c->response->redirect("/lnp#stored_numbers");
            return;
        }
    }

    $c->session->{messages} = \%messages;
    $c->session->{nerefill} = \%settings;
    $c->response->redirect("/lnp?edit_number=$id#stored_numbers");
    return;
}


=head2 do_delete_number

Delete a ported number from the database.

=cut

sub do_delete_number : Local {
    my ( $self, $c ) = @_;

    my $id = $c->request->params->{id};

    if($id and
       $c->model('Provisioning')->call_prov( $c, 'billing', 'delete_lnp_number',
                                             { id => $id },
                                             undef))
    {
        $c->session->{messages}{enumsg} = 'Web.LNPNumber.Deleted';
        $c->session->{searched_lnp_numbers}{offset}-- if $c->request->params->{last_one};
        delete $c->session->{lnp_numbers};
    }

    $c->response->redirect("/lnp#stored_numbers");
    return;
}

sub _do_search_numbers {
    my ( $self, $c, $filter ) = @_;

    my %sfilter;
    $sfilter{number} = $$filter{number} if defined $$filter{number};
    $sfilter{lnp_provider_id} = $$filter{lnp_provider_id} if defined $$filter{lnp_provider_id};
    $sfilter{number} = '%' . $sfilter{number} . '%' unless $$filter{exact_number};
    $sfilter{offset} = $$filter{offset} || 0;
    $sfilter{limit} = $$filter{limit};
    $sfilter{offset} *= $sfilter{limit};

    return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_lnp_numbers',
                                                        { filter => \%sfilter },
                                                        \$c->session->{lnp_numbers}
                                        );

    if(ref $c->session->{lnp_numbers}{numbers} eq 'ARRAY') {
        my $providers;
        return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_lnp_providers',
                                                            undef,
                                                            \$providers
                                                          );
        if(@$providers) {
            foreach my $num (@{$c->session->{lnp_numbers}{numbers}}) {
                for(@$providers) {
                    $$num{lnp_provider} = $$_{name}
                        if $$num{lnp_provider_id} == $$_{id};
                }
            }
        }
    }

    return 1;
}

=head1 BUGS AND LIMITATIONS

=over

=item none

=back

=head1 SEE ALSO

Provisioning model, Sipwise::Provisioning::Billing, Catalyst

=head1 AUTHORS

Daniel Tiefnig <dtiefnig@sipwise.com>

=head1 COPYRIGHT

The lnp controller is Copyright (c) 2009-2010 Sipwise GmbH, Austria. All
rights reserved.

=cut

# ende gelaende
1;
