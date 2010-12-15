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

    if(ref $c->session->{restore_admin_input} eq 'HASH') {
        $c->stash->{admin} = $c->session->{restore_admin_input};
        delete $c->session->{restore_admin_input};
    } elsif(defined $edit_admin) {
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
    $c->session->{restore_admin_input} = \%settings;
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
