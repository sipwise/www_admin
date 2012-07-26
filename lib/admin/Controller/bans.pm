package admin::Controller::bans;

use strict;
use warnings;
use base 'Catalyst::Controller';

=head1 NAME

admin::Controller::bans - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

View banned IPs and Users

=head1 METHODS

=head2 index 

Edit sound sets.

=cut

sub base : Chained('/') PathPrefix CaptureArgs(0) {}

sub users : Chained('base') PathPart('users') Args(0) {
    my ($self, $c) = @_;

    $c->stash->{template} = 'tt/bans_users.tt';
    my $banned_users;

    return unless $c->model('Provisioning')->call_prov(
        $c,
        'voip',
        'get_banned_users',
        undef, # parameters
        \$banned_users,
    );

    $c->stash->{banned_users} = $banned_users;
}

sub ips : Chained('base') PathPart('ips') Args(0) {
    my ($self, $c) = @_;
    
    $c->stash->{template} = 'tt/bans_ips.tt';
    my $banned_ips;

    return unless $c->model('Provisioning')->call_prov(
        $c,
        'voip',
        'get_banned_ips',
        undef, # parameters
        \$banned_ips,
    );
    
    $c->stash->{banned_ips} = $banned_ips;
}

# Ends, some people will rob their mothers for the ends ...
1
