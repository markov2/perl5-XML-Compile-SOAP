use warnings;
use strict;

package XML::Compile::WSDL11;
use base 'XML::Compile::Cache';

use Log::Report 'xml-compile-soap', syntax => 'SHORT';

use XML::Compile             ();      
use XML::Compile::Util       qw/pack_type unpack_type/;
use XML::Compile::SOAP::Util qw/:wsdl11/;
use XML::Compile::SOAP::Extension;

use XML::Compile::SOAP::Operation  ();
use XML::Compile::Transport  ();

use List::Util               qw/first/;

XML::Compile->addSchemaDirs(__FILE__);
XML::Compile->knownNamespace(&WSDL11 => 'wsdl.xsd');

=chapter NAME

XML::Compile::WSDL11 - create SOAP messages defined by WSDL 1.1

=chapter SYNOPSIS

 # preparation
 use XML::Compile::WSDL11;      # use WSDL version 1.1
 use XML::Compile::SOAP11;      # use SOAP version 1.1
 use XML::Compile::Transport::SOAPHTTP;

 my $wsdl = XML::Compile::WSDL11->new($wsdlfile);
 $wsdl->addWSDL(...more WSDL files...);
 $wsdl->importDefinitions(...more schemas...);

 # during initiation, for each used call (slow)
 my $call = $wsdl->compileClient('GetStockPrice', ...);

 # at "run-time", call as often as you want (fast)
 my $answer = $call->(%request);

 # capture useful trace information
 my ($answer, $trace) = $call->(%request);

 # investigate the %request structure (server input)
 print $wsdl->explain('GetStockPrice', PERL => 'INPUT');

 # investigate the $answer structure (server output)
 print $wsdl->explain('GetStockPrice', PERL => 'OUTPUT');

 # when you like, get all operation definitions
 my @all_ops = $wsdl->operations;

 # Install XML::Compile::SOAP::Daemon
 my $server  = XML::Compile::SOAP::HTTPDaemon->new;
 $server->operationsFromWSDL($wsdl);
 undef $wsdl;    # not needed any further
 
 # For debug info, start your script with:
 use Log::Report mode => 'DEBUG';

=chapter DESCRIPTION

This module implements WSDL version 1.1.
An WSDL file defines a set of messages to be send and received over
(SOAP) connections.

As end-user, you do not have to worry about the complex details of the
messages and the way to exchange of them: it's all simple Perl for you.
Also faults are handled automatically.  The only complication you have
to worry about, is to shape a nested HASH structure to the sending
message structure.  M<XML::Compile::Schema::template()> may help you.

When the definitions are spread over multiple files, you will need to
use M<addWSDL()> (wsdl), or M<importDefinitions()> (additional schema's)
explicitly, because M<XML::Compile::Schema> does not wish dynamic internet
download magic to happen.

=chapter METHODS

=section Constructors

=c_method new XML, OPTIONS
The XML is the WSDL file, which is anything accepted by
M<XML::Compile::dataToXML()>.
=cut

sub init($)
{   my ($self, $args) = @_;
    $args->{schemas} and panic "new(schemas) option removed in 0.78";
    my $wsdl = delete $args->{top};

    local $args->{any_element}      = 'ATTEMPT';
    local $args->{any_attribute}    = 'ATTEMPT'; # not implemented
    local $args->{allow_undeclared} = 1;

    $self->SUPER::init($args);

    $self->{index}   = {};

    $self->prefixes(wsdl => WSDL11, soap => WSDL11SOAP, http => WSDL11HTTP);

    # next module should change into an extension as well...
    $_->can('_initWSDL11') && $_->_initWSDL11($self)
        for XML::Compile::SOAP::Operation->registered;

    XML::Compile::SOAP::Extension->wsdl11Init($self, $args);

    $self->declare
      ( READER      => 'wsdl:definitions'
      , key_rewrite => 'PREFIXED(wsdl,soap,http)'
      , hook        => {type => 'wsdl:tOperation', after => 'ELEMENT_ORDER'}
      );

    $self->importDefinitions(WSDL11);
    $self->addWSDL($wsdl);
    $self;
}

sub schemas(@) { panic "schemas() removed in v2.00, not needed anymore" }

#--------------------------

=section Accessors

=section Extension

=method addWSDL XMLDATA
Some XMLDATA, accepted by M<XML::Compile::dataToXML()> is provided,
which should represent the top-level of a (partial) WSDL document.
The specification can be spread over multiple files, which each have a
C<definition> root element.
=cut

sub _learn_prefixes($)
{   my ($self, $node) = @_;

    my $namespaces = $self->prefixes;
  PREFIX:
    foreach my $ns ($node->getNamespaces)  # learn preferred ns
    {   my ($prefix, $uri) = ($ns->getLocalName, $ns->getData);
        next if !defined $prefix || $namespaces->{$uri};

        if(my $def = $self->prefix($prefix))
        {   next PREFIX if $def->{uri} eq $uri;
        }
        else
        {   $self->prefixes($prefix => $uri);
            next PREFIX;
        }

        $prefix =~ s/0?$/0/;
        while(my $def = $self->prefix($prefix))
        {   next PREFIX if $def->{uri} eq $uri;
            $prefix++;
        }
        $self->prefixes($prefix => $uri);
    }
}

sub addWSDL($)
{   my ($self, $data) = @_;
    defined $data or return ();

    defined $data or return;
    my ($node, %details) = $self->dataToXML($data);
    defined $node or return $self;

    $node->localName eq 'definitions' && $node->namespaceURI eq WSDL11
        or error __x"root element for WSDL is not 'wsdl:definitions'";

    $self->importDefinitions($node, details => \%details);
    $self->_learn_prefixes($node);

    my $spec = $self->reader('wsdl:definitions')->($node);
    my $tns  = $spec->{targetNamespace}
        or error __x"WSDL sets no targetNamespace";

    # WSDL 1.1 par 2.1.1 says: WSDL def types each in own name-space
    my $index     = $self->{index};

    # silly WSDL structure
    my $toplevels = $spec->{gr_wsdl_anyTopLevelOptionalElement} || [];

    foreach my $toplevel (@$toplevels)
    {   my ($which, $def) = %$toplevel;        # always only one
        $which =~ s/^wsdl_(service|message|binding|portType)$/$1/
            or next;

        $index->{$which}{pack_type $tns, $def->{name}} = $def;

        if($which eq 'service')
        {   foreach my $port ( @{$def->{port} || []} )
            {   $index->{port}{pack_type $tns, $port->{name}} = $port;
            }
        }
    }

    # no service block when only one port
    unless($index->{service})
    {   # only from this WSDL, cannot use collective $index
        my @portTypes = map { $_->{wsdl_portType} || () } @$toplevels;
        @portTypes==1
            or error __x"no service definition so needs 1 portType, found {nr}"
                 , nr => scalar @portTypes;

        my @bindings = map { $_->{wsdl_binding} || () } @$toplevels;
        @bindings==1
            or error __x"no service definition so needs 1 binding, found {nr}"
                 , nr => scalar @bindings;

        my $binding  = pack_type $tns, $bindings[0]->{name};
        my $portname = $portTypes[0]->{name};
        my $servname = $portname;
        $servname =~ s/Service$|(?:Service)?Port(?:Type)?$/Service/i
             or $servname .= 'Service';

        my %port = (name => $portname, binding => $binding
           , soap_address => {location => 'http://localhost'} );

        $index->{service}{pack_type $tns, $servname}
            = { name => $servname, wsdl_port => [ \%port ] };
        $index->{port}{pack_type $tns, $portname} = \%port;
    }
#warn "INDEX: ",Dumper $index;
    $self;
}

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
M<XML::Compile::SOAP::Operation> object.

An operation is defined by a service name, a port, some bindings,
and an operation name, which can be specified explicitly and often
left-out (in any situation where there are no alternative choices).

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

=option action STRING
=default action <undef>
Overrule the soapAction from the WSDL.

=requires operation NAME
Ignored when the parameter list starts with a NAME (which is an
alternative for this option).  Optional when there is only
one operation defined within the portType.

=cut

# new options, then also add them to the list in compileClient()

sub operation(@)
{   my $self = shift;
    my $name = @_ % 2 ? shift : undef;
    my %args = (name => $name, @_);

    #
    ## Service structure
    #

    my $service   = $self->findDef(service => delete $args{service});

    my $port;
    my @ports     = @{$service->{wsdl_port} || []};
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

    # get plugin for operation # {
    my $address   = first { $_ =~ m/address$/ } keys %$port
        or error __x"no address provided in service port {port}"
           , port => $port->{name};

    if($address =~ m/^{/)      # }
    {   my ($ns)  = unpack_type $address;

        warning __"Since v2.00 you have to require XML::Compile::SOAP11 explicitly"
            if $ns eq WSDL11SOAP;

        error __x"ports of type {ns} not supported (not loaded?)", ns => $ns;
    }

    my ($prefix)  = $address =~ m/(\w+)_address$/;
    $prefix
        or error __x"port address not prefixed; probably need to add a plugin";

    my $opns      = $self->findName("$prefix:");
    my $opclass   = XML::Compile::SOAP::Operation->plugin($opns);
    unless($opclass)
    {   my $pkg = $opns eq WSDL11SOAP   ? 'SOAP11'
                : $opns eq WSDL11SOAP12 ? 'SOAP12'
                : $opns eq WSDL11HTTP   ? 'SOAP10'
                :                         undef;

        if($pkg)
        {   error __x"add 'use XML::Compile::{pkg}' to your script", pkg=>$pkg;
        }
        else
        {   notice __x"ignoring unsupported namespace {ns}", ns => $opns;
            return;
        }
    }

    $opclass->can('_fromWSDL11')
        or error __x"WSDL11 not supported by {class}", class => $opclass;

    #
    ## Binding
    #

    my $bindtype  = $port->{binding}
        or error __x"no binding defined in port '{name}'"
               , name => $port->{name};

    my $binding   = $self->findDef(binding => $bindtype);

    my $type      = $binding->{type}  # get portTypeType
        or error __x"no type defined with binding `{name}'"
               , name => $bindtype;

    my $portType  = $self->findDef(portType => $type);
    my $types     = $portType->{wsdl_operation}
        or error __x"no operations defined for portType `{name}'"
               , name => $type;

    my @port_ops  = map {$_->{name}} @$types;

    $name       ||= delete $args{operation};
    my $port_op;
    if(defined $name)
    {   $port_op = first {$_->{name} eq $name} @$types;
        error __x"no operation `{op}' for portType {pt}, pick from{ops}"
          , op => $name, pt => $type, ops => join("\n    ", '', @port_ops)
            unless $port_op;
    }
    elsif(@port_ops==1)
    {   $port_op = shift @$types;
        $name    = $port_op->{name};
    }
    else
    {   error __x"multiple operations in portType `{pt}', pick from {ops}"
            , pt => $type, ops => join("\n    ", '', @port_ops)
    }

    my @bindops   = @{$binding->{wsdl_operation} || []};
    my $bind_op   = first {$_->{name} eq $name} @bindops;
    $bind_op
        or error __x"cannot find bind operation for {name}", name => $name;

    # This should be detected while parsing the WSDL because the order of
    # input and output is significant (and lost), but WSDL 1.1 simplifies
    # our life by saying that only 2 out-of 4 predefined types can actually
    # be used at present.

    my @order = map { (unpack_type $_)[1] } @{$port_op->{_ELEMENT_ORDER}};

    my ($first_in, $first_out);
    for(my $i = 0; $i<@order; $i++)
    {   $first_in  = $i if !defined $first_in  && $order[$i] eq 'input';
        $first_out = $i if !defined $first_out && $order[$i] eq 'output';
    }

    my $kind
      = !defined $first_in     ? 'notification-operation'
      : !defined $first_out    ? 'one-way'
      : $first_in < $first_out ? 'request-response'
      :                          'solicit-response';

    #
    ### message components
    #

    my $operation = $opclass->_fromWSDL11
     ( name      => $name,
     , kind      => $kind

     , service   => $service
     , serv_port => $port
     , binding   => $binding
     , bind_op   => $bind_op
     , portType  => $portType
     , port_op   => $port_op

     , wsdl      => $self
     , action    => $args{action}
     );
 
    $operation;
}

=method compileClient [NAME], OPTIONS
Creates temporarily an M<XML::Compile::SOAP::Operation> object with
M<operation()>, and then calls C<compileClient()> on that; an usual
combination.

As OPTIONS are available the combination of all possibilities for
=over 4
=item .
M<operation()> (i.e. C<service> and C<port>), and all of
=item .
M<XML::Compile::SOAP::Operation::compileClient()> (a whole lot,
for instance C<transport_hook> and C<server>), plus
=back

You B<cannot> pass options for M<XML::Compile::Schema::compile()>, like
C<<sloppy_integers => 0>>, hooks or typemaps this way. Use M<new(opts_rw)>
and friends to declare those.

=example
  $wsdl->compileClient
    ( operation => 'HelloWorld'
    , port      => 'PrefillSoap' # only needed when multiple ports
    );
=cut

sub compileClient(@)
{   my $self = shift;
    unshift @_, 'operation' if @_ % 2;
    my $op   = $self->operation(@_) or return ();
    $op->compileClient(@_);
}

#---------------------

=section Introspection

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

=method findDef CLASS, [QNAME|PREFIXED|NAME]
With a QNAME, the HASH which contains the parsed XML information
from the WSDL template for that CLASS-NAME combination is returned.
You may also have a PREFIXED name, using one of the predefined namespace
abbreviations.  Otherwise, NAME is considered to be the localName in
that class.  When the NAME is not found, an error is produced.

Without QNAME in SCALAR context, there may only be one such name
defined otherwise an error is produced.  In LIST context, all definitions
in CLASS are returned.
=cut

sub findDef($;$)
{   my ($self, $class, $name) = @_;
    my $group = $self->index($class)
        or error __x"no definitions for `{class}' found", class => $class;

    if(defined $name)
    {   return $group->{$name} if exists $group->{$name};  # QNAME

        if($name =~ m/\:/)                                 # PREFIXED
        {   my $qname = $self->findName($name);
            return $group->{$qname} if exists $group->{$qname};
        }

        if(my $q = first { (unpack_type $_)[1] eq $name } keys %$group)
        {   return $group->{$q};
        }

        error __x"no definition for `{name}' as {class}, pick from:{groups}"
          , name => $name, class => $class
          , groups => join("\n    ", '', sort keys %$group);
    }

    return values %$group
        if wantarray;

    return (values %$group)[0]
        if keys %$group==1;

    my @alts = map $self->prefixed($_), sort keys %$group;
    error __x"explicit selection required: pick one {class} from {alts}"
      , class => $class, alts => join("\n    ", '', @alts);
}

=method operations OPTIONS
Return a list with all operations defined in the WSDL.

=option  service NAME
=default service <undef>
Only return operations related to the NAMEd service, by default all services.

=option  port NAME
=default port <undef>
Return only operations related to the specified port NAME.
By default operations from all ports.

=option  binding NAME
=default binding <undef>
Only return operations which use the binding with the specified NAME.
By default, all bindings are accepted.
=cut

sub operations(@)
{   my ($self, %args) = @_;
    my @ops;
    $args{produce} and die "produce option removed in 0.81";

    foreach my $service ($self->findDef('service'))
    {
        next if $args{service} && $args{service} ne $service->{name};

        foreach my $port (@{$service->{wsdl_port} || []})
        {
            next if $args{port} && $args{port} ne $port->{name};

            my $bindtype = $port->{binding}
                or error __x"no binding defined in port '{name}'"
                      , name => $port->{name};
            my $binding  = $self->findDef(binding => $bindtype);

            next if $args{binding} && $args{binding} ne $binding->{name};

            my $type     = $binding->{type}
                or error __x"no type defined with binding `{name}'"
                    , name => $bindtype;

            foreach my $operation ( @{$binding->{wsdl_operation}||[]} )
            {   push @ops, $self->operation
                  ( service   => $service->{name}
                  , port      => $port->{name}
                  , binding   => $bindtype
                  , operation => $operation->{name}
                  , portType  => $type
                  );
            }
        }
    }

    @ops;
}

=method printIndex [FILEHANDLE], OPTIONS
For available OPTIONS, see M<operations()>.  This method is useful to
understand the structure of your WSDL: it shows a nested list of
services, bindings, ports and portTypes.
=cut

sub printIndex(@)
{   my $self = shift;
    my $fh   = @_ % 2 ? shift : select;
    my @args = @_;

    my %tree;
    $tree{'service '.$_->serviceName}
         {$_->version.' port '.$_->portName . ' (binding '.$_->bindingName.')'}
         {$_->name} = $_
         for $self->operations(@args);

    foreach my $service (sort keys %tree)
    {   $fh->print("$service\n");
        foreach my $port (sort keys %{$tree{$service}})
        {   $fh->print("    $port\n");
            foreach my $op (sort keys %{$tree{$service}{$port}})
            {   $fh->print("        $op\n");
            }
        }
    }
}

=method explain OPERATION, FORMAT, DIRECTION, OPTIONS
[2.13]
Produce templates (see M<XML::Compile::Schema::template()> which detail
the use of the OPERATION. Currently, only the C<PERL> template FORMAT
is available.

The DIRECTION of operation is either C<INPUT> (input for the server,
hence to be produced by the client), or C<OUTPUT> (from the server,
received by the client).

The actual work is done by M<XML::Compile::SOAP::Operation::explain()>. The
OPTIONS are passed to that method, as there are C<recurse> and
C<skip_header>.

=example
  print $wsdl->explain('CheckStatus', PERL => 'INPUT');
=cut

sub explain($$$@)
{   my ($self, $opname, $format, $direction, @opts) = @_;
    my $op = $self->operation($opname, @opts)
        or error __x"explain operation {name} not found", name => $opname;
    $op->explain($self, $format, $direction, @opts);
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
