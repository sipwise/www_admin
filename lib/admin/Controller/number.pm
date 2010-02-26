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

    my $blocks;
    return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_number_blocks',
                                                        { filter => { limit  => $limit,
                                                                      offset => $limit * $offset,
                                                                    },
                                                        },
                                                        \$blocks
                                                      );

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
        foreach my $block (eval { @$blocks }) {
            if($$block{cc} == $c->stash->{edit_cc}
               and $$block{ac} == $c->stash->{edit_ac}
               and $$block{sn_prefix} == $c->stash->{edit_sn_prefix})
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
            $c->response->redirect("/number?offset=$offset#create_block");
            return;
        }
        $c->session->{crefill} = \%settings;
        $c->response->redirect("/number?offset=$offset#create_block");
        return;
    }

    $messages{cblockerr} = 'Client.Voip.InputErrorFound';
    $c->session->{messages} = \%messages;
    $c->session->{crefill} = \%settings;
    $c->response->redirect("/number?offset=$offset#create_block");
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
            $c->response->redirect("/number?offset=$offset#existing_blocks");
            return;
        }
        $c->session->{erefill} = \%settings;
        $c->response->redirect("/number?edit_cc=$settings{cc}&amp;edit_ac=$settings{ac}&amp;edit_sn_prefix=$settings{sn_prefix}&amp;offset=$offset#existing_blocks");
        return;
    }

    $messages{eblockerr} = 'Client.Voip.InputErrorFound';
    $c->session->{messages} = \%messages;
    $c->session->{erefill} = \%settings;
    $c->response->redirect("/number?edit_cc=$settings{cc}&amp;edit_ac=$settings{ac}&amp;edit_sn_prefix=$settings{sn_prefix}&amp;offset=$offset#existing_blocks");
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
        $c->response->redirect("/number?offset=$offset#existing_blocks");
        return;
    }

    $c->response->redirect("/number?offset=$offset#existing_blocks");
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
