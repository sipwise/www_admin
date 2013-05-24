package admin::Controller::admin;

use strict;
use warnings;
use base 'Catalyst::Controller';

=head1 NAME

admin::Controller::admin - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=head2 index 

Display admin list.

=cut

sub index : Private {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/admin.tt';

    if($c->session->{admin}{is_master} or $c->session->{admin}{is_superuser}) {
        my $admins;
        return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_admins',
                                                            undef,
                                                            \$admins
                                                          );
        $c->stash->{admins} = $admins if eval { @$admins };


    } else { # only own settings
        my $admin;
        return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_admin',
                                                            { login => $c->session->{admin}{login} },
                                                            \$admin
                                                          );
        $c->stash->{admins} = [ $admin ];
    }
    unless($c->session->{admin}{is_reseller}) {
        $self->load_reseller_contracts($c);
        $self->load_resellers($c);
    }

    $c->stash->{edit_admin} = $c->request->params->{edit_admin};

    if(ref $c->session->{restore_admedit_input} eq 'HASH') {
        $c->stash->{erefill} = $c->session->{restore_admedit_input};
        delete $c->session->{restore_admedit_input};
    }
    if(ref $c->session->{restore_admadd_input} eq 'HASH') {
        $c->stash->{arefill} = $c->session->{restore_admadd_input};
        delete $c->session->{restore_admadd_input};
    } else {
        $c->stash->{arefill} = $c->config->{default_admin_settings};
    }

    return 1;
}

=head2 edit_admin

Show edit form for an administrator.

=cut

sub edit_admin : Local {
    my ( $self, $c ) = @_;

    $c->stash->{template} = 'tt/admin_edit.tt';

    my $edit_admin = $c->request->params->{edit_admin};
    $c->stash->{edit_admin} = $edit_admin if defined $edit_admin;
    unless($c->session->{admin}{is_reseller}) {
        $self->load_reseller_contracts($c);
        $self->load_resellers($c);
    }

    if(defined $edit_admin) {
        return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_admin',
                                                            { login => $edit_admin },
                                                            \$c->stash->{admin}
                                                          );
    } else {
        $c->stash->{admin} = $c->config->{default_admin_settings};
    }

    return 1;
}

=head2 do_edit_admin 

Change settings for an admin or create a new one.

=cut

sub do_edit_admin : Local {
    my ( $self, $c ) = @_;

    my %messages;
    my %settings;

    my $admin = $c->request->params->{admin};  # new admin
    my $edit_admin = $c->request->params->{edit_admin};  # existing admin

    if(defined $admin) {
      $messages{elogin} = 'Client.Syntax.MalformedLogin'
          unless $admin =~ /^\w+$/;
    }

    $settings{password} = $c->request->params->{password};
    if(defined $settings{password} and length $settings{password}) {
        $messages{epass} = 'Client.Voip.PassLength'
            unless length $settings{password} >= 6;
        my $password2 = $c->request->params->{password2};
        if(defined $password2 and length $password2) {
            $messages{epass2} = 'Client.Voip.PassLength'
                unless length $password2 >= 6;
            $messages{epass2} = 'Client.Voip.PassNoMatch'
                unless $settings{password} eq $password2;
        } else {
            $messages{epass2} = 'Client.Voip.MissingPass2';
        }
    } else {
        delete $settings{password};
        $messages{epass} = 'Client.Voip.PassLength'
            unless defined $edit_admin;
    }

    $settings{reseller_id} = $c->request->params->{reseller_id} || undef;
    $settings{is_master} = $c->request->params->{is_master} ? 1 : 0
        unless $edit_admin eq $c->session->{admin}{login};
    $settings{is_active} = $c->request->params->{is_active} ? 1 : 0
        unless $edit_admin eq $c->session->{admin}{login};
    $settings{read_only} = $c->request->params->{read_only} ? 1 : 0
        unless $edit_admin eq $c->session->{admin}{login};
    $settings{show_passwords} = $c->request->params->{show_passwords} ? 1 : 0
        unless $edit_admin eq $c->session->{admin}{login};
    $settings{call_data} = $c->request->params->{call_data} ? 1 : 0
        unless $edit_admin eq $c->session->{admin}{login};
    $settings{lawful_intercept} = $c->request->params->{lawful_intercept} ? 1 : 0
        unless $edit_admin eq $c->session->{admin}{login};

    unless(keys %messages) {
        if(keys %settings) {
            if($c->model('Provisioning')->call_prov( $c, 'billing',
                                                     (defined $edit_admin ? 'update_admin'
                                                                          : 'create_admin'
                                                     ),
                                                     { login => (defined $edit_admin ? $edit_admin
                                                                                     : $admin),
                                                       data   => { %settings },
                                                     },
                                                     undef
                                                   ))
            {
                $c->session->{admin}{password} = $settings{password}
                    if exists $settings{password} and $edit_admin eq $c->session->{admin}{login};
                $messages{admmsg} = defined $edit_admin ? 'Server.Voip.SavedSettings'
                                                        : 'Web.Admin.Created';
                $c->session->{messages} = \%messages;
                $c->response->redirect("/admin");
                return;
            }
        } else {
            # emit error?
            $c->response->redirect("/admin");
            return;
        }
    } else {
        $messages{eadmerr} = 'Client.Voip.InputErrorFound';
    }

    $c->session->{messages} = \%messages;
    $settings{admin} = $admin if defined $admin;
    $c->response->redirect(defined $edit_admin ? "/admin/edit_admin?edit_admin=$edit_admin" : "/admin/edit_admin");
    return;
}

=head2 do_delete_admin 

Delete a admin.

=cut

sub do_delete_admin : Local {
    my ( $self, $c ) = @_;

    my $admin = $c->request->params->{admin};
    if($c->model('Provisioning')->call_prov( $c, 'billing', 'delete_admin',
                                             { login => $admin },
                                             undef
                                           ))
    {
        $c->session->{messages}{admmsg} = 'Web.Admin.Deleted';
        $c->response->redirect("/admin");
        return;
    }

    $c->response->redirect("/admin");
    return;
}

=head2 detail 

Show reseller contract details.

=cut

sub contract_detail : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/admin_contract_detail.tt';

    my $contract;
    my $contract_id = $c->request->params->{contract_id} || undef;
    if(defined $contract_id) {
        return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_reseller_contract_by_id',
                                                            { id => $contract_id },
                                                            \$contract
                                                          );
    }
    if(ref $c->session->{restore_contract_input} eq 'HASH') {
        if($c->config->{billing_features}) {
            $contract->{billing_profile} = $c->session->{restore_contract_input}{billing_profile};
    }
        $contract->{contact} = $c->session->{restore_contract_input}{contact};
        delete $c->session->{restore_contract_input};
    }

    # we only use this to fill the drop-down lists
    if($c->request->params->{edit_contract}) {
        my $billing_profiles;
        return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_billing_profiles',
                                                            undef,
                                                            \$billing_profiles
                                                          );
        $c->stash->{billing_profiles} = [ sort { $$a{data}{name} cmp $$b{data}{name} }
                                            @$billing_profiles ];
    } else {
        if(defined $contract->{billing_profile}) {
            my $profile;
            return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_billing_profile',
                                                                { handle => $contract->{billing_profile} },
                                                                \$profile
                                                              );
            $contract->{billing_profile_name} = $$profile{data}{name};
        }
    }

    $c->stash->{contract} = $contract;
    $c->stash->{contact_form_fields} = admin::Utils::get_contract_contact_form_fields($c,$contract->{contact});
    if($c->config->{billing_features}) {
        $c->stash->{billing_features} = 1;
    }
    $c->stash->{edit_contract} = $c->request->params->{edit_contract};

    return 1;
}

=head2 save_contract 

Create or update details of a SIP peering contract.

=cut

sub save_contract : Local {
    my ( $self, $c ) = @_;

    my %messages;
    my %settings;

    my $contract_id = $c->request->params->{contract_id} || undef;

    my $billing_profile = $c->request->params->{billing_profile};
    $settings{billing_profile} = $billing_profile if defined $billing_profile;

    my %contact;
    my $contract_contact_form_fields = admin::Utils::get_contract_contact_form_fields($c,undef);
    if (ref $contract_contact_form_fields eq 'ARRAY') {
      foreach my $form_field (@$contract_contact_form_fields) {
    if (defined $c->request->params->{$form_field->{field}} and length($c->request->params->{$form_field->{field}})) {
      $contact{$form_field->{field}} = $c->request->params->{$form_field->{field}};
    } else {
          $contact{$form_field->{field}} = undef;
        }
      }
    }
    $settings{contact} = \%contact;

    if(keys %settings or (!$c->config->{billing_features} and !defined $contract_id)) {
        if(defined $contract_id) {
            if($c->model('Provisioning')->call_prov( $c, 'billing', 'update_reseller_contract',
                                                     { id   => $contract_id,
                                                       data => \%settings,
                                                     },
                                                     undef))
            {
                $messages{topmsg} = 'Web.Contract.Updated';
                $c->session->{messages} = \%messages;
                $c->response->redirect("/admin");
                return;
            }
        } else {
            if($c->model('Provisioning')->call_prov( $c, 'billing', 'create_reseller_contract',
                                                     { data => \%settings },
                                                     \$contract_id))
            {
                $messages{topmsg} = 'Web.Contract.Created';
                $c->session->{messages} = \%messages;
                $c->response->redirect("/admin");
                return;
            }
        }
    }

    $c->session->{messages} = \%messages;
    $c->session->{restore_contract_input} = \%settings;
    $c->response->redirect("/admin/contract_detail?edit_contract=1&contract_id=$contract_id");
    return;
}

=head2 terminate

Terminates a reseller contract.

=cut

sub terminate_contract : Local {
    my ( $self, $c ) = @_;

    my %messages;

    my $contract_id = $c->request->params->{contract_id};

    if($c->model('Provisioning')->call_prov( $c, 'billing', 'terminate_reseller_contract',
                                             { id => $contract_id },
                                             undef))
    {
        $messages{topmsg} = 'Web.Contract.Deleted';
        $c->session->{messages} = \%messages;
        $c->response->redirect("/admin");
        return;
    }

    $c->session->{messages} = \%messages;
    $c->response->redirect("/admin/contract_detail?edit_contract=1&contract_id=$contract_id");
    return;
}

=head2 delete

Deletes a reseller contract.

=cut

sub delete_contract : Local {
    my ( $self, $c ) = @_;

    my %messages;

    my $contract_id = $c->request->params->{contract_id};

    if($c->model('Provisioning')->call_prov( $c, 'billing', 'delete_reseller_contract',
                                             { id => $contract_id },
                                             undef))
    {
        $messages{topmsg} = 'Web.Contract.Deleted';
        $c->session->{messages} = \%messages;
        $c->response->redirect("/admin");
        return;
    }

    $c->session->{messages} = \%messages;
    $c->response->redirect("/admin/contract_detail?edit_contract=1&contract_id=$contract_id");
    return;
}

sub reseller_detail : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/admin_reseller_detail.tt';

    my $reseller;
    my $reseller_id = $c->request->params->{reseller_id} || undef;
    if(defined $reseller_id) {
        return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_reseller_by_id',
                                                            { id => $reseller_id },
                                                            \$reseller
                                                          );
    }
    $c->stash->{reseller} = $reseller;

    # we only use this to fill the drop-down lists
    $self->load_resellers($c);
    $self->load_reseller_contracts($c);
    my %used = (); my @all = ();
    push @all, @{$c->stash->{contracts}};
    $c->stash->{contracts} = [];
    my $i = 0;
    foreach my $con(@all) {
        foreach my $r(@{$c->stash->{resellers}}) {
            if($r->{contract_id} == $con->{id}) {
                if(defined $reseller_id && $reseller->{contract_id} == $con->{id}) {
                } else {
                    $used{$i} = 1;
                }
            }
        }
        ++$i;
    }
    for(my $i = 0; $i < @all; ++$i) {
      unless(exists $used{$i}) {
        push @{$c->stash->{contracts}}, $all[$i]
      } else {
      }
    }
    $c->stash->{edit_reseller} = $c->request->params->{edit_reseller};

    return 1;
}

sub save_reseller : Local {
    my ( $self, $c ) = @_;

    my %messages;
    my %settings;

    my $reseller_id = $c->request->params->{reseller_id} || undef;
    my $contract_id = $c->request->params->{contract_id};
    my $name = $c->request->params->{name};
    $settings{name} = $name if defined $name;
    $settings{contract_id} = $contract_id if defined $contract_id;

    if(keys %settings or (!$c->config->{billing_features} and !defined $reseller_id)) {
        if(defined $reseller_id) {
            if($c->model('Provisioning')->call_prov( $c, 'billing', 'update_reseller',
                                                     { id   => $reseller_id,
                                                       data => \%settings,
                                                     },
                                                     undef))
            {
                $messages{topmsg} = 'Web.Contract.Updated';
                $c->session->{messages} = \%messages;
                $c->response->redirect("/admin");
                return;
            }
        } else {
            if($c->model('Provisioning')->call_prov( $c, 'billing', 'create_reseller',
                                                     { data => \%settings },
                                                     \$reseller_id))
            {
                $messages{topmsg} = 'Web.Contract.Created';
                $c->session->{messages} = \%messages;
                $c->response->redirect("/admin");
                return;
            }
        }
    }

    $c->session->{messages} = \%messages;
    $c->response->redirect("/admin/reseller_detail?edit_reseller=1&reseller_id=$reseller_id");
    return;
}

sub load_reseller_contracts : Private {
    my ( $self, $c ) = @_;

        my $reseller_contracts;
        my $contracts;
        return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_reseller_contracts',
                                                        1,
                                                        \$reseller_contracts
                                                      );
        if (eval { @$reseller_contracts }) {
            $contracts = [];
            foreach my $reseller_contract (@$reseller_contracts) {
                my %contract; # = {};
                $contract{id} = $reseller_contract->{id};
                if(defined $reseller_contract->{billing_profile} and length $reseller_contract->{billing_profile}) {
                    my $profile;
                    return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_billing_profile',
                                                                    { handle => $reseller_contract->{billing_profile} },
                                                                    \$profile
                                                                  );
                    $contract{billing_profile_name} = $$profile{data}{name};
                } else {
                    $contract{billing_profile_name} = '';
                }
                $contract{short_contact} = admin::Utils::short_contact($c,$reseller_contract->{contact});
                $contract{create_timestamp} = $reseller_contract->{create_timestamp};
                push @$contracts,\%contract;
           }
           $c->stash->{contracts} = $contracts;
        }
        return 1;
}

sub load_resellers : Private {
    my ( $self, $c ) = @_;

    my $resellers;

    return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_resellers',
                                                        undef,
                                                        \$resellers
                                                      );

    $c->stash->{resellers} = $resellers;

    return 1;
}



=head1 BUGS AND LIMITATIONS

=over

=item currently none

=back

=head1 SEE ALSO

Provisioning model, Sipwise::Provisioning::Billing, Catalyst

=head1 AUTHORS

Daniel Tiefnig <dtiefnig@sipwise.com>

=head1 COPYRIGHT

The admin controller is Copyright (c) 2007-2010 Sipwise GmbH, Austria.
You should have received a copy of the licences terms together with the
software.

=cut

# ende gelaende
1;

# vim: set tabstop=4 expandtab:
