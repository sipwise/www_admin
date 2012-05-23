package admin::Controller::sipanalysis;

use strict;
use warnings;
use base 'Catalyst::Controller';
use admin::Utils;
use HTML::Entities;

=head1 NAME

admin::Controller::sipcanalysis- Catalyst Controller

=head1 DESCRIPTION

This provides functionality for analyzing SIP traffic

=head1 METHODS

=head2 index

Display search form.

=cut

sub index : Private {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/sipanalysis.tt';

    return 1;
}

=head2 search

Search for SIP sessions and display results.

=cut

sub search : Local {
    my ( $self, $c ) = @_;
    my $limit = 10;
    my %filter;

    $c->stash->{template} = 'tt/sipanalysis.tt';

    if($c->request->params->{use_session}) {
        %filter = %{ $c->session->{search_filter} }
            if defined $c->session->{search_filter};
    } else {
        foreach my $sf (qw(uuid call_id)) {
            if(defined $c->request->params->{'search_'.$sf}
                and length $c->request->params->{'search_'.$sf})
            {
                $filter{$sf} = $c->request->params->{'search_'.$sf} || '';
            }
        }
        $c->session->{search_filter} = { %filter };
    }

    foreach my $sf (qw(uuid call_id)) {
        # set values for webform
        $c->stash->{'search_'.$sf} = $filter{$sf};

        next unless defined $filter{$sf};
    }

    my $offset = $c->request->params->{offset} || 0;
    $offset = 0 if $offset !~ /^\d+$/;

    my $calls;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'search_sipstat_calls',
                                                        { filter => { %filter,
                                                                      # limit => $limit,
                                                                      # offset => $limit * $offset
                                                                    }
                                                        },
                                                        \$calls
                                                      );
    $c->stash->{searched} = 1;

    # TODO: pagination goes here

    $c->stash->{calls} = $calls;

    return;
}

sub pcap : Local {
    my ( $self, $c ) = @_;

    $c->stash->{template} = 'tt/sipanalysis.tt';
    my $callid = $c->request->params->{callid};

    my $packets;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_sipstat_packets',
                                                        { 
                                                          callid   => $callid,
                                                        },
                                                        \$packets
                                                      );
    my $pcap = admin::Utils::generate_pcap($packets);
    my $filename = $callid . '.pcap';
    $c->stash->{current_view} = 'Plain';
    $c->stash->{content_type} = 'application/octet-stream';
    $c->stash->{content_disposition} = qq[attachment; filename="$filename"];
    $c->stash->{content} = eval { $pcap };
    return;
}

sub callmap_png : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/sipanalysis_call.tt';

    my $callid = $c->request->params->{callid};
    $c->stash->{callid} = $callid;

    my $calls;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_sipstat_packets',
                                                        { 
                                                          callid   => $callid,
                                                        },
                                                        \$calls
                                                      );
    my $png = admin::Utils::generate_callmap_png($c, $calls);
    my $filename = $callid . '.png';
    $c->stash->{current_view} = 'Plain';
    $c->stash->{content_type} = 'image/png';
    $c->stash->{content_disposition} = qq[attachment; filename="$filename"];
    $c->stash->{content} = eval { $png };

    return;
}

sub callmap : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/sipanalysis_call.tt';

    my $callid = $c->request->params->{callid};
    $c->stash->{callid} = $callid;

    my $calls;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_sipstat_packets',
                                                        { 
                                                          callid   => $callid,
                                                        },
                                                        \$calls
                                                      );
    $c->stash->{canvas} = admin::Utils::generate_callmap($c, $calls);

    return;
}

sub packet : Local {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/sipanalysis_call.tt';

    my $pkgid = $c->request->params->{pkgid};

    my $pkg;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_sipstat_packet',
                                                        { 
                                                          packetid   => $pkgid,
                                                        },
                                                        \$pkg
                                                      );

    $pkg->{payload} = encode_entities($pkg->{payload});
    $pkg->{payload} =~ s/\r//g;
    $pkg->{payload} =~ s/([^\n]{120})/$1<br\/>/g;
    $pkg->{payload} =~ s/^([^\n]+)\n/<b>$1<\/b>\n/;
    $pkg->{payload} = $pkg->{src_ip}.':'.$pkg->{src_port}.' &rarr; '. $pkg->{dst_ip}.':'.$pkg->{dst_port}.'<br/><br/>'.$pkg->{payload};
    $pkg->{payload} =~ s/\n([a-zA-Z0-9\-_]+\:)/\n<b>$1<\/b>/g;
    $pkg->{payload} =~ s/\n/<br\/>/g;
    $c->stash->{current_view} = 'Plain';
    $c->stash->{content_type} = 'text/html';
    $c->stash->{content} = eval { $pkg->{payload} };

    return;
}

=head1 BUGS AND LIMITATIONS

=over

=item currently none

=back

=head1 SEE ALSO

Provisioning model, Catalyst

=head1 AUTHORS

=over

=item Andreas Granig <agranig@sipwise.com>

=back

=head1 COPYRIGHT

The subscriber controller is Copyright (c) 2007-2012 Sipwise GmbH,
Austria. You should have received a copy of the licences terms together
with the software.

=cut

1;
