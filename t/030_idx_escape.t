#-*- perl -*-
#$Id$

use Test::More 0.88;
use Module::Build;
use lib '../lib';
use lib 'lib';
use lib 't/lib';
use Neo4p::Connect;
use strict;
use warnings;
no warnings qw(once);
my @cleanup;
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
plan tests => 4 + 5;

{
  my @node_defs = 
    (
     { name => 'A', type => 'purine' },
     { name => 'T', type => 'pyrimidine' },
     { name => 'G', type => 'purine'},
     { name => 'C', type => 'pyrimidine' }
    );
  @cleanup = my ($A,$T,$G,$C) = map { REST::Neo4p::Node->new($_) } @node_defs;

  ok my $nt_names = REST::Neo4p::Index->new('node','nt_names'), 'create node index(2)';

  push @cleanup, $nt_names if $nt_names;

  ok $nt_names->add_entry($T, 'nickname' => 'old thymy',
			  'friends_call_him' => 'Mr T'), 
			    'add multiple key/values';
  ok my ($mrt) = $nt_names->find_entries('friends_call_him' => 'Mr T'), 'found multiply added entry';
  is $mrt->get_property('name'), 'T', 'found right node' if $mrt;

  CLEANUP : {
    ok ($_->remove, 'entity removed') for reverse @cleanup;
  }
  }

done_testing;
