use warnings;
use strict;

package XML::Compile::Operation;

use Log::Report 'xml-report-soap', syntax => 'SHORT';
use List::Util  'first';

use XML::Compile::Util       qw/pack_type unpack_type/;
use XML::Compile::SOAP::Util qw/:wsdl11/;

=chapter NAME

XML::Compile::Operation - base-class for possible interactions

=chapter SYNOPSIS
 # created by XML::Compile::WSDL11
 my $op = $wsdl->operation('GetStockPrices');

=chapter DESCRIPTION
These objects are created by M<XML::Compile::WSDL11>, grouping information
about a certain specific message interchange between a client and
a server.

=chapter METHODS

=section Constructors

=c_method new OPTIONS
=requires name

=requires kind
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
Some string which is refering to the action which is taken.  For SOAP
protocols, this defines the soapAction header.

=requires schemas XML::Compile::Cache
=cut

sub new(@) { my $class = shift; (bless {}, $class)->init( {@_} ) }

sub init($)
{   my ($self, $args) = @_;
    $self->{kind}     = $args->{kind} or die;
    $self->{name}     = $args->{name} or die;
    $self->{schemas}  = $args->{schemas} or die;

    $self->{transport} = $args->{transport};
    $self->{action}   = $args->{action};

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

=section Accessors
=method kind
=method name
=method schemas
=method action
=method version
=method serviceName
=method bindingName
=method portName
=cut

sub schemas()   {shift->{schemas}}
sub kind()      {shift->{kind}}
sub name()      {shift->{name}}
sub action()    {shift->{action}}
sub style()     {shift->{style}}
sub transport() {shift->{transport}}
sub version()   {panic}

sub bindingName() {shift->{bindname}}
sub serviceName() {shift->{servname}}
sub portName()    {shift->{portname}}
sub portTypeName(){shift->{porttypename}}

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

#-------------------------------------------

=section Handlers

=method compileTransporter OPTIONS

Create the transporter code for a certain specific target.

=option  transporter CODE
=default transporter <created>
The routine which will be used to exchange the data with the server.
This code is created by an M<XML::Compile::Transport::compileClient()>
extension. By default, a transporter compatible to the protocol
is created.  However, in most cases you want to reuse one (HTTP1.1)
connection to a server.

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

    my $send      = delete $args{transporter} || delete $args{transport};
    return $send if $send;

    my $proto     = $self->transport;
    my $endpoints = $args{endpoint} || [];
    my @endpoints = ref $endpoints eq 'ARRAY' ? @$endpoints : ();
    unless(@endpoints)
    {   @endpoints = $self->endPoints;
        if(my $s = $args{server})
        {   s#^(\w+)://([^/]+)#$1://$s# for @endpoints;
        }
    }

    my $id        = join ';', sort @endpoints;
    $send         = $self->{transp_cache}{$proto}{$id};
    return $send if $send;

    my $transp    = XML::Compile::Transport->plugin($proto)
        or error __x"transporter type {proto} not supported (not loaded?)"
             , proto => $proto;

    my $transport = $self->{transp_cache}{$proto}{$id}
                  = $transp->new(address => \@endpoints);

    $transport->compileClient
      ( name     => $self->name
      , kind     => $self->kind
      , action   => $self->action
      , hook     => $args{transport_hook}
      , %args
      );
}

=method compileClient OPTIONS
Returns one CODE reference which handles the conversion from a perl
data-structure into a request message, the transmission of the
request, the receipt of the answer, and the decoding of that answer
into a Perl data-structure.

=method compileHandler OPTIONS
Returns a code reference which translates in incoming XML message
into Perl a data-structure, then calls the callback.  The result of
the callback is encoded from Perl into XML and returned.

=requires callback CODE
=cut

sub compileClient(@)  { panic "not implemented" }
sub compileHandler(@) { panic "not implemented" }

=section Helpers

=c_method register URI, ENVNS
Declare an operation type, but WSDL specific URI and envelope namespace.
=cut

{   my (%registered, %envelope);
    sub register($)
    { my ($class, $uri, $env) = @_;
      $registered{$uri} = $class;
      $envelope{$env}   = $class;
    }
    sub plugin($)       { $registered{$_[1]} }
    sub fromEnvelope($) { $envelope{$_[1]} }
    sub registered($)   { values %registered }
}

1;
