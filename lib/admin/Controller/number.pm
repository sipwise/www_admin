package admin::Controller::number;

use strict;
use warnings;
use base 'Catalyst::Controller';

=head1 NAME

admin::Controller::number - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=head2 index

Display and edit local number blocks.

=cut

sub index : Private {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/number.tt';

    my $limit = 10;
    my $offset = $c->request->params->{offset} || 0;
    $offset = 0 if $offset !~ /^\d+$/;

    my %filter;
    my %exact;     

    if($c->request->params->{use_session}) {
        %filter = %{ $c->session->{search_filter} }
            if defined $c->session->{search_filter};
        %exact = %{ $c->session->{exact_filter} }
            if defined $c->session->{exact_filter};
    } else {
        foreach my $sf (qw(cc ac sn_prefix)) {
            if(   defined $c->request->params->{'search_'.$sf}
               and length $c->request->params->{'search_'.$sf})
               
            {
                $filter{$sf} = $c->request->params->{'search_'.$sf};
                $exact{$sf} = 1 if $c->request->params->{'exact_'.$sf};
            }
        }
        $filter{sn_length} = $c->request->params->{search_sn_length}
            if defined $c->request->params->{search_sn_length} and
               length $c->request->params->{search_sn_length};
        $filter{authoritative} = $c->request->params->{search_authoritative}
            if defined $c->request->params->{search_authoritative} and
               $c->request->params->{search_authoritative} =~ /^0|1$/;
        $filter{allocable} = $c->request->params->{search_allocable}
            if defined $c->request->params->{search_allocable} and
               $c->request->params->{search_allocable} =~ /^0|1$/;

        $c->session->{search_filter} = { %filter };
        $c->session->{exact_filter} = { %exact };
    }

    foreach my $sf (qw(cc ac sn_prefix)) {
        next unless defined $filter{$sf};

        # set values for webform
        $c->stash->{'exact_'.$sf} = $exact{$sf};
        $c->stash->{'search_'.$sf} = $filter{$sf};

        # alter filter for SOAP call
        $filter{$sf} =~ s/\*/\%/g;
        $filter{$sf} =~ s/\?/\_/g;
        unless($exact{$sf}) {
            $filter{$sf} =~ s/^\%*/\%/;
            $filter{$sf} =~ s/\%*$/\%/;
        }
    }
    $c->stash->{search_sn_length} = $filter{sn_length};
    $c->stash->{search_authoritative} = $filter{authoritative};
    $c->stash->{search_allocable} = $filter{allocable};

    my $blocks;
    do {
        return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_number_blocks',
                                                            { filter => { %filter,
                                                                          limit  => $limit,
                                                                          offset => $limit * $offset,
                                                                        },
                                                            },
                                                            \$blocks
                                                          );
    } until eval { @{$$blocks{number_blocks}} } or --$offset < 0;

    if(eval { @{$$blocks{number_blocks}} }) {
        $c->stash->{blocks} = $$blocks{number_blocks};
        $c->stash->{total_count} = $$blocks{total_count};
        $c->stash->{offset} = $offset;

        if($$blocks{total_count} > @{$$blocks{number_blocks}})  {
            # paginate!
            $c->stash->{pagination} = admin::Utils::paginate($$blocks{total_count}, $offset, $limit);
            $c->stash->{max_offset} = $#{$c->stash->{pagination}};
            if(@{$$blocks{number_blocks}} == 1) {
                $c->stash->{last_one} = 1;
            }
        }
    }


    $c->stash->{edit_cc} = $c->request->params->{edit_cc};
    $c->stash->{edit_ac} = $c->request->params->{edit_ac};
    $c->stash->{edit_sn_prefix} = $c->request->params->{edit_sn_prefix};

    if(exists $c->session->{crefill}) {
        $c->stash->{crefill} = $c->session->{crefill};
        delete $c->session->{crefill};
    }
    if(exists $c->session->{erefill}) {
        $c->stash->{erefill} = $c->session->{erefill};
        delete $c->session->{erefill};
    } elsif($c->request->params->{edit_cc}) {
        foreach my $block (eval { @{$$blocks{number_blocks}} }) {
            if($$block{cc} == $c->stash->{edit_cc}
               and $$block{ac} == $c->stash->{edit_ac}
               and $$block{sn_prefix} eq $c->stash->{edit_sn_prefix})
            {
                $c->stash->{erefill} = $block;
                last;
            }
        }
    }

    return 1;
}

=head2 do_create_block

Create a new number block in the database.

=cut

sub do_create_block : Local {
    my ( $self, $c ) = @_;

    my %messages;
    my %settings;

    my $offset = $c->request->params->{offset} || 0;

    $settings{cc} = $c->request->params->{cc};
    $settings{ac} = $c->request->params->{ac};
    $settings{sn_prefix} = $c->request->params->{sn_prefix};
    $settings{data}{sn_length} = $c->request->params->{sn_length};
    $settings{data}{allocable} = $c->request->params->{allocable} ? 1 : 0;
    $settings{data}{authoritative} = $c->request->params->{authoritative} ? 1 : 0;

    unless(keys %messages) {
        if($c->model('Provisioning')->call_prov( $c, 'billing', 'create_number_block',
                                                 \%settings,
                                                 undef))
        {
            $messages{cblockmsg} = 'Web.NumberBlock.Created';
            $c->session->{messages} = \%messages;
            $c->response->redirect("/number?offset=$offset&amp;use_session=1#create_block");
            return;
        }
        $c->session->{crefill} = \%settings;
        $c->response->redirect("/number?offset=$offset&amp;use_session=1#create_block");
        return;
    }

    $messages{cblockerr} = 'Client.Voip.InputErrorFound';
    $c->session->{messages} = \%messages;
    $c->session->{crefill} = \%settings;
    $c->response->redirect("/number?offset=$offset&amp;use_session=1#create_block");
    return;
}

=head2 do_update_block

Update settings of a number block in the database.

=cut

sub do_update_block : Local {
    my ( $self, $c ) = @_;

    my %messages;
    my %settings;

    my $offset = $c->request->params->{offset} || 0;

    $settings{cc} = $c->request->params->{cc};
    $settings{ac} = $c->request->params->{ac};
    $settings{sn_prefix} = $c->request->params->{sn_prefix};
    unless(length $settings{cc} and length $settings{ac}) {
        $c->response->redirect("/number");
        return;
    }
    $settings{data}{allocable} = $c->request->params->{allocable} ? 1 : 0;
    $settings{data}{authoritative} = $c->request->params->{authoritative} ? 1 : 0;

    unless(keys %messages) {
        if($c->model('Provisioning')->call_prov( $c, 'billing', 'update_number_block',
                                                 \%settings,
                                                 undef))
        {
            $messages{eblockmsg} = 'Web.NumberBlock.Updated';
            $c->session->{messages} = \%messages;
            $c->response->redirect("/number?offset=$offset&amp;use_session=1#existing_blocks");
            return;
        }
        $c->session->{erefill} = \%settings;
        $c->response->redirect("/number?edit_cc=$settings{cc}&amp;edit_ac=$settings{ac}&amp;edit_sn_prefix=$settings{sn_prefix}&amp;offset=$offset&amp;use_session=1#existing_blocks");
        return;
    }

    $messages{eblockerr} = 'Client.Voip.InputErrorFound';
    $c->session->{messages} = \%messages;
    $c->session->{erefill} = \%settings;
    $c->response->redirect("/number?edit_cc=$settings{cc}&amp;edit_ac=$settings{ac}&amp;edit_sn_prefix=$settings{sn_prefix}&amp;offset=$offset&amp;use_session=1#existing_blocks");
    return;
}

=head2 do_delete_block

Delete a number block from the database.

=cut

sub do_delete_block : Local {
    my ( $self, $c ) = @_;

    my %settings;

    my $offset = $c->request->params->{offset} || 0;

    $settings{cc} = $c->request->params->{cc};
    $settings{ac} = $c->request->params->{ac};
    $settings{sn_prefix} = $c->request->params->{sn_prefix};
    unless(length $settings{cc} and length $settings{ac}) {
        $c->response->redirect("/number");
        return;
    }

    if($c->model('Provisioning')->call_prov( $c, 'billing', 'delete_number_block',
                                             \%settings,
                                             undef))
    {
        $c->session->{messages} = { eblockmsg => 'Web.NumberBlock.Deleted' };
        $c->response->redirect("/number?offset=$offset&amp;use_session=1#existing_blocks");
        return;
    }

    $c->response->redirect("/number?offset=$offset&amp;use_session=1#existing_blocks");
    return;
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

The number controller is Copyright (c) 2010 Sipwise GmbH, Austria. All
rights reserved.

=cut

# ende gelaende
1;
