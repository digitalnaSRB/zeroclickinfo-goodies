package DDG::GoodieRole::Parse::List;
# ABSTRACT: Parse and format lists.

use strict;
use warnings;
use utf8;

use List::Util qw( all pairs );
use Data::Record;
use Regexp::Common;

my @parens = (
    '[' => ']',
    '(' => ')',
    '{' => '}',
);

sub is_conj {
    return shift =~ qr/^$RE{list}{and}$/i;
}

sub get_separator {
    my $text = shift;
    my $comma_sep = qr/\s*,\s*/io;
    return qr/(?:\s*,?\s*and\s*|$comma_sep)/io if is_conj($text);
    return $comma_sep;
}

sub remove_parens {
    my $text = shift;
    foreach (pairs @parens) {
        my ($opening, $closing) = map { quotemeta $_ } @$_;
        next unless $text =~ /^$RE{balanced}{-parens=>"$opening$closing"}$/;
        $text =~ s/^$opening(.*?)$closing$/$1/;
        return ($text, parens => [$opening, $closing]);
    }
    return $text;
}

sub trim_whitespace {
    my $to_trim = shift;
    $to_trim =~ s/^\s+//ro =~ s/\s+$//ro;
}

sub is_list {
    my ($text, %options) = @_;
    my $parens = join '', @{$options{parens}};
    return $text =~ qr/^$RE{balanced}{-parens=>$parens}$/ ? 1 : 0;
}

sub verify_items {
    my ($item_re, $nested, $items) = @_;
    my @items = @$items;
    return all { $_ =~ /^$item_re$/ } @items unless $nested;
    return all {
        ref $_ eq 'ARRAY'
            ? verify_items($item_re, $nested, $_)
            : $_ =~ /^$item_re$/;
    } @items;
}

sub join_with_last {
    my ($join, $join_last, @items) = @_;
    return '' unless @items;
    my $last = @items <= 1
        ? $items[$#items] : $join_last . $items[$#items];
    return join($join, @items[0..$#items-1]) . $last;
};

use namespace::autoclean;

use Moo::Role;

# Parse a list of items
#
# Options:
#
# C<item> - regex each item must match. Default is C<.*?\S>
# Items must I<fully> match (implied qr/^...$/).
#
# C<nested> - boolean whether nested lists should be parsed;
# default true. If C<item> is specified then it defaults to false.
sub parse_list {
    my ($list_text, %options) = @_;

    return unless ($list_text // '') ne '';
    my %defaults = (
        item   => qr/.*?\S/o,
        nested => $options{item} ? 0 : 1,
    );
    %options = (%defaults, %options);
    my $item = $options{item};

    ($list_text, my %parens) = remove_parens($list_text);
    return [] if $list_text eq '';
    my $sep = get_separator($list_text);
    my $parens = join '', @{$parens{parens} // []};
    my $record = Data::Record->new({
        split => $sep,
        unless => $options{nested} && $parens ? qr/(?:$RE{quoted}|$RE{balanced}{-parens=>$parens})/ : $RE{quoted},
    });
    my @items = map { trim_whitespace $_ } $record->records($list_text);
    my $should_parse_nested = $options{nested} && %parens;
    if ($should_parse_nested) {
        @items = map {
            is_list($_, %parens) ? parse_list($_, %options, %parens) : $_;
        } @items;
    }
    return unless verify_items($item, $options{nested}, \@items);
    return \@items;
}

# Options:
#
# C<parens> - either a string in the form '()' where '(' is the
# openening parenthesis and ')' is the closing parenthesis or
# an ARRAY in the form ['(', ')'] with the same definitions.
#
# C<join> - string to join items together with, default ', '.
sub format_list {
    my ($items, %options) = @_;
    my $parens = $options{parens} // '[]';
    my $join   = $options{join} // ', ';
    my $join_last = $options{join_last} // $join;
    @parens = ref $parens eq 'ARRAY'
        ? @$parens : split '', $parens;
    # In the case the user uses parens => '' we don't want to
    # display *any* parentheses, so we need to have 'fake'
    # parentheses.
    @parens = ('', '') if "@parens" eq '';
    my ($pl, $pr) = ($parens[0], $parens[$#parens]);
    my @inner_parens = @parens > 2
        ? @parens[1..$#parens-1] : @parens;
    my %inner_options = (
        %options, parens => \@inner_parens,
    );
    my @formatted_items = map {
        ref $_ eq 'ARRAY' ? format_list($_, %inner_options) : $_
    } @$items;
    return $pl . join_with_last(
        $join, $join_last, @formatted_items
    ) . $pr;
}

1;
