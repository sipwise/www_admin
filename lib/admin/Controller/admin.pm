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

=head2 do_edit_admin 

Change settings for an admin.

=cut

sub do_edit_admin : Local {
    my ( $self, $c ) = @_;

    my %messages;
    my %settings;

    my $admin = $c->request->params->{admin};

    $settings{password} = $c->request->params->{password};
    if(defined $settings{password} and length $settings{password}) {
        $messages{epass} = 'Client.Voip.PassLength'
            unless length $settings{password} >= 6;
    } else {
        delete $settings{password};
    }

    $settings{is_master} = $c->request->params->{is_master} ? 1 : 0
        unless $admin eq $c->session->{admin}{login};
    $settings{is_active} = $c->request->params->{is_active} ? 1 : 0
        unless $admin eq $c->session->{admin}{login};
    $settings{read_only} = $c->request->params->{read_only} ? 1 : 0
        unless $admin eq $c->session->{admin}{login};
    $settings{show_passwords} = $c->request->params->{show_passwords} ? 1 : 0
        unless $admin eq $c->session->{admin}{login};
    $settings{call_data} = $c->request->params->{call_data} ? 1 : 0
        unless $admin eq $c->session->{admin}{login};
    $settings{lawful_intercept} = $c->request->params->{lawful_intercept} ? 1 : 0
        unless $admin eq $c->session->{admin}{login};

    unless(keys %messages) {
        if(keys %settings) {
            if($c->model('Provisioning')->call_prov( $c, 'billing', 'update_admin',
                                                     { login => $admin,
                                                       data   => { %settings },
                                                     },
                                                     undef
                                                   ))
            {
                $c->session->{admin}{password} = $settings{password}
                    if exists $settings{password} and $admin eq $c->session->{admin}{login};
                $messages{eadmmsg} = 'Server.Voip.SavedSettings';
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
    $c->session->{restore_admedit_input} = \%settings;
    $c->response->redirect("/admin?edit_admin=$admin");
    return;
}

=head2 do_create_admin 

Create a new admin.

=cut

sub do_create_admin : Local {
    my ( $self, $c ) = @_;

    my %messages;
    my %settings;

    my $admin = $c->request->params->{admin};
    $messages{alogin} = 'Client.Syntax.MalformedLogin'
        unless $admin =~ /^\w+$/;

    $settings{password} = $c->request->params->{password};
    $messages{apass} = 'Client.Voip.PassLength'
        unless length $settings{password} >= 6;

    $settings{is_master} = $c->request->params->{is_master} ? 1 : 0;
    $settings{is_active} = $c->request->params->{is_active} ? 1 : 0;
    $settings{read_only} = $c->request->params->{read_only} ? 1 : 0;
    $settings{show_passwords} = $c->request->params->{show_passwords} ? 1 : 0;
    $settings{call_data} = $c->request->params->{call_data} ? 1 : 0;
    $settings{lawful_intercept} = $c->request->params->{lawful_intercept} ? 1 : 0;

    unless(keys %messages) {
        if($c->model('Provisioning')->call_prov( $c, 'billing', 'create_admin',
                                                 { login => $admin,
                                                   data   => \%settings,
                                                 },
                                                 undef
                                               ))
        {
            $messages{cadmmsg} = 'Web.Admin.Created';
            $c->session->{messages} = \%messages;
            $c->response->redirect("/admin");
            return;
        }
    } else {
        $messages{cadmerr} = 'Client.Voip.InputErrorFound';
    }

    $c->session->{messages} = \%messages;
    $c->session->{restore_admadd_input} = \%settings;
    $c->session->{restore_admadd_input}{admin} = $admin;
    $c->response->redirect("/admin");
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
