package ElasticSearch;

use strict;
use warnings FATAL => 'all';
use LWP::UserAgent();
use LWP::ConnCache();
use HTTP::Request();
use JSON::XS();
use Data::Dump qw(pp);
use Encode qw(decode_utf8);

our $VERSION = '0.02';

use constant { ONE_REQ     => 1,
               ONE_OPT     => 2,
               MULTI_ALL   => 3,
               MULTI_BLANK => 4,
};

use constant {
    CMD_INDEX_TYPE_ID => [ index => ONE_REQ, type => ONE_REQ, id => ONE_REQ ],
    CMD_INDEX_TYPE_id => [ index => ONE_REQ, type => ONE_REQ, id => ONE_OPT ],
    CMD_index      => [ index => MULTI_BLANK ],
    CMD_INDEX      => [ index => ONE_REQ ],
    CMD_index_TYPE => [ index => MULTI_ALL, type => ONE_REQ ],
    CMD_index_type => [ index => MULTI_ALL, type => MULTI_BLANK ],
    CMD_nodes      => [ nodes => MULTI_BLANK ],
};

our %Action = (

    ## DOCUMENT MANAGEMENT
    index => { cmd => CMD_INDEX_TYPE_id,
               qs  => {create  => [ 'boolean',  'opType=create' ],
                       timeout => [ 'duration', 'timeout' ],
               },
               data => 'data'
    },

    get => { cmd => CMD_INDEX_TYPE_ID },

    delete => { method => 'DELETE',
                cmd    => CMD_INDEX_TYPE_ID,
    },

    ## QUERIES
    search => { cmd  => CMD_index_type,
                data => 'query'
    },

    delete_by_query => { method  => 'DELETE',
                         cmd     => CMD_index_type,
                         postfix => '_query',
                         data    => 'query'
    },

    count => { cmd    => CMD_index_type,
               postfi => '_count',
               data   => 'query'
    },

    ## INDEX MANAGEMENT
    index_status => { cmd     => CMD_index,
                      postfix => '_status'
    },

    create_index => { method  => 'PUT',
                      cmd     => CMD_INDEX,
                      postfix => '',
                      data    => ['defn']
    },

    delete_index => { method  => 'DELETE',
                      cmd     => CMD_INDEX,
                      postfix => ''
    },

    flush_index => { method  => 'POST',
                     cmd     => CMD_index,
                     postfix => '_flush',
                     qs      => { refresh => [ 'boolean', 'refresh=1' ] },
    },

    refresh_index => { method  => 'POST',
                       cmd     => CMD_index,
                       postfix => '_refresh'
    },

    optimize_index => {
                    method  => 'POST',
                    cmd     => CMD_index,
                    postfix => '_optimize',
                    qs      => {
                        only_deletes => [ 'boolean', 'onlyExpungeDeletes=1' ],
                        refresh      => [ 'boolean', 'refresh=1' ],
                        flush        => [ 'boolean', 'flush=1' ]
                    },
    },

    snapshot_index => { method  => 'POST',
                        cmd     => CMD_index,
                        postfix => '_gateway/snapshot'
    },

    gateway_snapshot => { method  => 'POST',
                          cmd     => CMD_index,
                          postfix => '_gateway/snapshot'
    },

    create_mapping => { method  => 'PUT',
                        cmd     => CMD_index_TYPE,
                        postfix => '_mapping',
                        data    => { properties => 'properties' }
    },

    ## CLUSTER MANAGEMENT
    cluster_state => { prefix => '_cluster/state' },

    nodes => { prefix => '_cluser/nodes',
               cmd    => CMD_nodes,
               qs     => { settings => [ 'boolean', 'settings=1' ] }
    },
);

## Add 'create' action
$Action{create} = { %{ $Action{index} }, action => 'create' };
$Action{create}{qs}
    = { %{ $Action{index}{qs} }, create => [ 'fixed', 'opType=create' ] };

our %QS_Format = ( boolean  => '1 | 0',
                   duration => "'5m' | '10s'",
                   fixed    => ''
);

our %QS_Formatter = (
    fixed   => sub { return $_[1] },
    boolean => sub { return $_[0] ? $_[1] : $_[2] },
    duration => sub {
        my ( $t, $k ) = @_;
        return unless defined $t;
        return "$k=$t" if $t =~ /^[\d+][smh]$/i;
        die "$k '$t' is not in the form $QS_Format{duration}\n";
    },
);

#===================================
sub new {
#===================================
    my ( $proto, $params ) = &_params;
    my $self = bless { _JSON => JSON::XS->new() }, ref $proto || $proto;
    my $servers = delete $params->{servers};
    for ( keys %$params ) {
        $self->$_( $params->{$_} );
    }
    $self->refresh_servers($servers);
    return $self;
}

#===================================
sub index {
#===================================
    my ( $self, $params ) = &_params;
    my $action = delete $params->{_action} || 'index';
    $self->_do_action( {  %{ $Action{index} },
                          action => $action,
                          method => $params->{id} ? 'PUT' : 'POST',
                       },
                       $params,
    );
}

#===================================
sub set {
#===================================
    my ( $self, $params ) = &_params;
    $params->{_action} = 'set';
    return $self->index($params);
}
#===================================
sub create {
#===================================
    my ( $self, $params ) = &_params;
    $self->_do_action( {  %{ $Action{create} },
                          method => $params->{id} ? 'PUT' : 'POST',
                       },
                       $params,
    );
}

#===================================
sub get              { shift->_default_action( 'get',              @_ ) }
sub delete           { shift->_default_action( 'delete',           @_ ) }
sub delete_by_query  { shift->_default_action( 'delete_by_query',  @_ ) }
sub count            { shift->_default_action( 'count',            @_ ) }
sub search           { shift->_default_action( 'search',           @_ ) }
sub index_status     { shift->_default_action( 'index_status',     @_ ) }
sub create_index     { shift->_default_action( 'create_index',     @_ ) }
sub delete_index     { shift->_default_action( 'delete_index',     @_ ) }
sub flush_index      { shift->_default_action( 'flush_index',      @_ ) }
sub refresh_index    { shift->_default_action( 'refresh_index',    @_ ) }
sub optimize_index   { shift->_default_action( 'optimize_index',   @_ ) }
sub snapshot_index   { shift->_default_action( 'snapshot_index',   @_ ) }
sub gateway_snapshot { shift->_default_action( 'gateway_snapshot', @_ ) }
sub create_mapping   { shift->_default_action( 'create_mapping',   @_ ) }
sub cluster_state    { shift->_default_action( 'cluster_state',    @_ ) }
sub nodes            { shift->_default_action( 'nodes',            @_ ) }
#===================================

#===================================
sub _default_action {
#===================================
    my $self   = shift;
    my $action = shift;
    my $params = ref $_[0] ? shift : {@_};
    my $dfn    = $Action{$action}
        or $self->throw( 'Internal', "Unknown action '$action'" );
    $dfn->{action} = $action;
    $self->_do_action( $dfn, $params );
}

#===================================
sub _do_action {
#===================================
    my ( $self, $dfn, $params ) = @_;

    my ( $cmd, $data, $error );

    eval {
        $cmd = join '',
            grep {defined}
            $self->_build_cmd( $params, @{$dfn}{qw(prefix cmd postfix)} ),
            $self->_build_qs( $params, $dfn->{qs} );

        $data = $self->_build_data( $params, $dfn->{data} );

        1;
    } or $error = $@ || 'Unknown error';

    $self->throw( 'Param',
                  $error . $self->_usage($dfn),
                  { params => $params } )
        if $error;

    return
        $self->request( { method => $dfn->{method} || 'GET',
                          cmd    => $cmd,
                          data   => $data,
                        }
        );
}

#===================================
sub _usage {
#===================================
    my $self  = shift;
    my $dfn   = shift;
    my $usage = "Usage for '$dfn->{action}()':\n";
    my @cmd   = @{ $dfn->{cmd} };
    while ( my $key = shift @cmd ) {
        my $type = shift @cmd;
        my $arg_format
            = $type == ONE_REQ ? "\$$key"
            : $type == ONE_OPT ? "\$$key"
            :                    "\$$key | [\$${key}_1,\$${key}_n]";

        my $required = $type == ONE_REQ ? 'required' : 'optional';
        $usage .= sprintf( "  - %-15s =>  %-45s # %s\n",
                           $key, $arg_format, $required );
    }
    if ( my $qs = $dfn->{qs} ) {
        for ( sort keys %$qs ) {
            my $arg_format = $QS_Format{ $qs->{$_}[0] };
            $usage .= sprintf( "  - %-15s =>  %-45s # optional\n", $_,
                               $arg_format );
        }
    }

    if ( my $data = $dfn->{data} ) {
        $data = { data => $data } unless ref $data;
        my @keys = sort { $a->[0] cmp $b->[0] }
            map { ref $_ ? [ $_->[0], 'optional' ] : [ $_, 'required' ] }
            values %$data;

        for (@keys) {
            $usage .= sprintf( "  - %-15s =>  %-45s # %s\n",
                               $_->[0], '{' . $_->[0] . '}',
                               $_->[1] );
        }
    }
    return $usage;
}

#===================================
sub _build_qs {
#===================================
    my $self   = shift;
    my $params = shift;
    my $dfn    = shift or return;
    my @qs;
    foreach my $key ( keys %$dfn ) {
        my ( $format_name, @args ) = @{ $dfn->{$key} || [] };
        $format_name ||= '';

        my $formatter = $QS_Formatter{$format_name}
            or die "Unknown QS formatter '$format_name'";

        my $val = $formatter->( $params->{$key}, @args );
        push @qs, $val if defined $val;
    }
    return unless @qs;
    return '?' . join '&', @qs;
}

#===================================
sub _build_data {
#===================================
    my $self   = shift;
    my $params = shift;
    my $dfn    = shift or return;

    my $top_level;
    if ( ref $dfn ne 'HASH' ) {
        $top_level = 1;
        $dfn = { data => $dfn };
    }

    my %data;
KEY: while ( my ( $key, $source ) = each %$dfn ) {
        if ( ref $source eq 'ARRAY' ) {
            foreach (@$source) {
                my $val = $params->{$_};
                next unless defined $val;
                $data{$key} = $val;
                next KEY;
            }
        }
        else {
            $data{$key} = $params->{$source}
                or die "Missing required param '$source'\n";
        }
    }
    return $top_level ? $data{data} : \%data;
}

#===================================
sub _build_cmd {
#===================================
    my $self   = shift;
    my $params = shift;
    my ( $prefix, $dfn, $postfix ) = @_;

    my @dfn = (@$dfn);
    my @cmd;
    while (@dfn) {
        my $key  = shift @dfn;
        my $type = shift @dfn;

        my $val = $params->{$key};
        if ( defined $val ) {
            if ( ref $val eq 'ARRAY' ) {
                die "'$key' must be a single value\n"
                    if $type == ONE_REQ || $type == ONE_OPT;
                $val = join ',', @$val;
            }
        }
        else {
            next if $type == ONE_OPT || $type == MULTI_BLANK;
            die "Param '$key' is required\n"
                if $type == ONE_REQ;
            $val = '_all';
        }
        push @cmd, $val;
    }

    return join '/', '', grep {defined} ( $prefix, @cmd, $postfix );
}

#===================================
sub servers { shift->{_servers}{$$} }
#===================================

#===================================
sub refresh_servers {
#===================================
    my $self = shift;
    my @servers
        = @_ == 0 ? @{ ( values %{ $self->{_servers} } )[0] || [] }
        : ref $_[0] eq 'ARRAY' ? ( @{ $_[0] } )
        :                        (@_);

    my @live_servers;
    foreach my $server (@servers) {
        next unless $server;
        $server = 'http://' . $server unless $server =~ m{^http(?:s)?://};
        $server =~ s{/+$}{};

        my $nodes = eval {
            my $result = $self->_request( $server, 'GET', '/_cluster/nodes' );
            return $result->{nodes};
        } or next;

        @live_servers = map { $_->{httpAddress} }
            grep { $_->{httpAddress} } values %$nodes;
        last if @live_servers;
    }
    $self->throw( 'NoServers',
                  "Could not retrieve a list of active servers",
                  { servers => \@servers } )
        unless @live_servers;
    for (@live_servers) {
        $_ =~ m{inet\[(\S*)/(\S+):(\d+)\]};
        $_ = 'http://' . ( $1 || $2 ) . ':' . $3;
    }

    $self->{_servers} = { $$ => \@live_servers };
    $self->{_current_server}
        = { $$ => $live_servers[ int( rand(@live_servers) ) ] };
}

#===================================
sub current_server {
#===================================
    my $self = shift;
    unless ( $self->{_current_server}{$$} ) {
        $self->refresh_servers;
    }
    return $self->{_current_server}{$$};
}

#===================================
sub ua {
#===================================
    my $self = shift;
    unless ( $self->{_ua}{$$} ) {
        my $ua = $self->{_ua} = LWP::UserAgent->new( %{ $self->ua_options } );
        $ua->conn_cache( LWP::ConnCache->new );
        $self->{_ua} = { $$ => $ua };
    }
    return $self->{_ua}{$$};
}

#===================================
sub ua_options {
#===================================
    my $self = shift;
    if (@_) {
        ( undef, my $params ) = $self->_params(@_);
        $self->{_ua_options} = $params;
    }
    return $self->{_ua_options} ||= {};
}

#===================================
sub JSON { shift()->{_JSON} }
#===================================

#===================================
sub request {
#===================================
    my $self   = shift;
    my $params = shift;
    my $method = $params->{method} || 'GET';
    my $cmd    = $params->{cmd}
        || $self->throw( 'Request', "No cmd specified" );

    my $data = $params->{data};
    my $json = $self->JSON;
    $data = $json->encode($data)
        if defined $data;

    while (1) {
        my $current_server = $self->current_server;
        my ( $result, $error );
        eval {
            $result
                = $self->_request( $current_server, $method, $cmd, $data );
            1;
        } or $error = $@ || 'Unknown error';

        return $result unless $error;

        if ( ref $error ) {
            my $code = $error->{-vars}{status_code} || 0;
            my $msg  = $error->{-vars}{status_msg}  || '';
            if ( $code == 500 && $msg =~ /Can't connect/ ) {
                warn "Error connecting to '$current_server' : $msg";
                $self->refresh_servers;
                next;
            }
            $error->{-vars}{request} = $params;
            die $error;
        }

        $self->throw( 'Request', $error, { request => $params } );
    }
}

#===================================
sub _request {
#===================================
    my $self           = shift;
    my $current_server = shift;
    my $method         = shift;
    my $cmd            = shift;
    my $data           = shift;
    my $request = HTTP::Request->new( $method, $current_server . $cmd );

    $request->add_content_utf8($data)
        if defined $data;
    use Data::Dump qw(pp);
    pp( { cmd => $cmd, data => $data } );

    my $server_response = $self->ua->request($request);

    my $content = $server_response->decoded_content;
    $content = decode_utf8($content);

    my ( $result, $json_error );
    eval { $result = $self->JSON->decode($content); 1 }
        or $json_error = ( $@ || 'Unknown JSON error' );

    my $success = $server_response->is_success;

    return $result if $success && !$json_error;

    my $error_params = {
        server      => $current_server,
        response    => $json_error ? $content : $result,
        status_code => $server_response->code,
        status_msg  => $server_response->message,

    };

    my ( $error_type, $error_msg );
    if ( $success && $json_error ) {
        $error_type = 'JSON';
        $error_msg  = $json_error;
    }
    else {
        $error_type = 'Request';
        $error_msg
            = $result && $result->{error}
            ? $result->{error}
            : $error_params->{status_msg} . ' ('
            . $error_params->{status_code} . ')';
    }

    $self->throw( $error_type, $error_msg, $error_params );
}

#===================================
sub _params {
#===================================
    my $self = shift;
    my $params;
    if ( @_ % 2 ) {
        $self->throw( "Param",
                      'Expecting a HASH ref or a list of key-value pairs',
                      { params => \@_ } )
            unless ref $_[0] eq 'HASH';
        $params = shift;
    }
    else {
        $params = {@_};
    }
    return ( $self, $params );
}
#===================================
sub throw {
#===================================
    my $self = shift;
    my $type = shift;
    my $msg  = shift;
    my $vars = shift;

    my $class = ref $self || $self;
    my $error_class = $class . '::Error::' . $type;

    $msg = 'Unknown error' unless defined $msg;
    $msg =~ s/\n/\n    /g;

    my $debug = ref $self ? $self->debug : 1;
    my ( undef, $file, $line ) = caller(0);
    my $error = bless { -text       => $msg,
                        -line       => $line,
                        -file       => $file,
                        -vars       => $vars,
                        -stacktrace => $debug ? _stack_trace() : ''
    }, $error_class;

    die $error;
}

#===================================
sub _stack_trace {
#===================================
    my $i    = 2;
    my $line = ( '-' x 60 ) . "\n";
    my $o    = $line
        . sprintf( "%-4s %-30s %-5s %s\n",
                   ( '#', 'Package', 'Line', 'Sub-routine' ) )
        . $line;
    while ( my @caller = caller($i) ) {
        $o .= sprintf( "%-4d %-30s %4d  %s\n", $i++, @caller[ 0, 2, 3 ] );
        last if $caller[3] eq '(eval)';
    }
    return $o .= $line;
}

#===================================
sub debug {
#===================================
    my $self = shift;
    if (@_) { $self->{_debug} = !!shift() }
    return $self->{_debug};
}

#===================================
#===================================
package ElasticSearch::Error;
#===================================
#===================================
@ElasticSearch::Error::Internal::ISA  = __PACKAGE__;
@ElasticSearch::Error::Param::ISA     = __PACKAGE__;
@ElasticSearch::Error::NoServers::ISA = __PACKAGE__;
@ElasticSearch::Error::Request::ISA   = __PACKAGE__;
@ElasticSearch::Error::JSON::ISA      = __PACKAGE__;

use strict;
use warnings FATAL => 'all', NONFATAL => 'redefine';

use overload ( '""' => 'stringify' );
use Data::Dump qw(pp);

#===================================
sub stringify {
#===================================
    my $error     = shift;
    my $object_id = $error->{-object_id};

    my $msg
        = '[ERROR] ** '
        . ( ref($error) || 'ElasticSearch::Error' ) . ' at '
        . $error->{-file}
        . ' line '
        . $error->{-line} . " : \n"
        . ( $error->{-text} || 'Missing error message' ) . "\n"
        . ( $error->{-vars}
            ? "With vars:\n" . pp( $error->{-vars} ) . "\n"
            : ''
        ) . $error->{-stacktrace};
    return $msg;
}

=head1 NAME

ElasticSearch - An API for communicating with ElasticSearch

=head1 VERSION

Version 0.01 - this is an alpha release

=cut

=head1 DESCRIPTION

ElasticSearch is an Open Source (Apache 2 license), distributed, RESTful
Search Engine based on Lucene, and built for the cloud, with a JSON API.

Check out its features: L<http://www.elasticsearch.com/products/elasticsearch/>

This module is a thin API which makes it easy to communicate with an
ElasticSearch cluster.

It maintains a list of all servers/nodes in the ElasticSearch cluster, and
spreads the load randomly across these nodes.  If the current active node
disappears, then it attempts to connect to another node in the list.

Forking a process triggers a server list refresh, and a new connection to
a randomly chosen node in the list.

=cut

=head1 SYNOPSIS


    use ElasticSearch;
    my $e = ElasticSearch->new( servers => 'search.foo.com', debug => 1 );

    $e->index(
        index => 'twitter',
        type  => 'tweet',
        id    => 1,
        data  => {
            user        => 'kimchy',
            postDate    => '2009-11-15T14:12:12',
            message     => 'trying out Elastic Search'
        }
    );

    $data = $e->get(
        index => 'twitter',
        type  => 'tweet',
        id    => 1
    );

    $results = $e->search(
        index => 'twitter',
        type  => 'tweet',
        query => {
            term    => { user => 'kimchy' },
        }
    );

=cut

=head1 GETTING ElasticSearch

You can download the latest release from
L<http://www.elasticsearch.com/download/>, or to build from source on Unix:

    cd ~
    git clone git://github.com/elasticsearch/elasticsearch.git
    cd elasticsearch
    ./gradlew clean devRelease

    cd /path/where/you/want/elasticsearch
    unzip ~/elasticsearch/distributions/elasticsearch*

To start a test server in the foreground:

   ./bin/elasticsearch -f

You can start multiple servers by repeating this command - they will
autodiscover each other.

More instructions are available here:
L<http://www.elasticsearch.com/docs/elasticsearch/setup/installation>

=cut

=head1 CALLING CONVENTIONS

I've tried to follow the same terminology as used in the ElasticSearch docs
when naming methods, so it should be easy to tie the two together.

Some methods require a specific C<index> and a specific C<type>, while others
allow a list of indices or types, or allow you to specify all indices or
types. I distinguish between them as follows:

   $e->method( index => multi, type => single, ...)

C<multi> values can be:

      index   => 'twitter'          # specific index
      index   => ['twitter','user'] # list of indices
      index   => undef              # (or not specified) = all indices

C<single> values must be a scalar, and are required parameters

      type  => 'tweet'

=cut

=head1 RETURN VALUES AND EXCEPTIONS

Methods that query the ElasticSearch cluster return the raw data structure
that the cluster returns.  This may change in the future, but as these
data structures are still in flux, I thought it safer not to try to interpret.

Anything that is know to be an error throws an exception, eg trying to delete
a non-existent index.

=cut

=head1 METHODS

=head2 Creating a new ElasticSearch instance

=head3 C<new()>

    $e = ElasticSearch->new(
            servers     =>  '127.0.0.1:9200'            # single server
                            | ['es1.foo.com:9200',
                               'es2.foo.com:9200'],     # multiple servers
            debug       => 1 | 0,
            ua_options  => { LWP::UserAgent options},

     );

C<servers> is a required parameter and can be either a single server or an
ARRAY ref with a list of servers.  These servers are used to retrieve a list
of all servers in the cluster, after which one is chosen at random to be
the L</"current_server()">.

See also: L</"debug()">, L</"ua_options()">,
          L</"refresh_servers()">, L</"servers()">, L</"current_server()">

=cut

=head2 Document-indexing methods

=head3 C<index()>

    $result = $e->index(
        index   => single,
        type    => single,
        id      => $document_id,        # optional, otherwise auto-generated
        data    => {
            key => value,
            ...
        },
        timeout => eg '1m' or '10s'     # optional
        create  => 1 |0                 # optional
    );

eg:

    $result = $e->index(
        index   => 'twitter',
        type    => 'tweet',
        id      => 1,
        data    => {
            user        => 'kimchy',
            postDate    => '2009-11-15T14:12:12',
            message     => 'trying out Elastic Search'
        },
    );

Used to add a document to a specific C<index> as a specific C<type> with
a specific C<id>. If the C<index/type/id> combination already exists,
then that document is updated, otherwise it is created.

Note:

=over

=item *

If the C<id> is not specified, then ElasticSearch autogenerates a unique
ID and a new document is always created.

=item *

If C<create> is C<true>, then a new document is created, even if the same
C<index/type/id> combination already exists!  C<create> can be used to
slightly increase performance when creating documents that are known not
to exists in the index.

=back

See also: L<http://www.elasticsearch.com/docs/elasticsearch/rest_api/index>
and L</"create_mapping()">


=head3 C<set()>

C<set()> is a synonym for L</"index()">


=head3 C<create()>

C<create> is a synonym for L</"index()"> but sets C<create> to C<true>

=head3 C<get()>

    $result = $e->get(
        index   => single,
        type    => single,
        id      => single,
    );

Returns the document stored at C<index/type/id> or throws an exception if
the document doesn't exist.

Example:

    $e->get( index => 'twitter', type => 'tweet', id => 1)
    Returns:
    {
      _id     => 1,
      _index  => "twitter",
      _source => {
                   message => "trying out Elastic Search",
                   postDate => "2009-11-15T14:12:12",
                   user => "kimchy",
                 },
      _type   => "tweet",
    }

See also: L<KNOWN ISSUES>,
          L<http://www.elasticsearch.com/docs/elasticsearch/json_api/get>

=head3 C<delete()>

    $result = $e->delete(
        index   => single,
        type    => single,
        id      => single,
    );

Deletes the document stored at C<index/type/id> or throws an exception if
the document doesn't exist.

Example:

    $e->delete( index => 'twitter', type => 'tweet', id => 1);

See also: L<http://www.elasticsearch.com/docs/elasticsearch/json_api/delete>

=head3 C<delete_by_query()>

    $result = $e->delete_by_query(
        index   => multi,
        type    => multi,
        query   => {...}
    );

Deletes any documents matching the query. Documents can be matched against
multiple indices and multiple types, eg

    $result = $e->delete_by_query(
        index   => undef,               # all
        type    => ['user','tweet'],
        query   => { term => {user => 'kimchy' }}
    );

See also L</"search()">,
         L<http://www.elasticsearch.com/docs/elasticsearch/json_api/delete_by_query>

=head3 C<count()>

    $result = $e->count(
        index   => multi,
        type    => multi,
        query   => {...}
    );

Counts the number of documents matching the query. Documents can be matched
against multiple indices and multiple types, eg

    $result = $e->count(
        index   => undef,               # all
        type    => ['user','tweet'],
        query   => { term => {user => 'kimchy' }}
    );

See also L</"search()">,
         L<http://www.elasticsearch.com/docs/elasticsearch/json_api/count>

=head3 C<search()>

    $result = $e->search(
        index   => multi,
        type    => multi,
        query   => {...}
    );

Searches for all documents matching the query. Documents can be matched
against multiple indices and multiple types, eg:

    $result = $e->search(
        index   => undef,               # all
        type    => ['user','tweet'],
        query   => { term => {user => 'kimchy' }}
    );

For all of the options that can be included in the C<query> parameter, see
L<http://www.elasticsearch.com/docs/elasticsearch/json_api/search>


=cut

=head2 Index Admin methods

=head3 C<index_status()>

    $result = $e->index_status(
        index   => multi,
    );

Returns the status of
    $result = $e->index_status();                               #all
    $result = $e->index_status( index => ['twitter','buzz'] );
    $result = $e->index_status( index => 'twitter' );

See L<http://www.elasticsearch.com/docs/elasticsearch/json_api/admin/indices/status>
=head3 C<create_index()>

    $result = $e->create_index(
        index   => single,
        defn    => {...}        # optional
    );

Creates a new index, optionally setting certain paramters, eg:

    $result = $e->create_index(
        index   => 'twitter',
        defn    => {
                numberOfShards      => 3,
                numberOfReplicas    => 2,
        }
    );

Throws an exception if the index already exists.

See L<http://www.elasticsearch.com/docs/elasticsearch/json_api/admin/indices/create_index>

=head3 C<delete_index()>

    $result = $e->delete_index(
        index   => single
    );

Deletes an existing index, or throws an exception if the index doesn't exist, eg:

    $result = $e->delete_index( index => 'twitter' );

See L<http://www.elasticsearch.com/docs/elasticsearch/json_api/admin/indices/delete_index>

=head3 C<flush_index()>

    $result = $e->flush_index(
        index   => multi
    );

Flushes one or more indices. The flush process of an index basically frees
memory from the index by flushing data to the index storage and clearing the
internal transaction log. By default, ElasticSearch uses memory heuristics
in order to automatically trigger flush operations as required in order to
clear memory.

Example:

    $result = $e->flush_index( index => 'twitter' );

See L<http://www.elasticsearch.com/docs/elasticsearch/json_api/admin/indices/flush>

=head3 C<refresh_index()>

    $result = $e->refresh_index(
        index   => multi
    );

Explicitly refreshes one or more indices, making all operations performed
since the last refresh available for search. The (near) real-time capabilities
depends on the index engine used. For example, the robin one requires
refresh to be called, but by default a refresh is scheduled periodically.

Example:

    $result = $e->refresh_index( index => 'twitter' );

See L<http://www.elasticsearch.com/docs/elasticsearch/json_api/admin/indices/refresh>

=head3 C<gateway_snapshot()>

    $result = $e->gateway_snapshot(
        index   => multi
    );

Explicitly performs a snapshot through the gateway of one or more indices
(backs them up ). By default, each index gateway periodically snapshot changes,
though it can be disabled and be controlled completely through this API.

Example:

    $result = $e->gateway_snapshot( index => 'twitter' );

See L<http://www.elasticsearch.com/docs/elasticsearch/json_api/admin/indices/gateway_snapshot>
and L<http://www.elasticsearch.com/docs/elasticsearch/modules/gateway>

=head3 C<snapshot_index()>

C<snapshot_index()> is a synonym for L</"gateway_snapshot()">

=head3 C<optimize_index()>

    $result = $e->optimize_index(
        index           => multi,
        only_deletes    => 1 | 0,  # onlyExpungeDeletes
        flush           => 1 | 0,  # flush after optmization
        refresh         => 1 | 0,  # refresh after optmization
    )

=head3 C<create_mapping()>

    $result = $e->create_mapping(
        index       => multi,
        type        => single,
        properties  => { ... }      # required
    );

A C<mapping> is the data definition of a C<type>.  If no mapping has been
specified, then ElasticSearch tries to infer the types of each field in
document, by looking at its contents, eg

    'foo'       => string
    123         => integer
    1.23        => float

However, these heuristics can be confused, so it safer (and much more powerful)
to specify an official C<mapping> instead, eg:

    $result = $e->create_mapping(
        index   => ['twitter','buzz'],
        type    => 'tweet',
        properties  =>  {
            user        =>  {type  =>  "string", index      =>  "not_analyzed"},
            message     =>  {type  =>  "string", nullValue  =>  "na"},
            postDate    =>  {type  =>  "date"},
            priority    =>  {type  =>  "integer"},
            rank        =>  {type  =>  "float"}
        }
    );

See also: L<http://www.elasticsearch.com/docs/elasticsearch/json_api/admin/indices/create_mapping>
and L<http://www.elasticsearch.com/docs/elasticsearch/mapping>

=cut

=head2 Cluster admin methods

=head3 C<cluster_state()>

    $result = $e->cluster_state();

Returns cluster state information.

See L<http://www.elasticsearch.com/docs/elasticsearch/json_api/admin/cluster/state/>

=head3 C<nodes()>

    $result = $e->nodes(
        nodes       => multi,
        settings    => 1 | 0        # optional
    );

Returns information about one or more nodes or servers in the cluster. If
C<settings> is C<true>, then it includes the node settings information.

See: L<http://www.elasticsearch.com/docs/elasticsearch/json_api/admin/cluster/nodes_info>

=cut

=head2 Module-specific methods

=head3 C<servers()>

    $servers = $e->servers

Returns a list of the servers/nodes known to be in the cluster the last time
that L</"refresh_servers()"> was called.

=head3 C<refresh_servers()>

    $e->refresh_servers( $server | [$server_1, ...$server_n])
    $e->refresh_servers()

Tries to contact each server in the list to retrieve a list of servers/nodes
currently in the cluster. If it succeeds, then it updates L</"servers()"> and
randomly selects one server to be the L</"current_server()">

If no servers are passed in, then it uses the list from L</"servers()"> (ie
the last known good list) instead.

Throws an exception if no servers can be found.

C<refresh_server> is called from :

=over

=item L</"new()">

=item if any L</"request()"> fails

=item if the process forks and the PID changes

=back

=head3 C<current_server()>

    $current_server = $e->current_server()

Returns the current server for the current PID, or if none is set, then it
tries to get a new current server by calling L</"refresh_servers()">.

=head3 C<ua()>

    $ua = $e->ua

Returns the current L<LWP::UserAgent> instance for the current PID.  If there is
none, then it creates a new instance, with any options specified in
L</"ua_options()">

C<Keep-alive> is used by default (via L<LWP::ConnCache>).

=head3 C<ua_options()>

    $ua_options = $e->ua({....})

Get/sets the current list of options to be used when creating a new
C<LWP::UserAgent> instance.  You may, for instance, want to set C<timeout>

This is best set when creating a new instance of ElasticSearch with L</"new()">.

=cut

=head3 C<JSON()>

    $json_xs = $e->JSON

Returns the current L<JSON::XS> object which is used to encode and decode
all JSON when communicating with ElasticSearch.

If you need to change the JSON settings you can do (eg):

    $e->JSON->utf8

It is probably better not to fiddle with this!  ElasticSearch expects all
data to be provided as Perl strings (not as UTF8 encoded byte strings) and
returns all data from ElasticSearch as Perl strings.

=cut

=head3 C<request()>

    $result = $e->request({
        method  => 'GET|PUT|POST|DELETE',
        cmd     => url,                     # eg '/twitter/tweet/123'
        data    => $hash_ref                # converted to JSON document
    })

The C<request()> method is used to communicate with the ElasticSearch
L</"current_server()">.  If any request fails with a C<Can't connect> error,
then C<request()> tries to refresh the server list, and repeats the request.

Any other error will throw an exception.

=head3 C<throw()>

    $e->throw('ErrorType','ErrorMsg', {vars})

Throws an exception of C<ref $e . '::Error::' . $error_type>, eg:

    $e->throw('Param', 'Missing required param', { params => $params})

... will thrown an error of class C<ElasticSearch::Error::Param>.

Any vars passed in will be available as C<< $error->{-vars} >>.

If L</"debug()"> is C<true>, then C<< $error->{-stacktrace} >> will contain a
stacktrace.

=head3 C<debug()>

    $e->debug(1|0);

If C<debug()> is C<true>, then exceptions include a stack trace.

=cut

=head1 AUTHOR

Clinton Gormley, C<< <drtech at cpan.org> >>

=head1 KNOWN ISSUES

=over

=item   L</"get()">

The C<_source> key that is returned from a L</"get()"> contains the original JSON
string that was used to index the document initially.  ElasticSearch parses
JSON more leniently than L<JSON::XS>, so if invalid JSON is used to index the
document (eg unquoted keys) then C<< $e->get(....) >> will fail with a
JSON exception.

Any documents indexed via this module will be not susceptible to this problem.

=back

=head1 TODO

Currently there are no tests in this module, as testing would require a live
ElasticSearch server - I plan to add these shortly.

=head1 BUGS

This is an alpha module, so there will be bugs, and the API is likely to
change in the future, as the API of ElasticSearch itself changes.

If you have any suggestions for improvements, or find any bugs, please report
them to C<bug-elasticsearch at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=ElasticSearch>.
I will be notified, and then you'll automatically be notified of progress on
your bug as I make changes.


=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc ElasticSearch


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=ElasticSearch>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/ElasticSearch>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/ElasticSearch>

=item * Search CPAN

L<http://search.cpan.org/dist/ElasticSearch/>

=back


=head1 ACKNOWLEDGEMENTS

Thanks to Shay Bannon, the ElasticSearch author, for producing an amazingly
easy to use search engine.

=head1 LICENSE AND COPYRIGHT

Copyright 2010 Clinton Gormley.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


=cut

1;
