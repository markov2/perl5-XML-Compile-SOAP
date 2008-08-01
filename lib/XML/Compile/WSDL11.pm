use warnings;
use strict;

package XML::Compile::WSDL11;
use base 'XML::Compile';

use Log::Report 'xml-compile-soap', syntax => 'SHORT';

use XML::Compile::Schema  ();
use XML::Compile::SOAP    ();
use XML::Compile::Util    qw/pack_type unpack_type/;
use XML::Compile::SOAP::Util qw/:wsdl11/;

use XML::Compile::WSDL11::Operation ();

use List::Util  qw/first/;

XML::Compile->addSchemaDirs(__FILE__);
XML::Compile->knownNamespace
 ( &WSDL11       => 'wsdl.xsd'
 , &WSDL11SOAP   => 'wsdl-soap.xsd'
 , &WSDL11HTTP   => 'wsdl-http.xsd'
 , &WSDL11MIME   => 'wsdl-mime.xsd'
 , &WSDL11SOAP12 => 'wsdl-soap12.xsd'
 );

=chapter NAME

XML::Compile::WSDL11 - create SOAP messages defined by WSDL 1.1

=chapter SYNOPSIS

 # preparation
 my $wsdl    = XML::Compile::WSDL11->new($wsdlfile);
 $wsdl->addWSDL(...additional WSDL file...);
 $wsdl->importDefinitions(...more schemas...);

 my $call    = $wsdl->compileClient('GetStockPrice');

 my $op      = $wsdl->operation('GetStockPrice');
 my $call    = $op->compileClient;

 my $answer  = $call->(%request);
 my ($answer, $trace) = $call->(%request);

 my @op_defs = $wsdl->operations;

 # Install XML::Compile::SOAP::Daemon
 my $server  = XML::Compile::SOAP::HTTPDaemon->new;
 $server->actionsFromWSDL($wsdl);
 
 # For debug info, start your script with:
 use Log::Report mode => 'DEBUG';

=chapter DESCRIPTION

This module currently supports WSDL 1.1 on SOAP 1.1, with HTTP-SOAP.
B<Missing are> pure HTTP GET/POST bindings, multipart-mime transport
protocols, WSDL2 and SOAP 1.2.

An WSDL file defines a set of messages to be send and received over SOAP
connections.  As end-user, you do not have to worry about the complex
details of the messages and the exchange of them: it's all Perl to you.
Also faults are handled automatically.

The only complication you have to worry about, is to shape
a nested HASH structure to the sending message structure.
M<XML::Compile::Schema::template()> may help you.

When the definitions are spread over multiple files, you will need to
use M<addWSDL()> (wsdl), or M<importDefinitions()> (additional schema's)
explicitly, because M<XML::Compile::Schema> does not wish dynamic internet
download magic to happen.

=chapter METHODS

=section Constructors

=c_method new XML, OPTIONS
The XML is the WSDL file, which is anything accepted by
M<XML::Compile::dataToXML()>.  All options are also passed
to create an internal M<XML::Compile::Schema> object.  See
M<XML::Compile::Schema::new()>

=option  wsdl_namespace IRI
=default wsdl_namespace C<undef>
Force to accept only WSDL descriptions which are in this namespace.  If
not specified, the name-space  which is found in the first WSDL document
is used.

=option  schemas XML::Compile::Schema object
=default schemas <created internally>
=cut

sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);

    $self->{schemas} = $args->{schemas} || XML::Compile::Schema->new;
    $self->{index}   = {};
    $self->{wsdl_ns} = $args->{wsdl_namespace};

    $self->addWSDL($args->{top});
    $self;
}

=section Accessors

=method schemas
Returns the M<XML::Compile::Schema> object which collects all type
information.
=cut

sub schemas() { shift->{schemas} }

=method wsdlNamespace [NAMESPACE]
Returns (optionally after setting) the namespace used by the WSDL
specification.  This is the namespace in which the C<definition>
document root element is defined.
=cut

sub wsdlNamespace(;$)
{   my $self = shift;
    @_ ? ($self->{wsdl_ns} = shift) : $self->{wsdl_ns};
}

=section Extension

=method addWSDL XMLDATA
Some XMLDATA, accepted by M<XML::Compile::dataToXML()> is provided,
which should represent the top-level of a (partial) WSDL document.
The specification can be spread over multiple files, which each have a
C<definition> root element.
=cut

sub addWSDL($)
{   my ($self, $data) = @_;

    defined $data or return;
    my ($node, %details) = $self->dataToXML($data)
        or return $self;

    my $schemas = $self->schemas;

    # Collect the user schema

    $node    = $node->documentElement
        if $node->isa('XML::LibXML::Document');

    $node->localName eq 'definitions'
        or error __x"root element for WSDL is not 'definitions'";

    $schemas->importDefinitions($node, details => \%details);

    # Collect the WSDL schemata

    my $wsdlns  = $node->namespaceURI;
    my $corens  = $self->wsdlNamespace || $self->wsdlNamespace($wsdlns);

    $corens eq $wsdlns
        or error __x"wsdl in namespace {wsdlns}, where already using {ns}"
               , wsdlns => $wsdlns, ns => $corens;

    $wsdlns eq WSDL11
        or error __x"don't known how to handle {wsdlns} WSDL files"
               , wsdlns => $wsdlns;

    $schemas->importDefinitions($wsdlns, %details);

    my %hook_kind =
     ( type         => pack_type($wsdlns, 'tOperation')
     , after        => 'ELEMENT_ORDER'
     );

    my $reader    = $schemas->compile        # to parse the WSDL
     ( READER       => pack_type($wsdlns, 'definitions')
     , anyElement   => 'TAKE_ALL'
     , anyAttribute => 'TAKE_ALL'
     , hook         => \%hook_kind
     );

    my $spec = $reader->($node);
    my $tns  = $spec->{targetNamespace}
        or error __x"WSDL sets no targetNamespace";

    # WSDL 1.1 par 2.1.1 says: WSDL def types each in own name-space
    my $index     = $self->{index};
    my $toplevels = $spec->{gr_import} || [];  # silly WSDL structure
    foreach my $toplevel (@$toplevels)
    {   my ($which, $def) = %$toplevel;        # always only one
        $index->{$which}{pack_type $tns, $def->{name}} = $def
            if $which =~ m/^(?:service|message|binding|portType)$/;
    }

    foreach my $service ( @{$spec->{service} || []} )
    {   foreach my $port ( @{$service->{port} || []} )
        {   $index->{port}{pack_type $tns, $port->{name}} = $port;
        }
    }

    $self;
}

=method importDefinitions XMLDATA, OPTIONS
Add schema information to the WSDL interface knowledge.  This should
not be needed, because WSDL definitions must be self-contained.
=cut

sub importDefinitions($@) { shift->schemas->importDefinitions(@_) }

=method namesFor CLASS
Returns the list of names available for a certain definition
CLASS in the WSDL.
=cut

sub namesFor($)
{   my ($self, $class) = @_;
    keys %{shift->index($class) || {}};
}

=method operation [NAME], OPTIONS
Collect all information for a certain operation.  Returned is an
M<XML::Compile::WSDL11::Operation> object.

An operation is defined by a service name, a port, some bindings,
and an operation name, which can be specified explicitly or sometimes
left-out.

When not specified explicitly via OPTIONS, each of the CLASSes are only
permitted to have exactly one definition.  Otherwise, you must make a
choice explicitly.  There is a very good reason to be not too flexible
in this area: developers need to be aware when there are choices, where
some flexibility is required.

=option  service QNAME
=default service <only when just one>
Required when more than one service is defined.

=option  port NAME
=default port <only when just one>
Required when more than one port is defined.

=requires operation NAME
Ignored when the parameter list starts with a NAME (which is an
alternative for this option).  Optional when there is only
one operation defined within the portType.

=cut

# new options, then also add them to the list in compileClient()

sub operation(@)
{   my $self = shift;
    my $name = @_ % 2 ? shift : undef;
    my %args = @_;

    my $service   = $self->find(service => delete $args{service});

    my $port;
    my @ports     = @{$service->{port} || []};
    my @portnames = map {$_->{name}} @ports;
    if(my $portname = delete $args{port})
    {   $port = first {$_->{name} eq $portname} @ports;
        error __x"cannot find port `{portname}', pick from {ports}"
            , portname => $portname, ports => join("\n    ", '', @portnames)
           unless $port;
    }
    elsif(@ports==1)
    {   $port = shift @ports;
    }
    else
    {   error __x"specify port explicitly, pick from {portnames}"
            , portnames => join("\n    ", '', @portnames);
    }

    my $bindname  = $port->{binding}
        or error __x"no binding defined in port '{name}'"
               , name => $port->{name};

    my $binding   = $self->find(binding => $bindname);

    my $type      = $binding->{type}
        or error __x"no type defined with binding `{name}'"
               , name => $bindname;

    my $portType  = $self->find(portType => $type);
    my $types     = $portType->{operation}
        or error __x"no operations defined for portType `{name}'"
               , name => $type;

    my @port_ops  = map {$_->{name}} @$types;

    $name       ||= delete $args{operation};
    my $port_op;
    if(defined $name)
    {   $port_op = first {$_->{name} eq $name} @$types;
        error __x"no operation `{operation}' for portType {porttype}, pick from{ops}"
            , operation => $name
            , porttype => $type
            , ops => join("\n    ", '', @port_ops)
            unless $port_op;
    }
    elsif(@port_ops==1)
    {   $port_op = shift @port_ops;
    }
    else
    {   error __x"multiple operations in portType `{porttype}', pick from {ops}"
            , porttype => $type
            , ops => join("\n    ", '', @port_ops)
    }

    my @bindops = @{$binding->{operation} || []};
    my $bind_op = first {$_->{name} eq $name} @bindops;

    my $operation = XML::Compile::WSDL11::Operation->new
     ( service  => $service
     , port     => $port
     , binding  => $binding
     , portType => $portType
     , wsdl     => $self
     , port_op  => $port_op
     , bind_op  => $bind_op
     , name     => $name
     );

    $operation;
}

=method compileClient [NAME], OPTIONS
Creates temporarily an M<XML::Compile::WSDL11::Operation> with M<operation()>,
and then calls C<compileClient()> on that; an usual combination.

As OPTIONS are available the combination of all possibilities for
=over 4
=item .
M<operation()> (i.e. C<service> and C<port>), and all of
=item .
M<XML::Compile::WSDL11::Operation::compileClient()> (a whole lot,
for instance C<transport_hook>), plus
=item .
everything you can pass to M<XML::Compile::Schema::compile()>, for
instance C<< check_values => 0 >>, hooks, and typemaps.
=back

=example
  $wsdl->compileClient
    ( operation => 'HelloWorld'
    , port      => 'PrefillSoap' # only needed when multiple ports
    , sloppy_integers => 1
    );
=cut

sub compileClient(@)
{   my $self = shift;
    unshift @_, 'operation' if @_ % 2;
    my $op   = $self->operation(@_) or return ();
    $op->compileClient(@_);
}

#---------------------

=section Inspection

All of the following methods are usually NOT meant for end-users. End-users
should stick to the M<operation()> and M<compileClient()> methods.

=method index [CLASS, [QNAME]]
With a CLASS and QNAME, it returns one WSDL definition HASH or undef.
Returns the index for the CLASS group of names as HASH.  When no CLASS is
specified, a HASH of HASHes is returned with the CLASSes on the top-level.
=cut

sub index(;$$)
{   my $index = shift->{index};
    @_ or return $index;

    my $class = $index->{ (shift) }
       or return ();

    @_ ? $class->{ (shift) } : $class;
}

=method find CLASS, [QNAME]
With a QNAME, the HASH which contains the parsed XML information
from the WSDL template for that CLASS-NAME combination is returned.
When the NAME is not found, an error is produced.

Without QNAME in SCALAR context, there may only be one such name
defined otherwise an error is produced.  In LIST context, all definitions
in CLASS are returned.
=cut

sub find($;$)
{   my ($self, $class, $name) = @_;
    my $group = $self->index($class)
        or error __x"no definitions for `{class}' found", class => $class;

    if(defined $name)
    {   return $group->{$name} if exists $group->{$name};
        error __x"no definition for `{name}' as {class}, pick from:{groups}"
            , name => $name, class => $class
            , groups => join("\n    ", '', sort keys %$group);
    }

    return values %$group
        if wantarray;

    return (values %$group)[0]
        if keys %$group==1;

    error __x"explicit selection required: pick one {class} from {groups}"
        , class => $class, groups => join("\n    ", '', sort keys %$group);
}

=method operations OPTIONS
Return a list with all operations defined in the WSDL.

=option  produce   'OBJECTS'|'HASHES'
=default produce   'HASHES'
By default, this function will return a list of HASHes, each representing
one defined operation.  When this option is set, those HASHes are
immediately used to create M<XML::Compile::WSDL11::Operation> objects
per operation.
=cut

sub operations(@)
{   my ($self, %args) = @_;
    my @ops;
    my $produce = delete $args{produce} || 'HASHES';

  SERVICE:
    foreach my $service ($self->find('service'))
    {
      PORT:
        foreach my $port (@{$service->{port} || []})
        {
            my $bindname = $port->{binding}
                or error __x"no binding defined in port '{name}'"
                      , name => $port->{name};
            my $binding  = $self->find(binding => $bindname);

            my $type     = $binding->{type}
                or error __x"no type defined with binding `{name}'"
                    , name => $bindname;
            my $portType = $self->find(portType => $type);
            my $types    = $portType->{operation}
                or error __x"no operations defined for portType `{name}'"
                     , name => $type;

            if($produce ne 'OBJECTS')
            {   foreach my $operation (@$types)
                {   push @ops
                      , { service   => $service->{name}
                        , port      => $port->{name}
                        , portType  => $portType->{name}
                        , binding   => $bindname
                        , operation => $operation->{name}
                        };
                }
                next PORT;
            }
 
            foreach my $operation (@$types)
            {   my @bindops = @{$binding->{operation} || []};
                my $op_name = $operation->{name};
                my $bind_op = first {$_->{name} eq $op_name} @bindops;

                push @ops, XML::Compile::WSDL11::Operation->new
                  ( name      => $operation->{name}
                  , service   => $service
                  , port      => $port
                  , portType  => $portType
                  , binding   => $binding
                  , wsdl      => $self
                  , port_op   => $operation
                  , bind_op   => $bind_op
                  );
            }
        }
    }

    @ops;
}

#--------------------------------

=chapter DETAILS

=section Initializing SOAP operations via WSDL

When you have a WSDL file, then SOAP is simple.  If there is no such file
at hand, then it is still possible to use SOAP.  See the DETAILS chapter
in M<XML::Compile::SOAP>.

The WSDL file contains operations, which can be addressed by name.
In this WSDL file, you need to find the name of the port to be used.
In most cases, the WSDL has only one service, one port, one binding,
and one portType and those names can therefore be omitted.  If there is
a choice, then you are required to select one explicitly.

 use XML::Compile::WSDL11 ();

 # once in your program
 my $wsdl   = XML::Compile::WSDL11->new('def.wsdl');

 # XML::Compile::Schema does not want to follow "include" and
 # "import" commands, so you need to invoke them explicitly.
 # $wsdl->addWSDL('file2.wsdl');            # optional
 # $wsdl->importDefinitions('schema1.xsd'); # optional

 # once for each of the defined operations
 my $call   = $wsdl->compileClient('GetStockPrice');

 # see XML::Compile::SOAP chapter DETAILS about call params
 my $answer = $call->(%request);

=cut


1;
