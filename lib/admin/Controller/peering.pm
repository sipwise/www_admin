package admin::Controller::peering;

use strict;
use warnings;
use base 'Catalyst::Controller';
use Data::Dumper;

=head1 NAME

admin::Controller::peering - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=head2 index 

Configure SIP peerings

=cut

sub index : Private {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/peering.tt';

    my $peer_groups;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_peer_groups',
                                                        undef,
                                                        \$peer_groups
                                                      );
    $c->stash->{peer_groups} = $$peer_groups{result};
	$c->stash->{editid} = $c->request->params->{editid};

    return 1;
}

=head2 do_delete_grp

Delete a peering group

=cut

sub delete_grp : Local {
    my ( $self, $c ) = @_;

    my %messages;
    my %settings;

    my $grpid = $c->request->params->{grpid};
    
    if($c->model('Provisioning')->call_prov( $c, 'voip', 'delete_peer_group',
                                              { id => $grpid
                                              },
                                              undef
                                            ))
    {
        $messages{epeermsg} = 'Server.Voip.PeerGroupDeleted';
        $c->session->{messages} = \%messages;
        $c->response->redirect("/peering");
        return;
	}
    $c->response->redirect("/peering");
    return;
}



=head2 create_grp

Create a peering group

=cut

sub create_grp : Local {
    my ( $self, $c ) = @_;

    my %messages;
    my %settings;

    my $grpname = $c->request->params->{grpname};
    $messages{cpeererr} = 'Client.Syntax.MalformedPeerGroupName'
        unless $grpname =~ /^[a-zA-Z0-9_\-]+/;
    my $grpdesc = $c->request->params->{grpdesc};

    unless(keys %messages) {
        if($c->model('Provisioning')->call_prov( $c, 'voip', 'create_peer_group',
                                                 { name => $grpname,
												   description => $grpdesc
                                                 },
                                                 undef
                                               ))
        {
            $messages{cpeermsg} = 'Server.Voip.SavedSettings';
            $c->session->{messages} = \%messages;
            $c->response->redirect("/peering");
            return;
		}
		else
		{
        	$messages{cpeererr} = 'Client.Voip.InputErrorFound';
		}
    } else {
		my %arefill = ();
		$arefill{name} = $grpname;
		$arefill{desc} = $grpdesc;

		$c->stash->{arefill} = \%arefill;
    }

    $c->session->{messages} = \%messages;
#$c->session->{restore_domedit_input} = \%settings;
#    $c->response->redirect("/peering?edit_group=$grpname");
    $c->response->redirect("/peering");
    return;
}

=head2 edit_grp

Edit a peering group

=cut

sub edit_grp : Local {
    my ( $self, $c ) = @_;

    my %messages;
    my %settings;

    my $grpid = $c->request->params->{grpid};
    my $grpdesc = $c->request->params->{grpdesc};

	$c->log->debug('*** edit grp');

    unless(keys %messages) {
		$c->log->debug('*** call backend');
        if($c->model('Provisioning')->call_prov( $c, 'voip', 'update_peer_group',
                                                 { id => $grpid,
												   description => $grpdesc
                                                 },
                                                 undef
                                               ))
        {
			$c->log->debug('*** call backend ok');
            $messages{epeermsg} = 'Server.Voip.SavedSettings';
		}
		else
		{
			$c->log->debug('*** call backend failed');
        	$messages{epeererr} = 'Client.Voip.InputErrorFound';
		}
    }
    $c->session->{messages} = \%messages;
    $c->response->redirect("/peering");
    return;
}

sub detail : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/peering_detail.tt';
    
	my $grpid = $c->request->params->{group_id};

    my $peer_details;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_peer_group_details',
														{ id => $grpid },
                                                        \$peer_details
                                                      );
	$c->log->debug(Dumper $peer_details);
    $c->stash->{grp} = $peer_details;
	$c->stash->{reditid} = $c->request->params->{reditid};
	$c->stash->{peditid} = $c->request->params->{peditid};

    return 1;
}

=head2 create_rule

Create a peering rule for a given group

=cut

sub create_rule : Local {
    my ( $self, $c ) = @_;

    my %messages;
    my %settings;

    my $grpid = $c->request->params->{grpid};
    my $callee_prefix = $c->request->params->{callee_prefix};
    my $caller_pattern = $c->request->params->{caller_pattern};
    my $priority = $c->request->params->{priority};
    my $description = $c->request->params->{description};

#    $messages{crulerr} = 'Client.Syntax.MalformedPeerGroupName'
#        unless $callee_prefix =~ /^[a-zA-Z0-9_\.\-\@\:]+/;

    unless(keys %messages) {
        if($c->model('Provisioning')->call_prov( $c, 'voip', 'create_peer_rule',
                                                 { group_id => $grpid,
												   callee_prefix => $callee_prefix,
												   caller_pattern => $caller_pattern,
												   priority => $priority,
												   description => $description
                                                 },
                                                 undef
                                               ))
        {
            $messages{erulmsg} = 'Server.Voip.SavedSettings';
            $c->session->{messages} = \%messages;
            $c->response->redirect("/peering/detail?group_id=$grpid");
            return;
		}
		else
		{
        	$messages{erulerr} = 'Client.Voip.InputErrorFound';
		}
    } else {
		# TODO: add proper values here and set them in tt
		my %arefill = ();
#		$arefill{name} = $grpname;
#		$arefill{desc} = $grpdesc;

		$c->stash->{arefill} = \%arefill;
    }

    $c->session->{messages} = \%messages;
    $c->response->redirect("/peering/detail?group_id=$grpid");
    return;
}

=head2 delete_rule

Delete a peering rule

=cut

sub delete_rule : Local {
    my ( $self, $c ) = @_;

    my %messages;
    my %settings;

    my $grpid = $c->request->params->{grpid};
    my $rule_id = $c->request->params->{ruleid};

    unless(keys %messages) {
        if($c->model('Provisioning')->call_prov( $c, 'voip', 'delete_peer_rule',
                                                 { id => $rule_id
                                                 },
                                                 undef
                                               ))
        {
            $messages{erulmsg} = 'Server.Voip.SavedSettings';
            $c->session->{messages} = \%messages;
            $c->response->redirect("/peering/detail?group_id=$grpid");
            return;
		}
    } else {
    }

    $c->session->{messages} = \%messages;
    $c->response->redirect("/peering/detail?group_id=$grpid");
    return;
}

=head2 edit_rule

Edit a peering rule

=cut

sub edit_rule : Local {
    my ( $self, $c ) = @_;

    my %messages;
    my %settings;

    my $grpid = $c->request->params->{grpid};
    my $ruleid = $c->request->params->{ruleid};
    my $callee_prefix = $c->request->params->{callee_prefix};
    my $caller_pattern = $c->request->params->{caller_pattern};
    my $priority = $c->request->params->{priority};
    my $description = $c->request->params->{description};

#    $messages{crulerr} = 'Client.Syntax.MalformedPeerGroupName'
#        unless $callee_prefix =~ /^[a-zA-Z0-9_\.\-\@\:]+/;

    unless(keys %messages) {
        if($c->model('Provisioning')->call_prov( $c, 'voip', 'update_peer_rule',
                                                 { id => $ruleid,
												   callee_prefix => $callee_prefix,
												   caller_pattern => $caller_pattern,
												   priority => $priority,
												   description => $description
                                                 },
                                                 undef
                                               ))
        {
            $messages{erulmsg} = 'Server.Voip.SavedSettings';
            $c->session->{messages} = \%messages;
            $c->response->redirect("/peering/detail?group_id=$grpid");
            return;
		}
		else
		{
        	$messages{erulerr} = 'Client.Voip.InputErrorFound';
		}
    } else {
		# TODO: add proper values here and set them in tt
		my %arefill = ();
#		$arefill{name} = $grpname;
#		$arefill{desc} = $grpdesc;

		$c->stash->{arefill} = \%arefill;
    }

    $c->session->{messages} = \%messages;
    $c->response->redirect("/peering/detail?group_id=$grpid");
    return;
}

=head2 create_peer

Create a peering server for a given group

=cut

sub create_peer : Local {
    my ( $self, $c ) = @_;

    my %messages;
    my %settings;

    my $grpid = $c->request->params->{grpid};
    my $name = $c->request->params->{name};
    my $ip = $c->request->params->{ip};
    my $port = $c->request->params->{port};
    my $via_lb = defined $c->request->params->{via_lb} ? 1 : 0;

#TODO: add syntax checks here

#    $messages{serverr} = 'Client.Syntax.MalformedPeerGroupName'
#        unless $callee_prefix =~ /^[a-zA-Z0-9_\.\-\@\:]+/;


    unless(keys %messages) {
        if($c->model('Provisioning')->call_prov( $c, 'voip', 'create_peer_host',
                                                 { group_id => $grpid,
												   name => $name,
												   ip => $ip,
												   port => $port,
												   via_lb => $via_lb
                                                 },
                                                 undef
                                               ))
        {
            $messages{servmsg} = 'Server.Voip.SavedSettings';
            $c->session->{messages} = \%messages;
            $c->response->redirect("/peering/detail?group_id=$grpid");
            return;
		}
		else
		{
        	$messages{serverr} = 'Client.Voip.InputErrorFound';
		}
    } else {
		# TODO: add proper values here and set them in tt
		my %arefill = ();
#		$arefill{name} = $grpname;
#		$arefill{desc} = $grpdesc;

		$c->stash->{arefill} = \%arefill;
    }

    $c->session->{messages} = \%messages;
    $c->response->redirect("/peering/detail?group_id=$grpid");
    return;
}

=head2 delete_peer

Delete a peering host

=cut

sub delete_peer : Local {
    my ( $self, $c ) = @_;

    my %messages;
    my %settings;

    my $grpid = $c->request->params->{grpid};
    my $peer_id = $c->request->params->{peerid};

    unless(keys %messages) {
        if($c->model('Provisioning')->call_prov( $c, 'voip', 'delete_peer_host',
                                                 { id => $peer_id
                                                 },
                                                 undef
                                               ))
        {
            $messages{servmsg} = 'Server.Voip.SavedSettings';
            $c->session->{messages} = \%messages;
            $c->response->redirect("/peering/detail?group_id=$grpid");
            return;
		}
    } else {
    }

    $c->session->{messages} = \%messages;
    $c->response->redirect("/peering/detail?group_id=$grpid");
    return;
}

=head2 edit_peer

Edit a peering host

=cut

sub edit_peer : Local {
    my ( $self, $c ) = @_;

    my %messages;
    my %settings;

    my $grpid = $c->request->params->{grpid};
    my $peerid = $c->request->params->{peerid};
    my $name = $c->request->params->{name};
    my $ip = $c->request->params->{ip};
    my $port = $c->request->params->{port};
    my $via_lb = defined $c->request->params->{via_lb} ? 1 : 0;

#    $messages{crulerr} = 'Client.Syntax.MalformedPeerGroupName'
#        unless $callee_prefix =~ /^[a-zA-Z0-9_\.\-\@\:]+/;

    unless(keys %messages) {
        if($c->model('Provisioning')->call_prov( $c, 'voip', 'update_peer_host',
                                                 { id => $peerid,
												   name => $name,
												   ip => $ip,
												   port => $port,
												   via_lb => $via_lb
                                                 },
                                                 undef
                                               ))
        {
            $messages{servmsg} = 'Server.Voip.SavedSettings';
            $c->session->{messages} = \%messages;
            $c->response->redirect("/peering/detail?group_id=$grpid");
            return;
		}
		else
		{
        	$messages{erulerr} = 'Client.Voip.InputErrorFound';
		}
    } else {
		# TODO: add proper values here and set them in tt
		my %arefill = ();
#		$arefill{name} = $grpname;
#		$arefill{desc} = $grpdesc;

		$c->stash->{arefill} = \%arefill;
    }

    $c->session->{messages} = \%messages;
    $c->response->redirect("/peering/detail?group_id=$grpid");
    return;
}


=head1 BUGS AND LIMITATIONS

=over

=item currently none

=back

=head1 SEE ALSO

Provisioning model, Sipwise::Provisioning::Billing, Catalyst

=head1 AUTHORS

Andreas Granig <agranig@sipwise.com>

=head1 COPYRIGHT

The domain controller is Copyright (c) 2007 Sipwise GmbH, Austria. All
rights reserved.

=cut

# ende gelaende
1;
