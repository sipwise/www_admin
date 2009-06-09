package admin::View::Sipwise;

use strict;
use warnings;
use base 'Catalyst::View::TT';

=head1 NAME

admin::View::Sipwise - Sipwise Catalyst View for NGCP admin interface

=head1 DESCRIPTION

Sipwise Catalyst View for NGCP admin interface.

=cut

__PACKAGE__->config(
##    PRE_PROCESS  => 'config/main',
##    TEMPLATE_EXTENSION => '.tt',
    MACRO        => 'debug(message) CALL Catalyst.log.debug(message)',
    INCLUDE_PATH => [
        admin->path_to( 'root' ),
    ],
    WRAPPER      => 'layout/wrapper',
    ERROR        => 'tt/error.tt',
    CATALYST_VAR => 'Catalyst',
    VARIABLES    => {
        site_config  => {
            language        => 'en',
            language_string => 'English',
            css             => [ '/css/sipwise.css', '/css/admin.css' ],
            title           => 'Sipwise NGCP admin interface',
            company         => {
                                 name => 'Sipwise GmbH'
                               },
        },
    },
    ENCODING     => 'utf-8',
);

=head1 BUGS AND LIMITATIONS

=over

=item none.

=back

=head1 SEE ALSO

Catalyst

=head1 AUTHORS

Daniel Tiefnig <dtiefnig@sipwise.com>

=head1 COPYRIGHT

The Sipwise view is Copyright (c) 2007 Sipwise GmbH, Austria. All rights
reserved.

=cut

# over and out
1;
