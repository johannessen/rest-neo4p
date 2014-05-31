#$Id$
package REST::Neo4p::Batch;
use REST::Neo4p::Exceptions;
use JSON::Streaming::Reader;
require REST::Neo4p;

use base qw(Exporter);
use strict;
use warnings;
no warnings qw(once);

BEGIN {
  $REST::Neo4p::Batch::VERSION = '0.2252';
}

our @EXPORT = qw(batch);
our @BATCH_ACTIONS = qw(keep_objs discard_objs);

sub batch (&@) {
  my ($coderef,$action) = @_;
  my $agent = REST::Neo4p->agent;
  my @errors;
  REST::Neo4p::CommException->throw("Not connected\n") unless REST::Neo4p->connected;
  warn 'Agent already in batch_mode on batch() call' if ($agent->batch_mode);
  REST::Neo4p::LocalException->throw("batch requires argument 'keep_objs' or 'discard_objs'\n") unless ($action && grep(/^$action$/,qw/keep_objs discard_objs/));
  $agent->batch_mode(1);
  $coderef->();
  for ($action) {
    /^discard_objs$/ && do {
      # do in eval to catch an agent error...
      while (my $tmpfh = $agent->execute_batch_chunk) {
	@errors = _scan_for_errors($tmpfh);
	1;
      }
      last;
    };
    /^keep_objs$/ && do {
      while (my $tmpfh = $agent->execute_batch_chunk) {
	@errors = _scan_for_errors($tmpfh);
	_process_objs($tmpfh);
      }
      last;
    };
    do { # fallthru
      die "I shouldn't be here."
    };
  }
  $agent->batch_mode(undef);
  return @errors;
}

sub _scan_for_errors {
  my $tmpfh = shift;

  $tmpfh->seek(0,0);
#  open $tmpfh;
  my $jsonr = JSON::Streaming::Reader->for_stream($tmpfh);
  my $in_response;
  my @errors;
  PARSE :
      while (my $cursor = $jsonr->get_token) {
	for ($$cursor[0]) {
	  /start_array/ && do {
	    $in_response = 1;
	    last;
	  };
	  /start_object/ && do {
	    unless ($in_response) {
	      REST::Neo4p::LocalException->throw("Unexpected token in server batch response\n");
	    }
	    my $obj = $jsonr->slurp;
	    if ($obj->{status} !~ m/^2../) {
	      warn "Error at id ".$obj->{id}." from ".$obj->{from}.": status ".$obj->{status} if $REST::Neo4p::VERBOSE;
	      push @errors, REST::Neo4p::Neo4jException->new(code=>$obj->{status},message => 'Server returned '.$obj->{status}.' at job id '.$obj->{id}.' from '.$obj->{from}, neo4j_message=>$obj->{message});
	    }
	    last;
	  };
	  /end_array/ && do {
	    last PARSE;
	  };
	}
	1;
      }
  return @errors;
}

# right now, look for 'body' elts, and
# create new nodes, relationships as they are encountered
#
# TODO: handling indexes, queries? Prevent queries in batch mode?
# TODO: use JSON streaming from file

sub _process_objs {
  my $tmpfh = shift;
  $tmpfh->seek(0,0);
#  open $tmpfh;
  my $jsonr = JSON::Streaming::Reader->for_stream($tmpfh);
  my $in_response;
  PARSE : 
      while ( my $cursor = $jsonr->get_token ) {
	for ($$cursor[0]) {
	  /start_array/ && do {
	    $in_response = 1;
	    last;
	  };
	  /start_object/ && do {
	    unless ($in_response) {
	      REST::Neo4p::LocalException->throw("Unexpected token in server batch response\n");
	    }
	    _register_object($jsonr->slurp);
	    last;
	  };
	  /end_array/ && do {
	    last PARSE;
	  };
	}
      }
  return;
}

sub _register_object {
  my $decoded_batch_resp = shift;
  my ($id, $from, $body) = @{$decoded_batch_resp}{qw(id from body)};
  return unless $body;
  return if ($decoded_batch_resp->{status} !~ m/^2../); # ignore an error here
  my $obj;
  if ($body->{template}) {
    $obj = REST::Neo4p::Index->new_from_json_response($body);
  }
  elsif ($body->{self} =~ m|node/[0-9]+$|) {
    $obj = REST::Neo4p::Node->new_from_json_response($body);
  }
  elsif ($body->{self} =~ m|relationship/[0-9]+$|) {
    $obj = REST::Neo4p::Relationship->new_from_json_response($body);
  }
  else {
    warn "Don't understand object in batch response: id ".$id;
  }
  if ($obj) {
    my $batch_objs = $REST::Neo4p::Entity::ENTITY_TABLE->{batch_objs};
    if ( my $batch_obj = delete $batch_objs->{ "{$id}" } ) {
      $$batch_obj = $$obj;
    }
  }
  return;
}

sub _cleanup_batch_objs {
  
}

=head1 NAME

REST::Neo4p::Batch - Mixin for batch processing

=head1 SYNOPSIS

 use REST::Neo4p;
 use REST::Neo4p::Batch;
 use List::MoreUtils qw(pairwise);

 my @bunch = map { "new_node_$_" } (1..100);
 my @nodes;
 batch {
  my $idx = REST::Neo4p::Index->new('node','bunch');
  @nodes = map { REST::Neo4p::Node->new({name => $_}) } @bunch;
  pairwise { $idx->add_entry($a, name => $b) } @nodes, @bunch;
  $nodes[$_]->relate_to($nodes[$_+1],'next_node') for (0..$#nodes-1);
 } 'keep_objs';

 $idx = REST::Neo4p->get_index_by_name('node','bunch');
 ($the_99th_node) = $nodes[98];
 ($points_to_100th_node) = $the_99th_node->get_outgoing_relationships;
 ($the_100th_node) = $idx->find_entries( name => 'new_node_100');


=head1 DESCRIPTION

REST::Neo4p::Batch adds some syntactic sugar allowing ordinary
REST::Neo4p code to be processed through the Neo4j REST batch API.

=head1 batch {} ($action)

To execute server calls generated by REST::Neo4p code, 
wrap the code in a batch block:

 batch {
  # create and manipulate REST::Neo4p objects
 } $action;

The C<$action> parameter B<must be> (there is no default) one of 

=over

=item * 'keep_objs'

If C<keep_objs> is specified, any nodes, relationships or indexes
returned in the server reponse will be created in memory as
REST::Neo4p objects.

=item * 'discard_objs'

If C<discard_objs> is specified, Neo4j entities in the server response
will not be automatically registered as REST::Neo4p objects. Of
course, these objects can be retrieved from the server through object
creation and other methods, outside of the batch block.

 #!perl
 # loader...
 use REST::Neo4p;
 use REST::Neo4p::Batch;
 
 open $f, shift() or die $!;
 batch {
   while (<$f>) {
    chomp;
    ($name, $value) = split /\t/;
    REST::Neo4p::Node->new({name => $name, value => $value});
   } 'discard_objs';
 exit(0);

=back

=head2 Errors in batch jobs

C<batch{}()> returns returns an array of
L<REST::Neo4p::Exceptions|REST::Neo4p::Neo4jException> error objects for each job that returns
a server-generated error. If no errors were encountered, it returns
undef.

 foreach ( batch { _do_stuff() } 'discard_objs' ) {
   print STDERR $_->message, "(", $_->code, ")\n";
 }

C<batch> will C<warn()> for each error immediately if
C<$REST::Neo4p::VERBOSE> is set.

=head1 CAVEATS

=over 

=item *

No call to the server is made until after the block is executed. There
is some magic provided, but not all object functionality is available
to REST::Neo4p entities obtained within the C<batch> block.

For example, this works:

 my $idx = REST::Neo4p::Index->new('node' => 'pals_of_bob');
 my $name = 'fred'
 batch {
  my $node = REST::Neo4p::Node->new({name => $name});
  $idx->add_entry($node, name => $name);
 } 'keep_objs';

but this does not:

 my $idx = REST::Neo4p::Index->new('node' => 'pals_of_bob');
 my $name = 'fred';
 batch {
  my $node = REST::Neo4p::Node->new({name => $name});
  $idx->add_entry($node, name => $node->get_property('name'));
 } 'keep_objs';

because $node has not been created on the server at the time that
add_entry() is executed, so C<get_property('name')> fails.

=back

=head1 SEE ALSO

L<REST::Neo4p>, L<REST::Neo4p::Agent>

=head1 AUTHOR

    Mark A. Jensen
    CPAN ID: MAJENSEN
    majensen -at- cpan -dot- org

=head1 LICENSE

Copyright (c) 2012-2014 Mark A. Jensen. This program is free software; you
can redistribute it and/or modify it under the same terms as Perl
itself.

=cut

1;
