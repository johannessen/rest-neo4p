#-*-perl-*-
#$Id$
use Test::More;
use Test::Exception;
use Module::Build;
use lib qw|../lib lib|;
use lib 't/lib';
use Neo4p::Connect;
use strict;
use warnings;
no warnings qw(once);

my $build;
my ($user,$pass) = @ENV{qw/REST_NEO4P_TEST_USER REST_NEO4P_TEST_PASS/};

eval {
    $build = Module::Build->current;
    $user = $build->notes('user');
    $pass = $build->notes('pass');
};
my $TEST_SERVER = $build ? $build->notes('test_server') : $ENV{REST_NEO4P_TEST_SERVER} // 'http://127.0.0.1:7474';

use REST::Neo4p;

my $not_connected = connect($TEST_SERVER,$user,$pass);
diag "Test server unavailable (".$not_connected->message.") : tests skipped" if $not_connected;

plan skip_all => neo4j_index_unavailable() if neo4j_index_unavailable();
plan skip_all => 'no local connection to neo4j' if $not_connected;
plan tests => 3;

{
  ok my $idx = REST::Neo4p::Index->new('node', 'medicago_truncatula_3_5v5');
  is $idx->name('medicago_truncatula_3_5v5'), 'medicago_truncatula_3_5v5', 'index name is correct';

  CLEANUP : {
      ok $idx->remove, 'idx removed';
      1;
  }
}
