#-*-perl-*-
#$Id$
use Test::More 0.88;
use Test::Exception;
use Module::Build;
use lib '../lib';
use lib 'lib';
use lib 't/lib';
use Neo4p::Connect;
use strict;
use warnings;
no warnings qw(once);
my @cleanup;
use REST::Neo4p;

my $build;
my ($user,$pass) = @ENV{qw/REST_NEO4P_TEST_USER REST_NEO4P_TEST_PASS/};

#$SIG{__DIE__} = sub { print $_[0] };
eval {
  $build = Module::Build->current;
  $user = $build->notes('user');
  $pass = $build->notes('pass');
};

my $TEST_SERVER = $build ? $build->notes('test_server') : $ENV{REST_NEO4P_TEST_SERVER} // 'http://127.0.0.1:7474';

my $not_connected = connect($TEST_SERVER,$user,$pass);
diag "Test server unavailable (".$not_connected->message.") : tests skipped" if $not_connected;

plan skip_all => neo4j_index_unavailable() if neo4j_index_unavailable();
plan skip_all => 'no local connection to neo4j' if $not_connected;
plan tests => 13 + 4;

{
  ok my $i = REST::Neo4p::Index->new('node', 'my_node_index');
  push @cleanup, $i if $i;
  my $f;
  ok $i->add_entry($f = REST::Neo4p::Node->new({ name => 'Fred Rogers' }),
                                       guy  => 'Fred Rogers');
  push @cleanup, $f if $f;
  ok my $index = REST::Neo4p->get_index_by_name('my_node_index','node');
  ok my ($my_node) = $index->find_entries('guy' => 'Fred Rogers');
  is $$my_node, $$f, 'got node from index';
  ok my $new_neighbor = REST::Neo4p::Node->new({'name' => 'Donkey Hoty'});
  push @cleanup, $new_neighbor if $new_neighbor;
  ok my $my_reln = $my_node->relate_to($new_neighbor, 'neighbor');
  is $my_reln->start_node->get_property('name'), 'Fred Rogers', 'got Mr. Rogers';
  is $my_reln->end_node->get_property('name'), 'Donkey Hoty', 'got Donkey Hoty';
  push @cleanup, $my_reln if $my_reln;
  ok my $query = REST::Neo4p::Query->new("MATCH p = (n)-[]->()
                                    WHERE id(n) = \$id
                                    RETURN p", {id => $my_node->id});
  ok $query->execute;
  my $path = $query->fetch->[0];
  my @path_nodes = $path->nodes;
  is scalar @path_nodes, 2, 'got path nodes';
  my @path_rels = $path->relationships;
  is scalar @path_rels, 1, 'got path reln';

}

END {
  CLEANUP : {
      ok ($_->remove, 'entity removed') for reverse @cleanup;
  }
}
