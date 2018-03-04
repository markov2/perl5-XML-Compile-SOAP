# This code is part of distribution XML-Compile-SOAP.  Meta-POD processed
# with OODoc into POD and HTML manual-pages.  See README.md
# Copyright Mark Overmeer.  Licensed under the same terms as Perl itself.

package XML::Compile::SOAP::Operation;

use warnings;
use strict;

use Log::Report    'xml-report-soap';

use XML::Compile::Util       qw/pack_type unpack_type/;
use XML::Compile::SOAP::Util qw/:wsdl11/;

use File::Spec     ();
use List::Util     qw(first);
use File::Basename qw(dirname);

my %servers =
  ( 'XML::Compile::Daemon' =>  # my own server implementation
      { xsddir => 'xcdaemon'
      , xsds   => [ qw(xcdaemon.xsd) ]
      }
    # more in XML::Compile::Licensed
  );

=chapter NAME

XML::Compile::SOAP::Operation - base-class for possible interactions

=chapter SYNOPSIS
 # created by XML::Compile::WSDL11
 my $op = $wsdl->operation('GetStockPrices');

=chapter DESCRIPTION
These objects are created by M<XML::Compile::WSDL11>, grouping information
about a certain specific message interchange between a client and
a server.

=chapter METHODS

=section Constructors

=c_method new %options
=requires name STRING

=requires kind 'one-way'|...
This returns the type of operation this is.  There are four kinds, which
are returned as strings C<one-way>, C<request-response>, C<sollicit-response>,
and C<notification>.  The latter two are initiated by a server, the former
two by a client.

=option   transport URI|'HTTP'
=default  transport 'HTTP'
C<HTTP> is short for C<http://schemas.xmlsoap.org/soap/http/>, which
is a constant to indicate that transport should use the HyperText
Transfer Protocol.

=option   endpoints ADDRESS|ARRAY
=default  endpoints []
Where to contact the server.

=option   action STRING
=default  action undef
Some string which is referring to the action which is taken.  For SOAP
protocols, this defines the soapAction header.

=requires schemas XML::Compile::Cache

=option  server_type NAME
=default server_type C<undef>
Most server implementations show some problems.  Also, servers may produce
responses using their own namespaces (like for error codes).  When you know
which server you are talking to, the quirks of the specific server type can
be loaded.  Read more in the L<XML::Compile::SOAP/"Supported servers">.

=cut

sub new(@) { my $class = shift; (bless {}, $class)->init( {@_} ) }

sub init($)
{   my ($self, $args) = @_;
    $self->{kind} = $args->{kind} or panic;
    $self->{name} = $args->{name} or panic;
    $self->{schemas} = $args->{schemas} or panic;
    $self->_server_type($args->{server_type});

    $self->{transport} = $args->{transport};
    $self->{action}    = $args->{action};

    my $ep = $args->{endpoints} || [];
    my @ep = ref $ep eq 'ARRAY' ? @$ep : $ep;
    $self->{endpoints} = \@ep;

    # undocumented, because not for end-user
    if(my $binding = $args->{binding})  { $self->{bindname} = $binding->{name} }
    if(my $service = $args->{service})  { $self->{servname} = $service->{name} }
    if(my $port    = $args->{serv_port}){ $self->{portname} = $port->{name} }
    if(my $port_type= $args->{portType}){ $self->{porttypename} = $port_type->{name} }

    $self;
}

sub registered
{   # This cannot be resolved via dependencies, because that causes
    # a dependency cycle which CPAN.pm cannot handle.  This method was
    # always called in <3.00 and moved to ::SOAP in >= 3.00
    error "You need to upgrade XML::Compile::WSDL11 to at least 3.00";
}

sub _server_type($)
{   my ($self, $type) = @_;
    $type or return;

    my $schemas = $self->schemas;
    return if $schemas->{"did_init_server_$type"}++;

    my ($def, $xsddir);
    if($def = $servers{$type})
    {   $xsddir = File::Spec->catdir(dirname(__FILE__), 'xsd', $def->{xsddir});
    }
    else
    {   eval "require XML::Compile::Licensed";
        if($@)
        {   error __x"soap server type `{type}' is not supported (yet); installing XML::Compile::Licensed may help"
             , type => $type;
        }
        ($xsddir, $def) = XML::Compile::Licensed->soapServer($type)
            or error __x"soap server type `{type}' is not supported (yet)"
             , type => $type;
    }

    $schemas->importDefinitions(File::Spec->catfile($xsddir, $_))
        for @{$def->{xsds}};
}

#----------------
=section Accessors
=method kind 
=method name 
=method schemas 
=method version 
=method serviceName 
=method bindingName 
=method portName 
=cut

sub schemas()   {shift->{schemas}}
sub kind()      {shift->{kind}}
sub name()      {shift->{name}}
sub style()     {shift->{style}}
sub transport() {shift->{transport}}
sub version()   {panic}

sub bindingName() {shift->{bindname}}
sub serviceName() {shift->{servname}}
sub portName()    {shift->{portname}}
sub portTypeName(){shift->{porttypename}}

=method soapAction 
Used for the C<soapAction> header in HTTP transport, for routing
messages through firewalls.
=cut

sub soapAction  {shift->{action}}
sub action()    {shift->{action}} # deprecated

=method wsaAction 'INPUT'|'OUTPUT'
Only available when C<XML::Compile::SOAP::WSA> is loaded. It specifies
the name of the operation in the WSA header.  With C<INPUT>, it is the
Action to be used with a message sent to the server (input to the
server). The C<OUTPUT> is used by the server in its message back.
=cut
# wsaAction is implement in XML::Compile::SOAP::WSA

=method serverClass 
Returns the class name which implements the Server side for this protocol.

=method clientClass 
Returns the class name which implements the Client side for this protocol.
=cut

sub serverClass {panic}
sub clientClass {panic}

=method endPoints 
Returns the list of alternative URLs for the end-point, which should
be defined within the service's port declaration.
=cut

sub endPoints() { @{shift->{endpoints}} }

=method longName
[3.06] prefix the service name before the operation name, to make it
really unique.  A C<#> is used as separator.
=cut

sub longName()
{   my $self = shift;
    ($self->serviceName // '') . '#' . $self->name;
}

#-------------------------------------------

=section Handlers

=method compileTransporter %options

Create the transporter code for a certain specific target.

=option  transporter CODE|XML::Compile::Transport-object
=default transporter <created>
The routine which will be used to exchange the data with the server.
This code is created by an M<XML::Compile::Transport::compileClient()>
extension.

By default, a transporter compatible to the protocol is created.  However,
in most cases you want to reuse one (HTTP1.1) connection to a server.

[3.14] You may provide a M<XML::Compile::Transport> object as well.  Its
compileClient() will be called for you.

=option  transport_hook CODE
=default transport_hook C<undef>
Passed to M<XML::Compile::Transport::compileClient(hook)>.  Can be
used to create off-line tests and last resort work-arounds.  See the
DETAILs chapter in the M<XML::Compile::Transport> manual page.

=option  endpoint URI|ARRAY-of-URI
=default endpoint <from WSDL>
Overrule the destination address(es).

=option  server URI-HOST
=default server undef
Overrule only the server part in the endpoint, not the whole endpoint.
This could be a string like C<username:password@myhost:4711>.  Only
used when no explicit C<endpoint> is provided.
=cut

sub compileTransporter(@)
{   my ($self, %args) = @_;

    my $transp    = delete $args{transporter} || delete $args{transport};
    return $transp if ref $transp eq 'CODE';

    my $proto     = $self->transport;
    my @endpoints;
    if(my $endpoints = $args{endpoint})
    {   @endpoints = ref $endpoints eq 'ARRAY' ? @$endpoints : $endpoints;
    }
    unless(@endpoints)
    {   @endpoints = $self->endPoints;
        if(my $s = $args{server})
        {   s#^(\w+)://([^/]+)#$1://$s# for @endpoints;
        }
    }

    my $id        = join ';', sort @endpoints;
    my $send      = $self->{transp_cache}{$proto}{$id};
    return $send if $send;

    unless($transp)
    {   my $type = XML::Compile::Transport->plugin($proto)
         or error __x"transporter type {proto} not supported (add 'use {pkg}'?)"
             , proto => $proto, pkg => 'XML::Compile::Transport::SOAPHTTP';
        $transp  = $type->new(address => \@endpoints, %args);
    }

    my $transport = $self->{transp_cache}{$proto}{$id} = $transp;

    $transport->compileClient
      ( name     => $self->name
      , kind     => $self->kind
      , action   => $self->action
      , hook     => $args{transport_hook}
      , %args
      );
}

=method compileClient %options
Returns one CODE reference which handles the conversion from a perl
data-structure into a request message, the transmission of the
request, the receipt of the answer, and the decoding of that answer
into a Perl data-structure.

=method compileHandler %options
Returns a code reference which translates in incoming XML message
into Perl a data-structure, then calls the callback.  The result of
the callback is encoded from Perl into XML and returned.

=requires callback CODE
=cut

sub compileClient(@)  { panic "not implemented" }
sub compileHandler(@) { panic "not implemented" }

#---------------
=section Helpers

=method explain $wsdl, $format, $direction, %options
Dump an annotated structure showing how the operation works, helping
developers to understand the schema. $format is C<PERL> or C<XML>.

The $direction is C<INPUT>, it will return the message which the client
sends to the server (input for the server). The C<OUTPUT> message is
sent as response by the server.
=cut

sub explain($$$@)
{   my ($self, $wsdl, $format, $dir, %args) = @_;
    panic "not implemented for ".ref $self;
}

=method parsedWSDL %options
[2.29] For some purposes, it is useful to get access to the parsed WSDL
structure.

B<Be aware> that the structure returned is consided "internal"
and strongly influenced by behavior of M<XML::Compile>; backwards
compatibility will not be maintained at all cost.

You can use M<XML::Compile::Schema::template()> format C<TREE> to get
more details about the element types mentioned in this structure.

=example
  use Data::Dumper;
  $Data::Dumper::Indent    = 1;
  $Data::Dumper::Quotekeys = 0;

  print Dumper $op->parsedWSDL;
=cut

sub parsedWSDL(%)
{   my $self = shift;
    panic "not implemented for ".ref $self;
}

1;
