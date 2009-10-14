package admin::View::Plain;

use strict;

=head1 NAME

admin::View::Plain - TT View for plain text

=head1 DESCRIPTION

Plain View for admin. It will output plain data with the corresponding
content-type header set.

=cut

sub new {
    return bless {}, shift;
}

sub process {
    my ( $self, $c ) = @_;

    $c->response->content_type($c->stash->{content_type});
    $c->response->body($c->stash->{content});

    return 1;
}

=head1 BUGS AND LIMITATIONS

=over

=item none I know.

=back

=head1 SEE ALSO

Catalyst, admin

=head1 AUTHORS

Daniel Tiefnig <dtiefnig@sipwise.com>
Andreas Granig <agranig@sipwise.com>

=head1 COPYRIGHT

The Plain view is Copyright (c) 2009 Sipwise GmbH, Austria. All rights
reserved.

=cut

# over and out
1;
