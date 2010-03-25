package admin::Controller::xmlctrl;

use strict;
use warnings;
use base 'Catalyst::Controller';
use Data::Dumper;

=head1 NAME

admin::Controller::xmlctrl - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=head2 index

Display and edit XMLRPC control interfaces

=cut

sub index : Private {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/xmlctrl.tt';

    my $xmlhosts = undef;	
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_xmlctrl_hosts',
                                                        undef,
                                                        \$xmlhosts
                                                      );
    $c->stash->{xmlhosts} = $xmlhosts if eval { @$xmlhosts };
    
    my $xmlgroups = undef;	
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_xmlctrl_groups',
                                                        undef,
                                                        \$xmlgroups
                                                      );
    $c->stash->{xmlgroups} = $xmlgroups if eval { @$xmlgroups };


    $c->stash->{edit_host} = $c->request->params->{edit_host};

    if(exists $c->session->{crefill}) {
        $c->stash->{crefill} = $c->session->{crefill};
        delete $c->session->{crefill};
    }
    if(exists $c->session->{erefill}) {
        $c->stash->{erefill} = $c->session->{erefill};
        delete $c->session->{erefill};
    } elsif($c->request->params->{edit_host}) {
        foreach my $host (eval { @$xmlhosts }) {
            if($$host{id} == $c->request->params->{edit_host}) {
                $c->stash->{erefill} = $host;
                last;
            }
        }
    }

    return 1;
}

=head2 do_create_host

Create a new xmlctrl interface in the database.

=cut

sub do_create_host : Local {
    my ( $self, $c ) = @_;

    my %messages;
    my %settings;

    $settings{ip} = $c->request->params->{ip};
    $settings{port} = $c->request->params->{port};
    $settings{path} = $c->request->params->{path};
    $settings{description} = $c->request->params->{description}
        if length $c->request->params->{description};
    $settings{groups} = $c->request->params->{groups};

    $messages{chosterr} = 'Client.Voip.InputErrorFound'
      unless(length $settings{ip} && $settings{ip} =~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ &&
             length $settings{port} && $settings{port} =~ /^[0-9]+$/ &&
             defined $settings{groups} &&
             defined $settings{path}
      );

    unless(keys %messages) {
        if($c->model('Provisioning')->call_prov( $c, 'voip', 'create_xmlctrl_host',
                                                 \%settings,
                                                 undef))
        {
            $messages{chostmsg} = 'Server.Voip.SavedSettings';
            $c->session->{messages} = \%messages;
            $c->response->redirect("/xmlctrl#create_host");
            return;
        }
    }

    $messages{chosterr} = 'Client.Voip.InputErrorFound';
    $c->session->{messages} = \%messages;
    $c->session->{crefill} = \%settings;
    $c->response->redirect("/xmlctrl#create_host");
    return;
}

=head2 do_update_host

Update settings of an xmlctrl interface in the database.

=cut

sub do_update_host : Local {
    my ( $self, $c ) = @_;

    my %messages;
    my %settings;


    $settings{id} = $c->request->params->{host};
    $settings{ip} = $c->request->params->{ip};
    $settings{port} = $c->request->params->{port};
    $settings{path} = $c->request->params->{path};
    $settings{description} = $c->request->params->{description}
        if length $c->request->params->{description};
    $settings{groups} = $c->request->params->{groups};

    $messages{ehosterr} = 'Client.Voip.InputErrorFound'
      unless(length $settings{id} && $settings{id} =~ /^\d+$/ &&
             length $settings{ip} && $settings{ip} =~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ &&
             length $settings{port} && $settings{port} =~ /^[0-9]+$/ &&
             defined $settings{groups} &&
             defined $settings{path}
      );

    unless(keys %messages) {
        if($c->model('Provisioning')->call_prov( $c, 'voip', 'update_xmlctrl_host',
                                                 \%settings,
                                                 undef))
        {
            $messages{ehostmsg} = 'Server.Voip.SavedSettings';
            $c->session->{messages} = \%messages;
            $c->response->redirect("/xmlctrl");
            return;
        }
        $c->response->redirect("/xmlctrl?edit_host=$settings{id}");
        return;
    }

    $messages{ehosterr} = 'Client.Voip.InputErrorFound';
    $c->session->{messages} = \%messages;
    $c->response->redirect("/xmlctrl?edit_level=$settings{id}");
    return;
}

=head2 do_delete_host

Delete an xmlrpc control interface from the database.

=cut

sub do_delete_host : Local {
    my ( $self, $c ) = @_;

    my %settings;

    $settings{id} = $c->request->params->{host};
    unless(length $settings{id}) {
        $c->response->redirect("/xmlctrl");
        return;
    }

    if($c->model('Provisioning')->call_prov( $c, 'voip', 'delete_xmlctrl_host',
                                             \%settings,
                                             undef))
    {
        $c->session->{messages} = { ehostmsg => 'Server.Voip.SavedSettings' };
        $c->response->redirect("/xmlctrl");
        return;
    }

    $c->response->redirect("/xmlctrl");
    return;
}


=head1 BUGS AND LIMITATIONS

=over

=item none

=back

=head1 SEE ALSO

Provisioning model, Sipwise::Provisioning::Billing, Catalyst

=head1 AUTHORS

Andreas Granig <agranig@sipwise.com>

=head1 COPYRIGHT

The xmlctrl controller is Copyright (c) 2010 Sipwise GmbH, Austria. All
rights reserved.

=cut

# ende gelaende
1;
