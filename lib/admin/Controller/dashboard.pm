package admin::Controller::dashboard;

use strict;
use warnings;
use base 'Catalyst::Controller';
use Data::Dumper;
use UNIVERSAL 'isa';
use Sys::Hostname;


=head1 NAME

admin::Controller::dashboard - Catalyst Controller

=head1 DESCRIPTION

Catalyst controller for representation of the NGCP statistics dashboard.

=head1 METHODS

=head2 index

Control the statistics dashboard.

=head1 BUGS AND LIMITATIONS

=over

=item none

=back

=head1 SEE ALSO

Provisioning model, Sipwise::Provisioning::Billing, Catalyst

=head1 AUTHORS

Andreas Granig <agranig@sipwise.com>

Roman Dieser <rdieser@sipwise.com>

=head1 COPYRIGHT

The dashboard controller is Copyright (c) 2010-2013 Sipwise GmbH, Austria.
You should have received a copy of the licences terms together with the
software.

=cut


sub index : Private {
    my ( $self, $c ) = @_;

    if($c->config->{dashboard}{enabled} == 1) {

        $c->stash->{template} = 'tt/dashboard.tt';
        
        my $hosts;
        return unless $c->model('Provisioning')
                        ->call_prov($c, 'system', 'get_host_list', undef, \$hosts);
        
        $c->stash->{hosts} = $hosts;

        $c->stash->{selected_host} 
            = grep($c->request->params->{server_to_show}, @$hosts) 
            ? $c->request->params->{server_to_show} 
            : (grep(hostname, @$hosts) ? hostname : $$hosts[0]);

        my $subdirs;
        return unless $c->model('Provisioning')
                        ->call_prov($c, 
                                    'system', 
                                    'get_host_subdirs', 
                                    { host => $c->stash->{selected_host} }, 
                                    \$subdirs
                                   );

        $c->stash->{subfolders} = $subdirs;
            
        $c->stash->{selected_subfolder}
            = grep($c->request->params->{subfolder_to_show}, @$subdirs)
            ? $c->request->params->{subfolder_to_show} : $$subdirs[0];
    
        my $rrds;
        return unless $c->model('Provisioning')
                        ->call_prov($c, 
                                    'system', 
                                    'get_rrd_files', 
                                    {
                                        host   => $c->stash->{selected_host},
                                        folder => $c->stash->{selected_subfolder} 
                                    }, 
                                    \$rrds
                                   );

        my @plotdata = qw();
        
        foreach my $rrd (@$rrds) {

            my $name = $rrd;      # name is used as html id attribute, 
                                  # hence should not contain dots and colons 
            $name =~ s/[\.:]/-/g; # in order to function properly with jQuery

            my $title = $rrd;
            $title =~ s/\.rrd$//;

            push @plotdata, {
                name  => $name, 
                title => $title,
                url   => '/rrd/get?path='
                        . $c->stash->{selected_host}
                        . '/' . $c->stash->{selected_subfolder}
                        . '/' . $rrd, 
                si    => 1
            };
        }
            
        $c->stash->{ctx}       = 'index';
        $c->stash->{plotdata}  = \@plotdata;
        $c->stash->{tz_offset} = admin::Utils::tz_offset();
    }
    else {
        $c->response->redirect($c->uri_for('/'));
    }

    return 1;
}

sub subdir_list :Local {
    my( $self, $c ) = @_;

    my $subdirs;
    return unless $c->model('Provisioning')
                    ->call_prov($c, 
                                'system', 
                                'get_host_subdirs', 
                                { host => $c->request->param('host') }, 
                                \$subdirs
                               );
    my $options = qw();
    
    foreach my $option (@$subdirs) {
        $options .= '<option value="' . $option. '">' . $option . "</option>\n";
    }
    
    $c->response->body( $options );
    
    return 1; 
}

1;
