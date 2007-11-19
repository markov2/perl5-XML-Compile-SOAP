use warnings;
use strict;

package XML::Compile::WSDL11::Operation;

use Log::Report 'xml-report-soap', syntax => 'SHORT';
use List::Util  'first';

use Data::Dumper;  # needs to go away
use XML::Compile::Util       qw/pack_type unpack_type/;
use XML::Compile::SOAP::Util qw/:wsdl11 SOAP11HTTP/;

=chapter NAME

XML::Compile::WSDL11::Operation - defines a possible SOAP interaction

=chapter SYNOPSIS
 # created by XML::Compile::WSDL11

=chapter DESCRIPTION
These objects are created by M<XML::Compile::WSDL11>, grouping information
about a certain specific message interchange between a client and
a server. You can better (try to) create a WSDL file itself, then
attempt to instantiate these objects yourself... or even better: use
M<XML::Compile::SOAP11> directly, and forget WSDL complexity.

There are three styles of SOAP: Document-style, RPC-literal and
RPC-encoded.  The first can be used directly, for the SOAP-RPC will
require you to specify more information about the expected message types.

=chapter METHODS

=section Constructors

=method new OPTIONS
The OPTIONS are all collected from the WSDL description by
M<XML::Compile::WSDL::operation()>.  End-users should not attempt to
initiate this object directly.

=requires name     STRING
=requires service  HASH
=requires port     HASH
=requires binding  HASH
=requires portType HASH
=requires wsdl     XML::Compile::WSDL11 object
=requires port_op  HASH

=option   bind_op  HASH
=default  bind_op  C<undef>

=option   protocol URI|'HTTP'
=default  protocol 'HTTP'
C<HTTP> is short for C<http://schemas.xmlsoap.org/soap/http/>, which
is a constant to indicate that transport should use the HyperText
Transfer Protocol.

=option   style 'document'|'rpc'
=default  style <from wsdl operation style> | 'document'

=option   action URI
=default  action <from wsdl>

=cut

sub new(@)
{   my $class = shift;
    (bless {@_}, $class)->init;
}

sub init()
{   my $self = shift;
    my $name = $self->name;

    # autodetect namespaces used
    my $port = $self->port;
    my ($soapns, $version) = ($self->{soap_ns}, $self->{version})
      = exists $port->{pack_type WSDL11SOAP,  'address'}
      ? (WSDL11SOAP,   'SOAP11')
      : exists $port->{pack_type WSDL11SOAP12,'address'}
      ? (WSDL11SOAP12, 'SOAP12')
      : error __x"no supported namespace found for {operation}"
           , operation => $name;

    $self->schemas->importDefinitions($soapns);

    # This should be detected while parsing the WSDL because the order of
    # input and output is significant (and lost), but WSDL 1.1 simplifies
    # our life by saying that only 2 out-of 4 predefined types can actually
    # be used at present.
    my @order    = @{$self->portOperation->{_ELEMENT_ORDER}};
    my ($first_in, $first_out);
    for(my $i = 0; $i<@order; $i++)
    {   $first_in  = $i if !defined $first_in  && $order[$i] eq 'input';
        $first_out = $i if !defined $first_out && $order[$i] eq 'output';
    }

    $self->{kind}
      = !defined $first_in     ? 'notification-operation'
      : !defined $first_out    ? 'one-way'
      : $first_in < $first_out ? 'request-response'
      :                          'solicit-response';

    $self->{protocol}  ||= 'HTTP';
    $self;
}

=section Accessors
=method name
=method service
=method port
=method bindings
=method portType
=method portOperation
=method bindOperation
=method wsdl
=method schemas
=cut

sub name()     {shift->{name}}
sub service()  {shift->{service}}
sub port()     {shift->{port}}
sub binding()  {shift->{binding}}
sub portType() {shift->{portType}}
sub wsdl()     {shift->{wsdl}}
sub schemas()  {shift->{wsdl}->schemas}

sub portOperation() {shift->{port_op}}
sub bindOperation() {shift->{bind_op}}

=section Use

=method soapNameSpace
=method soapVersion
=cut

sub soapNameSpace() {shift->{soap_ns}}
sub soapVersion()   {shift->{version}}

=method endPointAddresses
Returns the list of alternative URLs for the end-point, which should
be defined within the service's port declaration.
=cut

sub endPointAddresses()
{   my $self = shift;
    return @{$self->{addrs}} if $self->{addrs};

    my $soapns   = $self->soapNameSpace;
    my $addrtype = pack_type $soapns, 'address';

    my $addrxml  = $self->port->{$addrtype}
        or error __x"soap end-point address not found in service port";

    my $addr_r   = $self->schemas->compile(READER => $addrtype);

    my @addrs    = map {$addr_r->($_)->{location}} @$addrxml;
    $self->{addrs} = \@addrs;
    @addrs;
}

=method soapAction
=cut

sub soapAction()
{   my $self = shift;
    return $self->{action}
        if exists $self->{action};

    my $optype = pack_type $self->soapNameSpace, 'operation';
    my $opdata = {};
    if(my $opxml = $self->bindOperation->{$optype})
    {   my $op_r = $self->schemas->compile(READER => $optype);
        my $binding
         = @$opxml > 1
         ? (first {$_->{style} eq $self->soapStyle} @$opxml)
         : $opxml->[0];

        $opdata = $op_r->($binding);
    }
    $self->{action} = $opdata->{soapAction};
}

sub soapStyle() { shift->{style} }

=method kind
This returns the type of operation this is.  There are four kinds, which
are returned as strings C<one-way>, C<request-response>, C<sollicit-response>,
and C<notification>.  The latter two are initiated by a server, the former
two by a client.
=cut

sub kind() {shift->{kind}}

=section Handlers

=method compileClient OPTIONS
Returns one CODE reference which handles the processing for this
operation.

You pass that CODE reference an input message of the correct
type, as pure Perl HASH structure.  An 'request-response' operation
will return then answer, or C<undef> in case of failure.  An 'one-way'
operation with return C<undef> in case of failure, and a true value
when successfull.

=option  style    'document'|'rpc'
=default style    new(style)|'document'

=option  protocol URI|'HTTP'
=default protocol new(protocol)|<from soapAction>
Only the HTTP protocol is supported on the moment.  The URI is
the WSDL URI representation of the HTTP protocol.

=option  transporter XML::Compile::Transport object
=default transporter <created>
Usually an M<XML::Compile::Transport::SOAPHTTP> object, which is
used to exchange the data with the server.  By default, a transporter
compatible to the protocol is created.  However, in most cases you
want to reuse one (HTTP1.1) connection to a server.

=option  transport_hook CODE
=default transport_hook C<undef>
Passed to M<XML::Compile::Transport::compileClient(hook)>.  Can be
used to create off-line tests and last resort work-arounds.  See the
DETAILs chapter in the M<XML::Compile::Transport> manual page.

=option  rpcout TYPE|CODE
=default rpcout C<undef>
Pack user values into an outgoing SOAP-RPC structure.
See M<XML::Compile::SOAP::compileClient(rpcout)>.

=option  rpcin TYPE|CODE
=default rpcin C<undef>
Decode some received (incoming) SOAP-RPC structure into Perl data structures.
See M<XML::Compile::SOAP::compileClient(rpcin)>.
=cut

sub compileClient(@)
{   my ($self, %args) = @_;

    #
    # which SOAP version to use
    #

    my $soapns = $self->soapNameSpace;
    my ($soap, $version);
    if($soapns eq WSDL11SOAP)
    {   require XML::Compile::SOAP11::Client;
        $soap    = XML::Compile::SOAP11::Client->new(schemas => $self->schemas);
        $version = 'SOAP11';
    }
    elsif($soapns eq WSDL11SOAP12)
    {   require XML::Compile::SOAP12::Client;
        $soap    = XML::Compile::SOAP12::Client->new(schemas => $self->schemas);
        $version = 'SOAP12';
    }
    else { panic "NameSpace $soapns not supported for WSDL11 operation" }

    #
    ### select the right binding
    #

    my $proto  = $args{protocol}  || $self->{protocol}
              || ($self->soapAction =~ m/^(\w+)\:/ ? uc($1) : 'HTTP');
    $proto     = SOAP11HTTP if $proto eq 'HTTP';

    my $style  = $args{style} || $self->soapStyle;
    if(defined $style)
    {   $self->canTransport($proto, $style)
            or error __x"transport {protocol} as {style} not defined in WSDL"
                  , protocol => $proto, style => $style;
    }
    elsif($self->canTransport($proto, 'document')) { $style = 'document' }
    elsif($self->canTransport($proto, 'rpc'))      { $style = 'rpc' }
    else
    {   error __x"transport {protocol} style not detected in WSDL"
          , protocol => $proto;
    }
    $self->{style} = $style;

    #
    ### prepare message processing
    #

    my ($encode, $decode) = $self->compileMessages(\%args, 'CLIENT', $soap);

    #
    ### prepare the transport
    #

    $proto eq SOAP11HTTP
       or error __x"SORRY: only transport of HTTP implemented, not {protocol}"
               , protocol => $proto;

    my $transport = $args{transport};
    unless($transport)
    {   my $impl = 'XML::Compile::Transport::SOAPHTTP';

        # this is an optimization thing: often, the client and server will
        # be forking daemons: you do not want to load the module in each
        # child.  The users will immediately avoid this error.
        $impl->can('new')
            or error __x"explicitly put 'use {impl}' in your script"
                  , impl => $impl;

        $transport = $impl->new
          ( address  => [ $self->endPointAddresses ]
          );
    }

    my $send = $transport->compileClient
      ( name         => $self->name
      , kind         => $self->kind
      , soap_version => $version
      , action       => $self->soapAction
      , hook         => $args{transport_hook}
      );

    $soap->compileClient
      ( name         => $self->name
      , kind         => $self->kind
      , encode       => $encode
      , decode       => $decode
      , transport    => $send
      , rpcout       => $args{rpcout}
      , rpcin        => $args{rpcin}
      );
}

=method prepareServer OPTIONS
Prepare the routines which will decode the request and encode the answer,
as will be run on the server.  The M<XML::Compile::SOAP::Server> will
connect these.

Returned is a LIST of three: the soapAction string, the request decoder
CODE reference, and the answer encoder CODE reference.

=requires soap XML::Compile::SOAP object
=cut

sub prepareServer(@)
{   my ($self, %args) = @_;
    my ($input, $output);

    my $soap = $args{soap} or panic "no soap to prepare server";

    ($self->soapAction, $input, $output);
}

=section Helpers

=method canTransport PROTOCOL, STYLE
Returns a true value when the pair with URI of the PROTOCOL and
processing style (either C<document> (default) or C<rpc>) is
provided as soap binding.  If the style was not specified explicitly
with M<new(style)>, it will be looked-up.  The style is returned as
trueth value.
=cut

sub canTransport($$)
{   my ($self, $proto, $style) = @_;
    my $trans = $self->{trans};

    unless($trans)
    {   # collect the transport information
        my $soapns   = $self->soapNameSpace;
        my $bindtype = pack_type $soapns, 'binding';

        my $bindxml  = $self->binding->{$bindtype}
            or error __x"soap transport binding not found in binding";

        my $bind_r   = $self->schemas->compile(READER => $bindtype);
  
        my %bindings = map {$bind_r->($_)} @$bindxml;
        $_->{style} ||= 'document' for values %bindings;
        $self->{trans} = $trans = \%bindings;
    }

    my @proto    = grep {$_->{transport} eq $proto} values %$trans;
    @proto or return ();

    my $op_style = $self->soapStyle;
    return $op_style eq $style if defined $op_style; # explicit style

    first {$_->{style} eq $style} @proto;         # the default style
}

=method compileMessages ARGS, 'CLIENT'|'SERVER', SOAP
=cut

sub compileMessages($$$)
{   my ($self, $args, $role, $soap) = @_;
    my $port   = $self->portOperation;
    my $bind   = $self->bindOperation;

    my ($output_parts, $output_enc)
     = $self->collectMessageParts($args, $port->{output},$bind->{output});

    my ($input_parts,  $input_enc)
     = $self->collectMessageParts($args, $port->{input}, $bind->{input});

    my ($fault_parts,  $fault_enc)
     = $self->collectFaultParts  ($args, $port->{fault}, $bind->{fault});

    my $encodings = { %$output_enc, %$input_enc, %$fault_enc };
#warn Dumper $input_parts, $output_parts, $fault_parts, $encodings;

    my $input = $soap->compileMessage
      ( ($role eq 'CLIENT' ? 'SENDER' : 'RECEIVER')
      , %$input_parts,  %$fault_parts, encodings => $encodings
      );

    my $output = $soap->compileMessage
      ( ($role eq 'CLIENT' ? 'RECEIVER' : 'SENDER')
      , %$output_parts, %$fault_parts, encodings => $encodings
      );

    ($input, $output);
}

=method collectMessageParts ARGS, PORT-OP, BIND-OP
Collect the components of the message which are actually being used.
=cut

my ($bind_body_reader, $bind_header_reader);
sub collectMessageParts($$$)
{   my ($self, $args, $portop, $bind) = @_;
    my (%parts, %encodings);

    my $msgname  = $portop->{message}
        or error __x"no message name in portOperation";

    my $message  = $self->wsdl->find(message => $msgname)
        or error __x"cannot find message {name}", name => $msgname;
    my $soapns   = $self->soapNameSpace;

    if(my $bind_body = $bind->{"{$soapns}body"})
    {   $bind_body_reader
               ||= $self->schemas->compile(READER => "{$soapns}body");
        my $body = ($bind_body_reader->($bind_body->[0]))[1];
#       my $use  = $body->{use} || 'literal';  # default correct?

        if($self->soapStyle eq 'document')
        {   my $body_parts = $body->{parts} || [];
            $parts{body}   = $self->messageSelectParts($message, @$body_parts);
#warn Dumper $body, $body_parts, $parts{body};
        }
    }

    if(my $bind_headers = $bind->{"{$soapns}header"})
    {   $bind_header_reader
        ||= $self->schemas->compile(READER => "{$soapns}header");

        my @headers = map {$bind_header_reader->($_)} @$bind_headers;

        foreach my $header (@headers)
        {   my $use = $header->{use}
                or error __x"message {name} header requires use attribute"
                      , name => $msgname;

            my $hmsgname = $header->{message}
                or error __x"message {name} header requires message attribute"
                      , name => $msgname;

            my $hmsg = $self->wsdl->find(message => $hmsgname)
                or error __x"cannot find header message {name}"
                      , name => $hmsgname;

            my $partname = $header->{part}
                or error __x"message {name} header requires part attribute"
                      , name => $msgname;

            $encodings{$partname} = $header;
            push @{$parts{header}}
               , $self->messageSelectParts($hmsg, $partname);

            foreach my $hf ( @{$header->{headerfault} || []} )
            {   my $hfmsg  = $self->wsdl->find(message => $hf->{message})
                   or error __x"cannot find headerfault message {name}"
                         , name => $hf->{message};
                my $hfname = $hf->{part};
                $encodings{$hfname} = $hf;
                push @{$parts{headerfault}}
                   , $self->messageSelectParts($hfmsg, $hfname);
            }

            $encodings{$partname} = $header;
        }
    }

    (\%parts, \%encodings);
}

=method messageSelectParts MESSAGE, [NAMES]
Collect the named message parts.  If no names are specified, then
all are all returned.
=cut

sub messageSelectParts($@)
{   my ($self, $msg) = (shift, shift);
    my @parts = @{$msg->{part} || []};
    my @names = @_ ? @_ : map {$_->{name}} @parts;
    my %parts = map { ($_->{name} => $_) } @parts;
    my @sel;

    foreach my $name (@names)
    {   my $part = $parts{$name}
            or error __x"message {msg} does not have a part named {part}"
                  , msg => $msg->{name}, part => $name;

        my $element;
        if($element = $part->{element})
        {   # ok, simple case: follow the rules of the schema
        }
        elsif(my $type = $part->{type})
        {   # hum... no element but we need one... let's fake one
            # (but in which namespace?)  The element name might get
            # overwritten by the next compilation.
            # Profile says this is not permitted?
            my ($type_ns, $type_local) = unpack_type $type;
            $element = pack_type '', $name;
#warn "($type, $type_ns, $type_local, $element)";
            $self->schemas->importDefinitions( <<__FAKE_ELEMENT );
<schema xmlns:xx="$type_ns">
  <element name="$name" type="xx:$type_local" />
</schema>
__FAKE_ELEMENT
        }
        else
        {   error __x"part {name} has neighter element nor type", name=>$name;
        }

        push @sel, $name => $element;
    }

    \@sel;
}

=method collectFaultParts ARGS, PORT-OP, BIND-OP
=cut

my $bind_fault_reader;
sub collectFaultParts($$$)
{   my ($self, $args, $portop, $bind) = @_;
    my (%parts, %encodings);

    my $soapns      = $self->soapNameSpace;
    my $bind_faults = $bind->{"{$soapns}fault"}
        or return ({}, {});

    my $port_faults = $portop->{fault} || [];
    $bind_fault_reader ||= $self->schemas->compile(READER => "{$soapns}fault");

    foreach my $bind_fault (@$bind_faults)
    {   my $fault = ($bind_fault_reader->($bind_fault))[1];
        my $name  = $fault->{name};

        my $port  = first {$_->{name} eq $name} @$port_faults;
        defined $port
            or error __x"cannot find port for fault {name}", name => $name;

        my $msgname = $port->{message}
            or error __x"no fault message name in portOperation";

        my $message = $self->wsdl->find(message => $msgname)
            or error __x"cannot find fault message {name}", name => $msgname;

        defined $message->{parts} && @{$message->{parts}}==1
            or error __x"fault message {name} must have one part exactly"
                  , name => $msgname;
        my $part    = $message->{parts}[0];

        push @{$parts{fault}}, $name => $part;
        $encodings{$name} = $part;
    }

    (\%parts, \%encodings);
}

1;

