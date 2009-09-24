package admin::Utils;
use strict;
use warnings;

# Takes a search result as returned by the search_subscribers or
# search_customers provisioning functions, an offset and a limit and
# returns an array containing offset values for a pagination link list
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
    my ($c, $subscriber_list, $offset, $limit) = @_;
    my @pagination;

    foreach my $page (0 .. int(($$subscriber_list{total_count} - 1) / $limit)) {
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

1;
