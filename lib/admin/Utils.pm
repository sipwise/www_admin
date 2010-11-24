package admin::Utils;
use strict;
use warnings;

use Time::Local;

# Takes a search result total count, an offset and a limit and returns
# an array containing offset values for a pagination link list
# where each page should list $limit elements.
# The array will contain at most 11 entries, the first and last offset
# (0 and n) are always included. Further, the array will contain either:
#   if n <= 10:
#     * up to 9 elements from 1 .. n-1
#   if n > 10:
#     * 8 elements from 1 .. 8 and -1, if offset <= 5
#     * -1 and 8 elements from n-9 .. n-1, if offset >= n-6
#     * -1, 7 elements from o-3 .. o+3 and -1, elsewise
sub paginate {
    my ($total_count, $offset, $limit) = @_;
    my @pagination;

    foreach my $page (0 .. int(($total_count - 1) / $limit)) {
        push @pagination, { offset => $page };
    }
    if($#pagination > 10) {
        if($offset <= 5) {
            # offset at the beginning, include offsets 0 .. 8
            splice @pagination, 9, @pagination - (10), ({offset => -1});
        } else {
            if($offset < @pagination - 6) {
                # offset somewhere in the midle, include offsets (o-3 .. o+3)
                splice @pagination, $offset + 4, @pagination - ($offset + 5), ({offset => -1});
                splice @pagination, 1, $offset - 4, ({offset => -1});
            } else {
                #offset at the end, include offsets n-8 .. n
                splice @pagination, 1, @pagination - 10, ({offset => -1});
            }
        }
    }

    return \@pagination;
}

#-# sub get_default_slot_list
#-# parameter $c
#-# return \@slots
#-# description gets default speed dial slot set from admin.conf
sub get_default_slot_list {
  my ($c) = @_;

  if (defined $c->config->{speed_dial_vsc_presets} and ref $c->config->{speed_dial_vsc_presets}->{vsc} eq 'ARRAY') {
    return $c->config->{speed_dial_vsc_presets}->{vsc};
  } else {
    return [];
  }

  #my @slots = ();

  #for (my $i = 0; $i < 10; $i++) {
  #  push @slots,'#' . $i;
  #}
  #return \@slots;

}

#-# sub short_contact
#-# parameter $c, $contact
#-# return $short_contact
#-# description gets a short representation of a (contract) contact
sub short_contact {
  my ($c,$contact) = @_;

  if (defined $contact->{company} and length($contact->{company})) {
    return $contact->{company};
  } elsif (defined $contact->{lastname} and length($contact->{lastname})) {
    if (defined $contact->{firstname} and length($contact->{firstname})) {
        return $contact->{lastname} . ', ' . $contact->{firstname};
    } else {
        return $contact->{lastname};
    }
  } elsif (defined $contact->{firstname} and length($contact->{firstname})) {
      return $contact->{firstname};
  } else {
    #die?
    return '';
  }

}

#-# sub get_contract_contact_form_fields
#-# parameter $c
#-# return \%contract_contact_form_fields
#-# description defines contract contact form fields
sub get_contract_contact_form_fields {
    my ($c,$contact) = @_;

    return [ { field => 'firstname',
               label => 'First Name',
               value => $contact->{firstname} },
             { field => 'lastname',
               label => 'Last Name',
               value => $contact->{lastname}  },
             { field => 'company',
               label => 'Company',
               value => $contact->{company}    }];

}

sub get_qualified_number_for_subscriber {
    my ($c, $number) = @_;

    my $ccdp = $c->config->{cc_dial_prefix};
    my $acdp = $c->config->{ac_dial_prefix};

    if($number =~ /^\+/ or $number =~ s/^$ccdp/+/) {
        # nothing more to do
    } elsif($number =~ s/^$acdp//) {
        $number = '+'. $c->session->{subscriber}{cc} . $number;
    } else {
        $number = '+' . $c->session->{subscriber}{cc} . $c->session->{subscriber}{ac} . $number;
    }

    return $number;
}

# takes a catalyst session with subscriber information and a call list
# as returned by the prov. interface and returns a reference to an
# array suited for TT display
sub prepare_call_list {
    my ($c, $call_list, $filter) = @_;
    my $callentries = [];

    my @time = localtime time;
    my $tmtdy = timelocal(0,0,0,$time[3],$time[4],$time[5]);

    if(defined $filter and length $filter) {
        $filter =~ s/\*/.*/g;
    } else {
        undef $filter;
    }

    my $b = '';
    my $ccdp = $c->config->{cc_dial_prefix};

    foreach my $call (@$call_list) {
        my %callentry;
        $callentry{background} = $b ? '' : 'tr_alt';

        my @date = localtime $$call{start_time};
        $date[5] += 1900;
        $date[4]++;
        $callentry{date} = sprintf("%02d.%02d.%04d %02d:%02d:%02d", @date[3,4,5,2,1,0]);

        if($$call{duration}) {
            my $duration = $$call{duration};
            while($duration > 59) {
                my $left = sprintf("%02d", $duration % 60);
                $callentry{duration} = ":$left". (defined $callentry{duration} ? $callentry{duration} : '');
                $duration = int($duration / 60);
            }
            $callentry{duration} = defined $callentry{duration} ? sprintf("%02d", $duration) . $callentry{duration}
                                                                : sprintf("00:%02d", $duration);
        } elsif($$call{call_status} eq 'ok') {
            $callentry{duration} = '00:00';
        }

        if(defined $$call{call_fee}) {
            # money is allways returned as cents
            $callentry{call_fee} = sprintf $c->session->{voip_account}{billing_profile}{data}{currency} . " %.04f", $$call{call_fee}/100;
        } else {
            $callentry{call_fee} = '';
        }

        if(defined $$call{source_user}
           and $$call{source_user} eq $c->session->{subscriber}{username}
           and $$call{source_domain} eq $c->session->{subscriber}{domain})
        {
            if($$call{call_status} eq 'ok') {
                $callentry{direction_icon} = 'anruf_aus_small.gif';
            } else {
                $callentry{direction_icon} = 'anruf_aus_err_small.gif';
            }
            if($$call{destination_user} =~ /^\+?\d+$/) {
                my $partner = $$call{destination_user};
                $partner =~ s/^$ccdp/+/;
                $partner =~ s/^\+*/+/;
                $callentry{partner} = $partner;
            } else {
                $callentry{partner} = $$call{destination_user} .'@'. $$call{destination_domain};
            }
            $callentry{partner_number} = $callentry{partner};

        } elsif(defined $$call{destination_user}
                and $$call{destination_user} eq $c->session->{subscriber}{username}
                and $$call{destination_domain} eq $c->session->{subscriber}{domain})
        {
            if($$call{call_status} eq 'ok') {
                $callentry{direction_icon} = 'anruf_ein_small.gif';
            } else {
                $callentry{direction_icon} = 'anruf_ein_err_small.gif';
            }
            if(!defined $$call{source_cli} or !length $$call{source_cli}
               or $$call{source_cli} !~ /^\+?\d+$/)
            {
                if(!defined $$call{source_user} or !length $$call{source_user}) {
                    $callentry{partner} = 'anonym';
                } elsif($$call{source_user} =~ /^\+?\d+$/) {
                    my $partner = $$call{source_user};
                    $partner =~ s/^$ccdp/+/;
                    $partner =~ s/^\+*/+/;
                    $callentry{partner} = $partner;
                } else {
                    $callentry{partner} = $$call{source_user} .'@'. $$call{source_domain};
                }
            } else {
                my $partner = $$call{source_cli};
                $partner =~ s/^$ccdp/+/;
                $partner =~ s/^\+*/+/;
                $callentry{partner} = $partner;
            }
            $callentry{partner_number} = $callentry{partner};

        } else {
            $c->log->error("***Utils::prepare_call_list no match on user in call list");
            next;
        }

        if(defined $filter) {
            next unless $callentry{partner} =~ /$filter/i;
        }

        push @$callentries, \%callentry;

        $b = !$b;
    }

    return $callentries;
}


1;
