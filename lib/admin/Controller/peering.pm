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
    $c->stash->{template} = 'tt/peering.tt';

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
    $c->stash->{template} = 'tt/peering.tt';

    my %messages;
    my %settings;

    my $grpname = $c->request->params->{grpname};
    $messages{cpeererr} = 'Client.Syntax.MalformedPeerGroupName'
        unless $grpname =~ /^[a-zA-Z0-9_\-]+/;
    my $priority = $c->request->params->{priority};
    my $grpdesc = $c->request->params->{grpdesc};

    unless(keys %messages) {
        if($c->model('Provisioning')->call_prov( $c, 'voip', 'create_peer_group',
                                                 { name => $grpname,
												   priority => $priority,
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
		$arefill{priority} = $priority;
		$arefill{desc} = $grpdesc;

		$c->stash->{arefill} = \%arefill;
    }

    $c->session->{messages} = \%messages;
    $c->response->redirect("/peering");
    return;
}

=head2 edit_grp

Edit a peering group

=cut

sub edit_grp : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/peering.tt';

    my %messages;
    my %settings;

    my $grpid = $c->request->params->{grpid};
    my $priority = $c->request->params->{priority};
    my $grpdesc = $c->request->params->{grpdesc};

#$c->log->debug('*** edit grp');

    unless(keys %messages) {
        if($c->model('Provisioning')->call_prov( $c, 'voip', 'update_peer_group',
                                                 { id => $grpid,
												   priority => $priority,
												   description => $grpdesc
                                                 },
                                                 undef
                                               ))
        {
            $messages{epeermsg} = 'Server.Voip.SavedSettings';
		}
		else
		{
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
    $c->stash->{template} = 'tt/peering_detail.tt';

    my %messages;
    my %settings;

    my $grpid = $c->request->params->{grpid};
    my $callee_prefix = $c->request->params->{callee_prefix};
    my $caller_pattern = $c->request->params->{caller_pattern};
    my $description = $c->request->params->{description};

#    $messages{crulerr} = 'Client.Syntax.MalformedPeerGroupName'
#        unless $callee_prefix =~ /^[a-zA-Z0-9_\.\-\@\:]+/;

    unless(keys %messages) {
        if($c->model('Provisioning')->call_prov( $c, 'voip', 'create_peer_rule',
                                                 { group_id => $grpid,
												   callee_prefix => $callee_prefix,
												   caller_pattern => $caller_pattern,
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
    $c->stash->{template} = 'tt/peering_detail.tt';

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
    $c->stash->{template} = 'tt/peering_detail.tt';

    my %messages;
    my %settings;

    my $grpid = $c->request->params->{grpid};
    my $ruleid = $c->request->params->{ruleid};
    my $callee_prefix = $c->request->params->{callee_prefix};
    my $caller_pattern = $c->request->params->{caller_pattern};
    my $description = $c->request->params->{description};

#    $messages{crulerr} = 'Client.Syntax.MalformedPeerGroupName'
#        unless $callee_prefix =~ /^[a-zA-Z0-9_\.\-\@\:]+/;

    unless(keys %messages) {
        if($c->model('Provisioning')->call_prov( $c, 'voip', 'update_peer_rule',
                                                 { id => $ruleid,
												   callee_prefix => $callee_prefix,
												   caller_pattern => $caller_pattern,
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
    $c->stash->{template} = 'tt/peering_detail.tt';

    my %messages;
    my %settings;

    my $grpid = $c->request->params->{grpid};
    my $name = $c->request->params->{name};
    my $ip = $c->request->params->{ip};
    my $port = $c->request->params->{port};
    my $weight = $c->request->params->{weight};
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
												   weight => $weight,
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
    $c->stash->{template} = 'tt/peering_detail.tt';

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
    $c->stash->{template} = 'tt/peering_detail.tt';

    my %messages;
    my %settings;

    my $grpid = $c->request->params->{grpid};
    my $peerid = $c->request->params->{peerid};
    my $name = $c->request->params->{name};
    my $ip = $c->request->params->{ip};
    my $port = $c->request->params->{port};
    my $weight = $c->request->params->{weight};
    my $via_lb = defined $c->request->params->{via_lb} ? 1 : 0;

#    $messages{crulerr} = 'Client.Syntax.MalformedPeerGroupName'
#        unless $callee_prefix =~ /^[a-zA-Z0-9_\.\-\@\:]+/;

    unless(keys %messages) {
        if($c->model('Provisioning')->call_prov( $c, 'voip', 'update_peer_host',
                                                 { id => $peerid,
												   name => $name,
												   ip => $ip,
												   port => $port,
												   weight => $weight,
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

=head2 rewrite

Show rewrite rules for a given peer

=cut

sub rewrite : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/peering_rewrite.tt';
    
	my $peerid = $c->request->params->{peer_id};

    my $peer_details;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_peer_host_details',
														{ id => $peerid },
                                                        \$peer_details
                                                      );
	my $all_peer_details;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_peer_group_details',
														{ id => $$peer_details{group_id} },
                                                        \$all_peer_details
                                                      );
	my $all_peers = $$all_peer_details{peers};
	my @final_peers = ();
	for(my $i = 0; $i < @$all_peers; ++$i)
	{
			my $peer = @$all_peers[$i];
			push @final_peers, $peer if $$peer{id} != $peerid;
	}

    $c->stash->{peer} = $peer_details;
    $c->stash->{all_peers} = \@final_peers;
	$c->stash->{ifeditid} = $c->request->params->{ifeditid};
	$c->stash->{iteditid} = $c->request->params->{iteditid};
	$c->stash->{ofeditid} = $c->request->params->{ofeditid};
	$c->stash->{oteditid} = $c->request->params->{oteditid};

    return 1;
}

=head2 create_rewrite

Create a rewrite rule for a given peer with defined direction and field

=cut

sub create_rewrite : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/peering_rewrite.tt';

    my %messages;
    my %settings;

    my $grpid = $c->request->params->{grpid};
    my $peerid = $c->request->params->{peerid};
    my $match_pattern = $c->request->params->{match_pattern};
    my $replace_pattern = $c->request->params->{replace_pattern};
    my $description = $c->request->params->{description};
    my $direction = $c->request->params->{direction};
    my $field = $c->request->params->{field};

	my $a = "";
	if($field eq 'caller') { $a = 'caller'.$a; }
	elsif($field eq 'callee') { $a = 'callee'.$a; }
	if($direction eq 'in') { $a = 'i'.$a; }
	elsif($direction eq 'out') { $a = 'o'.$a; }
	my $m = $a.'msg'; my $e = $a.'err';

#    $messages{crulerr} = 'Client.Syntax.MalformedPeerGroupName'
#        unless $callee_prefix =~ /^[a-zA-Z0-9_\.\-\@\:]+/;

    unless(keys %messages) {
        if($c->model('Provisioning')->call_prov( $c, 'voip', 'create_peer_rewrite',
                                                 { peer_id => $peerid,
												   match_pattern => $match_pattern,
												   replace_pattern => $replace_pattern,
												   description => $description,
												   direction => $direction,
												   field => $field
                                                 },
                                                 undef
                                               ))
        {
            $messages{$m} = 'Server.Voip.SavedSettings';
            $c->session->{messages} = \%messages;
            $c->response->redirect("/peering/rewrite?peer_id=$peerid#$a");
            return;
		}
		else
		{
        	$messages{$e} = 'Client.Voip.InputErrorFound';
		}
    } else {
		# TODO: add proper values here and set them in tt
		my %arefill = ();
#		$arefill{name} = $grpname;
#		$arefill{desc} = $grpdesc;

		$c->stash->{arefill} = \%arefill;
    }

    $c->session->{messages} = \%messages;
    $c->response->redirect("/peering/rewrite?peer_id=$peerid#$a");
    return;
}

=head2 delete_rewrite

Delete a rewrite rule

=cut

sub delete_rewrite : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/peering_rewrite.tt';

    my %messages;
    my %settings;

    my $peerid = $c->request->params->{peerid};
    my $rewriteid = $c->request->params->{rewriteid};
    my $direction = $c->request->params->{direction};
    my $field = $c->request->params->{field};

	my $a = "";
	if($field eq 'caller') { $a = 'caller'.$a; }
	elsif($field eq 'callee') { $a = 'callee'.$a; }
	if($direction eq 'in') { $a = 'i'.$a; }
	elsif($direction eq 'out') { $a = 'o'.$a; }
	my $m = $a.'msg'; my $e = $a.'err';

    unless(keys %messages) {
        if($c->model('Provisioning')->call_prov( $c, 'voip', 'delete_peer_rewrite',
                                                 { id => $rewriteid
                                                 },
                                                 undef
                                               ))
        {
            $messages{$m} = 'Server.Voip.SavedSettings';
            $c->session->{messages} = \%messages;
            $c->response->redirect("/peering/rewrite?peer_id=$peerid#$a");
            return;
		}
    } else {
    }

    $c->session->{messages} = \%messages;
    $c->response->redirect("/peering/rewrite?peer_id=$peerid#$a");
    return;
}

=head2 edit_rewrite

Updates a rewrite rule

=cut

sub edit_rewrite : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/peering_rewrite.tt';

    my %messages;
    my %settings;

    my $peerid = $c->request->params->{peerid};
    my $rewriteid = $c->request->params->{rewriteid};
    my $match_pattern = $c->request->params->{match_pattern};
    my $replace_pattern = $c->request->params->{replace_pattern};
    my $description = $c->request->params->{description};
    my $direction = $c->request->params->{direction};
    my $field = $c->request->params->{field};

	my $a = "";
	if($field eq 'caller') { $a = 'caller'.$a; }
	elsif($field eq 'callee') { $a = 'callee'.$a; }
	if($direction eq 'in') { $a = 'i'.$a; }
	elsif($direction eq 'out') { $a = 'o'.$a; }
	my $m = $a.'msg'; my $e = $a.'err';

#    $messages{crulerr} = 'Client.Syntax.MalformedPeerGroupName'
#        unless $callee_prefix =~ /^[a-zA-Z0-9_\.\-\@\:]+/;

    unless(keys %messages) {
        if($c->model('Provisioning')->call_prov( $c, 'voip', 'update_peer_rewrite',
                                                 { id => $rewriteid,
												   match_pattern => $match_pattern,
												   replace_pattern => $replace_pattern,
												   description => $description,
												   direction => $direction,
												   field => $field
                                                 },
                                                 undef
                                               ))
        {
            $messages{$m} = 'Server.Voip.SavedSettings';
            $c->session->{messages} = \%messages;
            $c->response->redirect("/peering/rewrite?peer_id=$peerid#$a");
            return;
		}
		else
		{
        	$messages{$e} = 'Client.Voip.InputErrorFound';
		}
    } else {
		# TODO: add proper values here and set them in tt
		my %arefill = ();
#		$arefill{name} = $grpname;
#		$arefill{desc} = $grpdesc;

		$c->stash->{arefill} = \%arefill;
    }

    $c->session->{messages} = \%messages;
    $c->response->redirect("/peering/rewrite?peer_id=$peerid#$a");
    return;
}

=head2 copy_rewrite

Copy a rewrite rule from current group 

=cut

sub copy_rewrite : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/peering_rewrite.tt';

    my %messages;
    my %settings;

    my $peerid = $c->request->params->{peerid};
    my $rpeerid = $c->request->params->{rpeerid};
    my $policy= $c->request->params->{policy};
    my $grpid = $c->request->params->{grpid};
	my $delete_old = $policy eq "delete" ? 1 : 0;

	unless(defined $peerid && defined $rpeerid)
	{
    	$messages{cperr} = 'Client.Voip.NoSuchPeerHost';
	}

    unless(keys %messages) {
        if($c->model('Provisioning')->call_prov( $c, 'voip', 'copy_peer_rewrites',
                                                 { from_peer_id => $rpeerid,
												   to_peer_id => $peerid,
												   delete_old => $delete_old
                                                 },
                                                 undef
                                               ))
        {
            	$messages{cpmsg} = 'Server.Voip.SavedSettings';
	            $c->session->{messages} = \%messages;
    	        $c->response->redirect("/peering/rewrite?peer_id=$peerid");
        	    return;
		}
	}
	else
	{
		$c->response->redirect("/peering/rewrite?peer_id=$peerid");
        return;
	}

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
