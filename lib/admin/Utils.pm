package admin::Utils;
use strict;
use warnings;

use Time::Local;
use HTML::Entities;
use POSIX;
use DateTime::TimeZone::OffsetOnly;
use GD::Simple;

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
    my ($c, $username, $domain, $call_list, $filter, $bilprof) = @_;
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
            my $duration = ceil($$call{duration});
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
            $callentry{call_fee} = sprintf $$bilprof{data}{currency} . " %.04f", $$call{call_fee}/100;
        } else {
            $callentry{call_fee} = '';
        }

        if(defined $$call{source_user}
           and $$call{source_user} eq $username
           and $$call{source_domain} eq $domain)
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
                and $$call{destination_user} eq $username
                and $$call{destination_domain} eq $domain)
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

# this prepares the list of preferences for display in the template
sub prepare_tt_prefs {
    my ($c, $db_prefs, $preferences) = @_;
    my @stashprefs;

    foreach my $pref (eval { @$db_prefs }) {
        # managed separately
        next if $$pref{preference} eq 'lock';

        if($$pref{preference} eq 'cfu'
           or $$pref{preference} eq 'cfb'
           or $$pref{preference} eq 'cft'
           or $$pref{preference} eq 'cfna')
        {
          if(defined $$preferences{$$pref{preference}} and length $$preferences{$$pref{preference}}) {
            my $vbdom = $c->config->{voicebox_domain};
            my $fmdom = $c->config->{fax2mail_domain};
            my $confdom = $c->config->{conference_domain};
            if($$preferences{$$pref{preference}} =~ /\@$vbdom$/) {
              $$preferences{$$pref{preference}} = 'voicebox';
            } elsif($$preferences{$$pref{preference}} =~ /\@$fmdom$/) {
              $$preferences{$$pref{preference}} = 'fax2mail';
            } elsif($$preferences{$$pref{preference}} =~ /\@$confdom$/) {
              $$preferences{$$pref{preference}} = 'conference';
            }
          }
        } elsif(!$c->stash->{ncos_levels} and ($$pref{preference} eq 'ncos' or $$pref{preference} eq 'adm_ncos')) {
          my $ncoslvl;
          return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_ncos_levels',
                                                              undef,
                                                              \$ncoslvl
                                                            );
          $c->stash->{ncos_levels} = $ncoslvl if eval { @$ncoslvl };
        } elsif(!$c->stash->{rewrite_rule_sets} and $$pref{preference} eq 'rewrite_rule_set') {
          my $rules;
          return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_rewrite_rule_sets',
                                                              undef,
                                                              \$rules
                                                            );
          $c->stash->{rewrite_rule_sets} = $rules if eval { @$rules };
        } elsif($$pref{preference} eq 'block_in_list' or $$pref{preference} eq 'block_out_list') {
          eval { map { s/^([1-9])/+$1/; $_ } @{$$preferences{$$pref{preference}}} }; ## no critic ProhibitMutatingListFunctions
        }

        push @stashprefs,
             { key         => $$pref{preference},
               data_type   => $$pref{data_type},
               value       => $$preferences{$$pref{preference}},
               max_occur   => $$pref{max_occur},
               description => encode_entities($$pref{description}),
               error       => $c->session->{messages}{$$pref{preference}}
                              ? $c->model('Provisioning')->localize($c, $c->view($c->config->{view})->
                                                                            config->{VARIABLES}{site_config}{language},
                                                                    $c->session->{messages}{$$pref{preference}})
                              : undef,
             };
    }

    return \@stashprefs;
}

# this prepares the list of preferences for the prov. interface
sub prepare_db_prefs {
    my ($c, $db_prefs, $preferences, $domain, $username) = @_;

    foreach my $db_pref (eval { @$db_prefs }) {

        next if $$db_pref{read_only};

        if($$db_pref{preference} eq 'cfu'
                or $$db_pref{preference} eq 'cfb'
                or $$db_pref{preference} eq 'cft'
                or $$db_pref{preference} eq 'cfna')
        {
            my $vbdom = $c->config->{voicebox_domain};
            my $fmdom = $c->config->{fax2mail_domain};
            my $confdom = $c->config->{conference_domain};

            my $fwtype = $$db_pref{preference};
            my $fw_target_select = $c->request->params->{$fwtype .'_target'} || 'disable';

            unless(defined $username) {  # forwards for domains and peers are not supported
                $c->session->{messages}{$fwtype} = 'Client.Voip.MalformedTarget';
                next;
            }

            my $fw_target;
            if($fw_target_select eq 'sipuri') {
                $fw_target = $c->request->params->{$fwtype .'_sipuri'};

                # normalize, so we can do some checks.
                $fw_target =~ s/^sip://i;

                if($fw_target =~ /^\+?\d+$/) {
                    $fw_target = admin::Utils::get_qualified_number_for_subscriber($c, $fw_target);
                    my $checkresult;
                    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'check_E164_number', { e164number => $fw_target }, \$checkresult);
                    $c->session->{messages}{$fwtype} = 'Client.Voip.MalformedNumber'
                        unless $checkresult;
                } elsif($fw_target =~ /^[a-z0-9&=+\$,;?\/_.!~*'()-]+\@[a-z0-9.-]+(:\d{1,5})?$/i) {
                    $fw_target = 'sip:'. lc $fw_target;
                } elsif($fw_target =~ /^[a-z0-9&=+\$,;?\/_.!~*'()-]+$/) {
                    $fw_target = 'sip:'. lc($fw_target) .'@'. $domain;
                } else {
                    $c->session->{messages}{$fwtype} = 'Client.Voip.MalformedTarget';
                    $fw_target = $c->request->params->{$fwtype .'_sipuri'};
                }
            } elsif($fw_target_select eq 'voicebox') {
                $fw_target = 'sip:vmu'.$c->session->{subscriber}{cc}.$c->session->{subscriber}{ac}.$c->session->{subscriber}{sn}."\@$vbdom";
            } elsif($fw_target_select eq 'fax2mail') {
                $fw_target = 'sip:'.$c->session->{subscriber}{cc}.$c->session->{subscriber}{ac}.$c->session->{subscriber}{sn}."\@$fmdom";
            } elsif($fw_target_select eq 'conference') {
                $fw_target = 'sip:conf='.$c->session->{subscriber}{cc}.$c->session->{subscriber}{ac}.$c->session->{subscriber}{sn}."\@$confdom";
            }
            $$preferences{$fwtype} = $fw_target;
        } elsif($$db_pref{preference} eq 'cli') {
            $$preferences{cli} = $c->request->params->{cli} or undef;
            unless(defined $username) {  # CLI for domains and peers is not supported
                $c->session->{messages}{cli} = 'Client.Voip.MalformedNumber';
                next;
            }
            if(defined $$preferences{cli} and $$preferences{cli} =~ /^\+?\d+$/) {
                $$preferences{cli} = admin::Utils::get_qualified_number_for_subscriber($c, $$preferences{cli});
                my $checkresult;
                return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'check_E164_number', { e164number => $$preferences{cli} }, \$checkresult);
                $c->session->{messages}{cli} = 'Client.Voip.MalformedNumber'
                    unless $checkresult;
            }
        } elsif($$db_pref{preference} eq 'cc') {
            $$preferences{$$db_pref{preference}} = $c->request->params->{$$db_pref{preference}} || undef;
            if(defined $$preferences{$$db_pref{preference}}) {
                my $checkresult;
                return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'check_cc',
                                                                    { cc => $$preferences{$$db_pref{preference}} }, \$checkresult
                                                                  );
                $c->session->{messages}{$$db_pref{preference}} = 'Client.Voip.MalformedCc'
                    unless $checkresult;
            }
        } elsif($$db_pref{preference} eq 'ac'
                or $$db_pref{preference} eq 'svc_ac'
                or $$db_pref{preference} eq 'emerg_ac')
        {
            $$preferences{$$db_pref{preference}} = $c->request->params->{$$db_pref{preference}} || undef;
            if(defined $$preferences{$$db_pref{preference}}) {
                my $checkresult;
                return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'check_ac',
                                                                    { ac => $$preferences{$$db_pref{preference}} }, \$checkresult
                                                                  );
                $c->session->{messages}{$$db_pref{preference}} = 'Client.Voip.MalformedAc'
                    unless $checkresult;
            }
        } elsif($$db_pref{max_occur} != 1) {
            # multi-value preferences are handled separately
        } elsif($$db_pref{data_type} eq 'int' or $$db_pref{data_type} eq 'string') {
            if(length $c->request->params->{$$db_pref{preference}}) {
                $$preferences{$$db_pref{preference}} = $c->request->params->{$$db_pref{preference}};
            } else {
                $$preferences{$$db_pref{preference}} = undef;
            }
        } elsif($$db_pref{data_type} eq 'boolean') {
            $$preferences{$$db_pref{preference}} = $c->request->params->{$$db_pref{preference}} ? 1 : undef;
        } elsif($$db_pref{data_type} eq 'enum') {
            # zero length value means user chose to not set this preference 
            $$preferences{$$db_pref{preference}} = (length($c->request->params->{$$db_pref{preference}}) > 0 )
                ?  $c->request->params->{$$db_pref{preference}}
                :  undef
        } else {
            # wtf? ignoring invalid preference
        }
    }

    if($$preferences{cft}) {
        unless(defined $$preferences{ringtimeout} and $$preferences{ringtimeout} =~ /^\d+$/
           and $$preferences{ringtimeout} < 301 and $$preferences{ringtimeout} > 4)
        {
            $c->session->{messages}{ringtimeout} = 'Client.Voip.MissingRingtimeout';
        }
    }

    return 1;
}

# this prepares a list preferences for display in the template
sub prepare_tt_list {
    my ($c, $list)  = @_;
    my (@list_to_sort, @sorted_list);

    foreach my $entry (@$list) {
        my $active = $entry =~ s/^#// ? 0 : 1;
        $entry =~ s/^([1-9])/+$1/;
        push @list_to_sort, { entry => $entry, active => $active };
    }

    my $bg = '';
    my $i = 1;
    foreach my $entry (sort {$a->{entry} cmp $b->{entry}} @list_to_sort) {
        push @sorted_list, { number     => $$entry{entry},
                             background => $bg ? '' : 'tr_alt',
                             id         => $i++,
                             active     => $$entry{active},
                           };
        $bg = !$bg;
    }

    return \@sorted_list;
}

# this adds, deletes, activates or deactivates entries from a block list
sub addelact_blocklist {
    my ($c, $preferences, $list, $add, $del, $act) = @_;

    if(defined $add) {
        if($add =~ /^\+?[?*0-9\[\]-]+$/) {
            my $ccdp = $c->config->{cc_dial_prefix};
            my $acdp = $c->config->{ac_dial_prefix};
            if($add =~ /^\*/ or $add =~ /^\?/ or $add =~ /^\[/) {
                # do nothing
            } elsif($add =~ s/^\+// or $add =~ s/^$ccdp//) {
                # nothing more to do
            } elsif($add =~ s/^$acdp//) {
                $add = $$preferences{cc} . $add;
            } else {
                $add = $$preferences{cc} . $$preferences{ac} . $add;
            }
            my $blocklist = $$preferences{$list};
            $blocklist = [] unless defined $blocklist;
            $blocklist = [ $blocklist ] unless ref $blocklist;
            $$preferences{$list} = [ @$blocklist, $add ];
        } else {
            $c->session->{messages}{msgadd} = 'Client.Voip.MalformedNumberPattern';
            $c->session->{blockaddtxt} = $add;
        }
    }

    if(defined $del) {
        my $blocklist = $$preferences{$list};
        if(defined $blocklist) {
            my $ccdp = $c->config->{cc_dial_prefix};
            my $acdp = $c->config->{ac_dial_prefix};
            if($del =~ /^\*/ or $del =~ /^\?/ or $del =~ /^\[/) {
                # do nothing
            } elsif($del =~ s/^\+// or $del =~ s/^$ccdp//) {
                # nothing more to do
            } elsif($del =~ s/^$acdp//) {
                $del = $$preferences{cc} . $del;
            }
            $blocklist = [ $blocklist ] unless ref $blocklist;
            if($c->request->params->{block_stat}) {
                $$preferences{$list} = [ grep { $_ ne $del } @$blocklist ];
            } else {
                $$preferences{$list} = [ grep { $_ ne '#'.$del } @$blocklist ];
            }
        }
    }

    if(defined $act) {
        my $blocklist = $$preferences{$list};
        if(defined $blocklist) {
            my $ccdp = $c->config->{cc_dial_prefix};
            my $acdp = $c->config->{ac_dial_prefix};
            if($act =~ /^\*/ or $act =~ /^\?/ or $act =~ /^\[/) {
                # do nothing
            } elsif($act =~ s/^\+// or $act =~ s/^$ccdp//) {
                # nothing more to do
            } elsif($act =~ s/^$acdp//) {
                $act = $c->session->{subscriber}{cc} . $act;
            }
            $blocklist = [ $blocklist ] unless ref $blocklist;
            if($c->request->params->{block_stat}) {
                $$preferences{$list} = [ grep { $_ ne $act } @$blocklist ];
                push @{$$preferences{$list}}, '#'.$act;
            } else {
                $$preferences{$list} = [ grep { $_ ne '#'.$act } @$blocklist ];
                push @{$$preferences{$list}}, $act;
            }
        }
    }

    return 1;
}

# this adds or deletes entries from an IP list
sub addel_iplist {
    my ($c, $preferences, $list, $add, $del) = @_;

    if(defined $add) {
        my $checkresult;
        return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'check_ipnet', { ipnet => $add }, \$checkresult);
        if($checkresult) {
            my $iplist = $$preferences{$list};
            $iplist = [] unless defined $iplist;
            $iplist = [ $iplist ] unless ref $iplist;
            $$preferences{$list} = [ @$iplist, $add ];
        } else {
            $c->session->{messages}{msgadd} = 'Client.Syntax.MalformedIPNet';
            $c->session->{listaddtxt} = $add;
        }
    }

    if(defined $del) {
        my $iplist = $$preferences{$list};
        if(defined $iplist) {
            $iplist = [ $iplist ] unless ref $iplist;
            $$preferences{$list} = [ grep { $_ ne $del } @$iplist ];
        }
    }

    return 1;
}

=head2 tz_offset

Returns localhost's offset to GMT in seconds

=cut

sub tz_offset {
    use DateTime::TimeZone::OffsetOnly;
    my $tz_offset = DateTime::TimeZone::OffsetOnly->new ( offset => strftime("%z", localtime(time())) );
    return $tz_offset->{offset} ;
}

=head2 generate_pcap

Returns pcap data from packets

=cut

sub generate_pcap {
    my $packets = shift;

    my $pcap = pack("LSSlLLL",
        0xa1b2c3d4,     # magic number
        2, 4,           # major/minor version number
        0, 0,           # gmt offset and timestamp accuracy
        0xffff,         # snap length
        1,		# data link type (http://www.tcpdump.org/linktypes.html)
        );

    foreach my $pkg(@{$packets}) {
        my($ts_sec, $ts_usec) = $pkg->{timestamp} =~ /^(\d+)\.(\d+)$/;
        my $len = length($pkg->{header}) + length($pkg->{payload}) + length($pkg->{trailer});

        $pcap .= pack("LLLLa*a*a*",
                $ts_sec, $ts_usec,      # timestamp
                $len, $len,             # bytes on-wire/off-wire
                $pkg->{header},
                $pkg->{payload},
                $pkg->{trailer},
                );
    }
    return $pcap;
}

sub draw_line {
  my ($c, $from_x, $from_y, $to_x, $to_y, $width, $color) = @_;
  $c->fgcolor($color);
  $c->moveTo($from_x, $from_y);
  $c->penSize($width, $width);
  $c->lineTo($to_x, $to_y);
}

sub draw_arrow {
  my ($c, $from_x, $from_y, $to_x, $to_y, $width, $color) = @_;
  $c->fgcolor($color);
  $c->moveTo($from_x, $from_y);
  $c->penSize($width, $width);
  $c->lineTo($to_x, $to_y);
  my $poly = new GD::Polygon;
  $poly->addPt($to_x, $to_y);
  my $dir = ($to_x > $from_x) ? -1 : 1;
  $poly->addPt($to_x + 4*$width*$dir, $to_y - 2*$width-(($width%2)?0:1));
  $poly->addPt($to_x + 4*$width*$dir, $to_y + 2*$width);
  my $oldbgcolor = $c->bgcolor();
  $c->bgcolor($color);
  $c->penSize(1,1);
  $c->polygon($poly);
  $c->bgcolor($oldbgcolor);
}

sub draw_text {
  my ($c, $x, $y, $ftype, $fsize, $fcolor, $txt) = @_;
  $c->font($ftype);
  $c->fontsize($fsize);
  $c->fgcolor($fcolor);
  $c->moveTo($x, $y);
  $c->string($txt);
  my @b = $c->stringBounds($txt);
  my %bounds = ('x', $x, 'y', $y, 'dx', $b[0], 'dy', $b[1]);
  return %bounds;
}

sub process_callmap {
    my $c = shift;
    my $packets = shift;
    my $r_png = shift;
    my $r_info = shift;
    my $i = 0;

    my %int_uas = (
      $c->config->{sipstats}->{lb_int}, 'lb',
      $c->config->{sipstats}->{lb_ext}, 'lb',
      $c->config->{sipstats}->{proxy},  'proxy',
      $c->config->{sipstats}->{sbc},    'sbc',
      $c->config->{sipstats}->{app},    'app',
    );

    my $canvas_margin = 100; # enough free space around diagram for text etc
    my $canvas_elem_distance = 220; # horizontal distance between element lines
    my $canvas_pkg_distance = 30; # vertical distance between packet arrows

    my $canvas_elem_line_width = 2;
    my $canvas_elem_line_color = 'darkgray';
    my $canvas_elem_font = 'Courier:bold';
    my $canvas_elem_font_size = 8;
    my $canvas_elem_font_color = 'darkgray';

    my $canvas_pkg_line_width = 2;
    my $canvas_pkg_line_color = 'green';
    my %canvas_pkg_line_colors = (TCP => 'blue');
    my $canvas_pkg_font = 'Courier:bold';
    my $canvas_pkg_font_size = 8;
    my $canvas_pkg_font_color = 'dimgray';

    my $html_padding = 5;

    my %ext_uas = ();
    my @uas = ();

    ### gather all involved elements
    foreach my $packet(@{$packets}) {
      if(exists($int_uas{$packet->{src_ip}.':'.$packet->{src_port}})) {
        #print "skipping internal elem ".$packet->{src_ip}.':'.$packet->{src_port}." (".$int_uas{$packet->{src_ip}.':'.$packet->{src_port}}.")\n";
      }
      elsif(exists($ext_uas{$packet->{src_ip}.':'.$packet->{src_port}})) {
        #print "skipping known external elem ".$packet->{src_ip}.':'.$packet->{src_port}."\n";
      }
      else {
        #print "adding new src elem ".$packet->{src_ip}.':'.$packet->{src_port}."\n";
        $ext_uas{$packet->{src_ip}.':'.$packet->{src_port}} = 1;
        # TODO: prefix "proto:" as well
        push @uas, $packet->{src_ip}.':'.$packet->{src_port};
      }

      if(exists($int_uas{$packet->{dst_ip}.':'.$packet->{dst_port}})) {
        #print "skipping internal elem ".$packet->{dst_ip}.':'.$packet->{dst_port}." (".$int_uas{$packet->{dst_ip}.':'.$packet->{dst_port}}.")\n";
      }
      elsif(exists($ext_uas{$packet->{dst_ip}.':'.$packet->{dst_port}})) {
        #print "skipping known external elem ".$packet->{dst_ip}.':'.$packet->{dst_port}."\n";
      }
      else {
        #print "adding new dst elem ".$packet->{dst_ip}.':'.$packet->{dst_port}."\n";
        $ext_uas{$packet->{dst_ip}.':'.$packet->{dst_port}} = 1;
        # TODO: prefix "proto:" as well
        push @uas, $packet->{dst_ip}.':'.$packet->{dst_port};
      }
    }
    push @uas, ('lb', 'sbc', 'proxy', 'app');

    ### calculate x position of all uas
    my %uas_pos_x = ();
    $i = 0;
    foreach my $ua(@uas) {
      my $name = $ua;
      foreach my $k(keys %int_uas) {
        if($ua eq $int_uas{$k}) {
          $uas_pos_x{$k} = $canvas_margin + $canvas_elem_distance*$i;
        }
      }
      $uas_pos_x{$ua} = $canvas_margin + $canvas_elem_distance*$i;
      ++$i;
    }

    ### calculate canvas size
    # TODO: take into account length of "proto:[ipv6]:port"
    my $canvas_width = 2*$canvas_margin + $canvas_elem_distance*(@uas - 1);
    my $canvas_height = 2*$canvas_margin + $canvas_pkg_distance*(@{$packets} + 1); # leave one pkg_distance free at begin and end
    my $canvas = GD::Simple->new($canvas_width, $canvas_height);
    $canvas->bgcolor('white');

    ### prepare html
    $r_info->{width} = $canvas_width;
    $r_info->{height} = $canvas_height;
    $r_info->{areas} = ();

    ### draw vertical lines
    my $offset = $canvas_margin;
    foreach my $ua(@uas) {
      draw_line($canvas, $offset, $canvas_margin, $offset, $canvas_height-$canvas_margin, $canvas_elem_line_width, $canvas_elem_line_color);
      my @bounds = $canvas->stringBounds($ua); # get bounds for text centering
      draw_text($canvas, $offset-int(abs($bounds[0])/2), $canvas_margin-abs($bounds[1]), $canvas_elem_font, $canvas_elem_font_size, $canvas_elem_font_color, $ua);
      $offset += $canvas_elem_distance;
    }

    ### draw arrows
    my $last_timestamp = undef;
    my $y_offset = $canvas_margin + $canvas_pkg_distance;
    $i = 1;
    foreach my $packet(@{$packets}) {
      my $time_offset = defined $last_timestamp ? ($packet->{timestamp} - $last_timestamp) : 0;
      $last_timestamp = $packet->{timestamp};
      my $from_x = $uas_pos_x{$packet->{src_ip}.':'.$packet->{src_port}};
      my $to_x = $uas_pos_x{$packet->{dst_ip}.':'.$packet->{dst_port}};
      #print "arrow from ".$packet->{src_ip}.':'.$packet->{src_port}." to ".$packet->{dst_ip}.':'.$packet->{dst_port}.": $from_x - $to_x\n";
      draw_arrow($canvas, $from_x, $y_offset, $to_x, $y_offset, $canvas_pkg_line_width,
      	$canvas_pkg_line_colors{$packet->{transport}} || $canvas_pkg_line_color);
      $packet->{payload} =~ /\ncseq:\s*(\d+)\s+[a-zA-Z]+/i;
      my $cseq = $1 ? $1 : '?';
      my $txt = sprintf($i.'. '.$packet->{method}.' ('.$cseq.', +%0.3fs)', $time_offset);
      my @bounds = $canvas->stringBounds($txt); # get bounds for text centering
      if($from_x < $to_x) {
        $from_x = $from_x+int($canvas_elem_distance/2)-int($bounds[0]/2);
      } elsif($from_x > $to_x) {
        $from_x = $from_x-int($canvas_elem_distance/2)-int($bounds[0]/2);
      } else {
        $from_x += 10; # call to itself, e.g. in cf loop
      }
      draw_text($canvas, $from_x, $y_offset-int(abs($bounds[1])/2), $canvas_pkg_font, $canvas_pkg_font_size, $canvas_pkg_font_color, $txt);

      push @{$r_info->{areas}}, {"id", $packet->{id}, "coords", ($from_x-$html_padding).','.($y_offset-abs($bounds[1])-$html_padding).','.($from_x+abs($bounds[0])+$html_padding).','.($y_offset)};

      $y_offset += $canvas_pkg_distance;
      ++$i;
    }
    $$r_png = $canvas->png;
}


sub generate_callmap {
    my $c = shift;
    my $packets = shift;
    my $png; my %info;
    process_callmap($c, $packets, \$png, \%info);
    return \%info;
}

sub generate_callmap_png {
    my $c = shift;
    my $packets = shift;
    my $png; my %info;
    process_callmap($c, $packets, \$png, \%info);
    return $png;    
}

1;
