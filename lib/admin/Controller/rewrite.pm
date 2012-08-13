package admin::Controller::rewrite;

use strict;
use warnings;
use base 'Catalyst::Controller';
use Data::Dumper;
use admin::Utils;

=head1 NAME

admin::Controller::rewrite - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=head2 index 

Configure SIP rewrites

=cut

sub index : Private {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/rewrite.tt';

    my $rule_sets;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_rewrite_rule_sets',
                                                        undef,
                                                        \$rule_sets
                                                      );
    $c->stash->{rule_sets} = $rule_sets if eval { @$rule_sets };	
    $c->stash->{editid} = $c->request->params->{editid};
    
    if(exists $c->session->{garefill}) {
        $c->stash->{garefill} = $c->session->{garefill};
        delete $c->session->{garefill};
    }

    return 1;
}

=head2 do_delete_set

Delete a rewrite set

=cut

sub delete_set : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/rewrite.tt';

    my %messages;
    my %settings;

    my $setid = $c->request->params->{setid};
    
    if($c->model('Provisioning')->call_prov( $c, 'voip', 'delete_rewrite_rule_set',
                                              { id => $setid
                                              },
                                              undef
                                            ))
    {
        $messages{epeermsg} = 'Web.Rewrite.RuleSetDeleted';
        $c->session->{messages} = \%messages;
        $c->response->redirect("/rewrite");
        return;
	}
    $c->response->redirect("/rewrite");
    return;
}



=head2 create_set

Create a rewrite set

=cut

sub create_set : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/rewrite.tt';

    my %messages = ();
    my %settings = ();

    $settings{name} = $c->request->params->{setname};
    $messages{cpeererr} = 'Client.Syntax.MalformedRewriteRuleSetName'
        unless $settings{name} =~ /^[a-zA-Z0-9_\-]+/;
    $settings{description} = $c->request->params->{setdesc};

    unless(keys %messages) {
        if($c->model('Provisioning')->call_prov( $c, 'voip', 'create_rewrite_rule_set',
                                                 { %settings },
                                                 undef
                                               ))
        {
            $messages{cpeermsg} = 'Server.Voip.SavedSettings';
            $c->session->{messages} = \%messages;
            $c->response->redirect("/rewrite");
            return;
        }
    } else {
        $messages{cpeererr} = 'Client.Voip.InputErrorFound';
    }

    $c->session->{garefill} = \%settings;
    $c->session->{messages} = \%messages;
    $c->response->redirect("/rewrite#create_set");
    return;
}

=head2 edit_set

Edit a rewrite set

=cut

sub edit_set : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/rewrite.tt';

    my %messages;
    my %settings;

    my $setid = $c->request->params->{setid};
    $settings{description} = $c->request->params->{setdesc};

#$c->log->debug('*** edit set');

    unless(keys %messages) {
        if($c->model('Provisioning')->call_prov( $c, 'voip', 'update_rewrite_rule_set',
                                                 { id   => $setid,
                                                   data => \%settings,
                                                 },
                                                 undef
                                               ))
        {
            $messages{epeermsg} = 'Server.Voip.SavedSettings';
        }
    }
    $c->session->{messages} = \%messages;
    $c->response->redirect("/rewrite");
    return;
}

=head2 detail

Show rewrite rules for a given set

=cut

sub detail : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/rewrite_detail.tt';
    
    my $setid = $c->request->params->{set_id};

    my $set_details;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_rewrite_rule_set',
	                                                { id => $setid },
                                                        \$set_details
                                                      );
    $c->stash->{set} = $set_details;
    $c->stash->{editid} = $c->request->params->{editid};

    return 1;
}

=head2 create_rewrite

Create a rewrite rule for a given peer with defined direction and field

=cut

sub create_rewrite : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/rewrite_detail.tt';

    my %messages;
    my %settings;

    my $setid = $c->request->params->{setid};
    my $match_pattern = $c->request->params->{match_pattern};
    my $replace_pattern = $c->request->params->{replace_pattern};
    my $description = $c->request->params->{description};
    my $direction = $c->request->params->{direction};
    my $field = $c->request->params->{field};
    my $priority = $c->request->params->{priority};
    
    $match_pattern   =~ s/ //g;
    $replace_pattern =~ s/ //g;

    my $a = "";
    if($field eq 'caller') { $a = 'caller'.$a; }
    elsif($field eq 'callee') { $a = 'callee'.$a; }
    if($direction eq 'in') { $a = 'i'.$a; }
    elsif($direction eq 'out') { $a = 'o'.$a; }
    my $m = $a.'msg'; my $e = $a.'err'; my $d = $a.'detail';

#    $messages{crulerr} = 'Client.Syntax.MalformedPeerGroupName'
#        unless $callee_prefix =~ /^[a-zA-Z0-9_\.\-\@\:]+/;

    unless(keys %messages) {
        if($c->model('Provisioning')->call_prov( $c, 'voip', 'create_rewrite_rule',
                                                 { set_id => $setid,
                                                   data => {
                                                       match_pattern => $match_pattern,
                                                       replace_pattern => $replace_pattern,
                                                       description => $description,
                                                       direction => $direction,
                                                       field => $field,
                                                       priority => $priority,
                                                   },
                                                 },
                                                 undef
                                               ))
        {
            $messages{$m} = 'Server.Voip.SavedSettings';
            $c->session->{messages} = \%messages;
            $c->response->redirect("/rewrite/detail?set_id=$setid#$a");
            return;
        }
        else
        {
       	    $messages{$e} = 'Client.Voip.InputErrorFound';
            if($c->session->{prov_error_object}) {
                  $c->flash->{$d} = $c->session->{prov_error_object};
                }
        }
    } else {
		# TODO: add proper values here and set them in tt
		my %arefill = ();
#		$arefill{name} = $setname;
#		$arefill{desc} = $setdesc;

		$c->stash->{arefill} = \%arefill;
    }

    $c->session->{messages} = \%messages;
    $c->response->redirect("/rewrite/detail?set_id=$setid#$a");
    return;
}

=head2 update_rewrite_priority

Updates the priority of rewrite rules upon re-order

=cut

sub update_rewrite_priority : Local {
    my ( $self, $c ) = @_;

    my %messages;
    my %settings;

    my $prio = 0;

    my $rules = $c->request->params->{'rule[]'};

    foreach my $rule_id(@$rules)
    {
       my $rule = undef;
       $c->model('Provisioning')->call_prov( $c, 'voip', 'get_rewrite_rule',
           { id => $rule_id },
           \$rule
       );
       $c->model('Provisioning')->call_prov( $c, 'voip', 'update_rewrite_rule',
           { id   => $rule_id,
             data => {
               match_pattern => $rule->{match_pattern},
               replace_pattern => $rule->{replace_pattern},
               description => $rule->{description},
               direction => $rule->{direction},
               field => $rule->{field},
               priority => $prio,
             },
           },
           undef
        );
        $prio++;
    }

    $c->session->{messages} = \%messages;
    $c->response->redirect("/");
    return;
}


=head2 delete_rewrite

Delete a rewrite rule

=cut

sub delete_rewrite : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/rewrite_detail.tt';

    my %messages;
    my %settings;

    my $setid = $c->request->params->{setid};
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
        if($c->model('Provisioning')->call_prov( $c, 'voip', 'delete_rewrite_rule',
                                                 { id => $rewriteid
                                                 },
                                                 undef
                                               ))
        {
            $messages{$m} = 'Server.Voip.SavedSettings';
            $c->session->{messages} = \%messages;
            $c->response->redirect("/rewrite/detail?set_id=$setid#$a");
            return;
		}
    } else {
    }

    $c->session->{messages} = \%messages;
    $c->response->redirect("/rewrite/detail?set_id=$setid#$a");
    return;
}

=head2 edit_rewrite

Updates a rewrite rule

=cut

sub edit_rewrite : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/rewrite_detail.tt';

    my %messages;
    my %settings;

    my $setid = $c->request->params->{setid};
    my $rewriteid = $c->request->params->{rewriteid};
    my $match_pattern = $c->request->params->{match_pattern};
    my $replace_pattern = $c->request->params->{replace_pattern};
    my $description = $c->request->params->{description};
    my $direction = $c->request->params->{direction};
    my $field = $c->request->params->{field};
    my $priority = $c->request->params->{priority};
    
    $match_pattern   =~ s/ //g;
    $replace_pattern =~ s/ //g;

	my $a = "";
	if($field eq 'caller') { $a = 'caller'.$a; }
	elsif($field eq 'callee') { $a = 'callee'.$a; }
	if($direction eq 'in') { $a = 'i'.$a; }
	elsif($direction eq 'out') { $a = 'o'.$a; }
        my $m = $a.'msg'; my $e = $a.'err'; my $d = $a.'detail';

#    $messages{crulerr} = 'Client.Syntax.MalformedPeerGroupName'
#        unless $callee_prefix =~ /^[a-zA-Z0-9_\.\-\@\:]+/;

    unless(keys %messages) {
        if($c->model('Provisioning')->call_prov( $c, 'voip', 'update_rewrite_rule',
                                                 { id => $rewriteid,
                                                   data => {
                                                       match_pattern => $match_pattern,
                                                       replace_pattern => $replace_pattern,
                                                       description => $description,
                                                       direction => $direction,
                                                       field => $field,
                                                       priority => $priority,
                                                   },
                                                 },
                                                 undef
                                               ))
        {
            $messages{$m} = 'Server.Voip.SavedSettings';
            $c->session->{messages} = \%messages;
            $c->response->redirect("/rewrite/detail?set_id=$setid#$a");
            return;
		}
		else
		{
        	$messages{$e} = 'Client.Voip.InputErrorFound';
                if($c->session->{prov_error_object}) {
                  $c->flash->{$d} = $c->session->{prov_error_object};
                }
		}
    } else {
		# TODO: add proper values here and set them in tt
		my %arefill = ();
#		$arefill{name} = $setname;
#		$arefill{desc} = $setdesc;

		$c->stash->{arefill} = \%arefill;
    }

    $c->session->{messages} = \%messages;
    $c->response->redirect("/rewrite/detail?set_id=$setid#$a");
    return;
}

=head1 BUGS AND LIMITATIONS

=over

=item currently none

=back

=head1 SEE ALSO

Provisioning model, Sipwise::Provisioning::Billing, Catalyst

=head1 AUTHORS

=over

=item Andreas Granig <agranig@sipwise.com>

=back

=head1 COPYRIGHT

The rewrite controller is Copyright (c) 2009-2011 Sipwise GmbH, Austria.
You should have received a copy of the licences terms together with the
software.

=cut

# ende gelaende
1;
