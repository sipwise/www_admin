package admin;

use strict;
use warnings;

use Catalyst::Runtime '5.70';
use XML::Simple;

# Set flags and add plugins for the application
#
#         -Debug: activates the debug mode for very useful log messages
#   ConfigLoader: will load the configuration from a YAML file in the
#                 application's home directory
# Static::Simple: will serve static files from the application's root 
#                 directory

use Catalyst::Log::Log4perl;

use Catalyst qw/ConfigLoader Static::Simple Unicode
                Authentication Authentication::Store::Minimal Authentication::Credential::Password
                Session Session::Store::FastMmap Session::State::Cookie
               /;

our $VERSION = '3.3';

# Configure the application. 
#
# Note that settings in admin.yml (or other external
# configuration file that you set up manually) take precedence
# over this when using ConfigLoader. Thus configuration
# details given here can function as a default configuration,
# with a external configuration file acting as an override for
# local deployment.

# load configuration from admin.conf XML
my $xs = new XML::Simple;
my $xc = $xs->XMLin( '/etc/ngcp-www-admin/admin.conf', ForceArray => 0);

__PACKAGE__->config(session => { flash_to_stash => 1 });

__PACKAGE__->config( %$xc );
__PACKAGE__->config( 'Plugin::Authentication' => {
        default_realm => 'default',
        default => {
                credential => {
                },
                store => {
                }
        },
});

if(__PACKAGE__->config->{log4perlconf}) {
  __PACKAGE__->log( Catalyst::Log::Log4perl->new(
      __PACKAGE__->config->{log4perlconf}
  ));
}

sub debug {
  return __PACKAGE__->config->{debugging} ? 1 : 0;
}

# Start the application
__PACKAGE__->setup;

=head1 NAME

admin - Catalyst based application

=head1 DESCRIPTION

The core module of the administration framework.

=head1 BUGS AND LIMITATIONS

=over

=item none so far

=back

=head1 SEE ALSO

L<admin::Controller::Root>, L<Catalyst>

=head1 AUTHORS

Daniel Tiefnig <dtiefnig@sipwise.com>

=head1 COPYRIGHT

The admin module is Copyright (c) 2007-2010 Sipwise GmbH, Austria. You
should have received a copy of the licences terms together with the
software.

=cut

1;
