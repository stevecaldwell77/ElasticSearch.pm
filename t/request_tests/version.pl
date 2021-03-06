#!perl

use Test::More;
use strict;
use warnings;
our $es;
my $r;

isa_ok $r = $es->current_server_version, 'HASH', 'Current server version';
ok $r->{number}, ' - has a version string';
ok $r->{date},   ' - has a build date';
ok defined $r->{snapshot_build}, ' - has snapshot_build';

note "Current server is "
    . ( $r->{snapshot_build} ? 'development ' : '' )
    . "version "
    . $r->{number};
note "Built: " . $r->{date};

1;
