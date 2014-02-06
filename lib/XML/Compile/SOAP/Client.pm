use warnings;
use strict;

package XML::Compile::SOAP::Client;

use Log::Report 'xml-compile-soap', syntax => 'SHORT';

use XML::Compile::Util qw/unpack_type/;
use XML::Compile::SOAP::Trace;
use Time::HiRes        qw/time/;

=chapter NAME
XML::Compile::SOAP::Client - SOAP message initiators

=chapter SYNOPSIS
 # never used directly, only via XML::Compile::SOAP1[12]::Client

=chapter DESCRIPTION
This class defines the methods that each client side of the SOAP
message exchange protocols must implement.

=chapter METHODS

=section Constructors
This object can not be instantiated, but is only used as secundary
base class.  The primary must contain the C<new>.
=cut

sub new(@) { panic __PACKAGE__." only secundary in multiple inheritance" }
sub init($) { shift }

=section Handlers

=method compileClient %options

=option  name STRING
=default name <undef>

=option  kind STRING
=default kind C<request-response>
Which kind of client is this.  WSDL11 defines four kinds of client-server
interaction.  Only C<request-response> (the default) and C<one-way> are
currently supported.

=requires encode CODE
The CODE reference is produced by M<XML::Compile::SOAP::compileMessage()>,
and must be a SENDER: translates Perl data structures into the SOAP
message in XML.

=requires decode CODE
The CODE reference is produced by M<XML::Compile::SOAP::compileMessage()>,
and must be a RECEIVER: translate a SOAP message into Perl data.  Even in
one-way operation, this decode should be provided: some servers may pass
back some XML in case of errors.

=requires transport CODE|OBJECT
The CODE reference is produced by an extensions of
M<XML::Compile::Transport::compileClient()> (usually
M<XML::Compile::Transport::SOAPHTTP::compileClient()>.

If you pass a M<XML::Compile::Transport::SOAPHTTP> object, the
compileClient will be called for you.  This is possible in case you do
not have any configuration options to pass with the compileClient().

=option  async BOOLEAN
=default async <false>
If true, a whole different code-reference is returned. Each time it
is called, the call will be made but the function returns immediately.
As additional parameter to the call, you must provide a C<_callback>
parameter which is a code-reference which will handle the result.

=example

Normal call:

   my $call = $wsdl->compileClient('myOp');
   my ($answer, $trace) = $call->(@params);
   #do something with $answer

Async call:

   my $call = $wsdl->compileClient('myOp', async => 1);
   sub cb
   {  my ($answer, $trace) = @_;
      #do something with $answer
   };
   $call->(@params, _callback => \&cb);

=cut

my $rr = 'request-response';

sub compileClient(@)
{   my ($self, %args) = @_;

    my $name = $args{name};
    my $kind = $args{kind} || $rr;
    $kind eq $rr || $kind eq 'one-way'
        or error __x"operation direction `{kind}' not supported for {name}"
             , rr => $rr, kind => $kind, name => $name;

    my $encode = $args{encode}
        or error __x"encode for client {name} required", name => $name;

    my $decode = $args{decode}
        or error __x"decode for client {name} required", name => $name;

    my $transport = $args{transport}
        or error __x"transport for client {name} required", name => $name;

    if(ref $transport eq 'CODE') { ; }
    elsif(UNIVERSAL::isa($transport, 'XML::Compile::Transport::SOAPHTTP'))
    {   $transport = $transport->compileClient;
    }
    else
    {   error __x"transport for client {name} is code ref or {type} object, not {is}"
          , name => $name, type => 'XML::Compile::Transport::SOAPHTTP'
          , is => (ref $transport || $transport);
    }

    my $output_handler = sub {
        my ($ans, $trace) = @_;
        wantarray or return
            UNIVERSAL::isa($ans, 'XML::LibXML::Node') ? $decode->($ans) : $ans;

        if(UNIVERSAL::isa($ans, 'XML::LibXML::Node'))
        {   $ans = try { $decode->($ans) };
            if($@)
            {   $trace->{decode_errors} = $@;
                my $fatal = $@->wasFatal;
                $trace->{errors} = [$fatal];
                $fatal->message($fatal->message->concat('decode error: ', 1));
            }

            my $end = time;
            $trace->{decode_elapse} = $end - $trace->{transport_end};
            $trace->{elapse} = $end - $trace->{start};
        }
        else
        {   $trace->{elapse} = $trace->{transport_end} - $trace->{start}
                if defined $trace->{transport_end};
        }
        ($ans, XML::Compile::SOAP::Trace->new($trace));
    };

    $args{async}
    ? sub  # Asynchronous call, f.i. X::C::Transfer::SOAPHTTP::AnyEvent
      { my ($data, $charset)
          = UNIVERSAL::isa($_[0], 'HASH') ? @_
          : @_%2==0 ? ({@_}, undef)
          : error __x"operation `{name}' called with odd length parameter list"
              , name => $name;

        my $callback = delete $data->{_callback}
            or error __x"opertaion `{name}' is async, so requires _callback";

        my $trace = {start => time};
        my ($req, $mtom) = $encode->($data, $charset);
        $trace->{encode_elapse} = time - $trace->{start};

        $transport->($req, $trace, $mtom
          , sub { $callback->($output_handler->(@_)) }
          );
      }
    : sub # Synchronous call (f.i. XML::Compile::Transfer::SOAPHTTP
      { my ($data, $charset)
          = UNIVERSAL::isa($_[0], 'HASH') ? @_
          : @_%2==0 ? ({@_}, undef)
          : panic(__x"operation `{name}' called with odd length parameter list"
              , name => $name);

        $data->{_callback}
            and error __x"operation `{name}' called with _callback, but "
                  . "compiled without async flag", name => $name;

        my $trace = {start => time};
        my ($req, $mtom) = $encode->($data, $charset);
        my $ans = $transport->($req, $trace, $mtom);

        $trace->{encode_elapse} = $trace->{transport_start} - $trace->{start};
        $output_handler->($ans, $trace);
      };
}

#------------------------------------------------

=chapter DETAILS

=section Client side SOAP

=subsection Calling the server (Document style)

First, you compile the call either via a WSDL file (see
M<XML::Compile::WSDL11>), or in a few manual steps (which are described
in the next section).  In either way, you end-up with a CODE references
which can be called multiple times.

    # compile once
    my $call   = $soap->compileClient(...);

    # and call often
    my $answer = $call->(%request);  # list of pairs
    my $answer = $call->(\%request); # same, but HASH
    my $answer = $call->(\%request, 'UTF-8');  # same

    # or with trace details, see XML::Compile::SOAP::Trace
    my ($answer, $trace) = $call->...

But what is the structure of C<%request> and C<$answer>?  Well, there
are various syntaxes possible: from structurally perfect, to user-friendly.

First, find out which data structures can be present: when you compiled
your messages explicitly, you have picked your own names.  When the
call was initiated from a WSDL file, then you have to find the names of
the message parts which can be used: the part names for header blocks,
body blocks, headerfaults, and (body) faults.  Do not worry to much,
you will get (hopefully understandable) run-time error messages when
the structure is incorrect.

Let's say that the WSDL defines this (ignoring all name-space issues)

 <definitions xmlns:xx="MYNS"
   <message name="GetLastTradePriceInput">
    <part name="count" type="int" />
    <part name="request" element="xx:TradePriceRequest"/>
   </message>

   <message name="GetLastTradePriceOutput">
    <part name="answer" element="xx:TradePrice"/>
   </message>

   <binding
    <operation
     <input>
      <soap:header message="GetLastTradePriceInput" part="count"
      <soap:body message="GetLastTradePriceInput" parts="request"
     <output>
      <soap:body message="GetLastTradePriceOutput"

The input message needs explicitly named parts in this case, where the
output message simply uses all defined in the body.  So, the input message
has one header part C<count>, and one body part C<request>.  The output
message only has one part named C<answer>, which is all defined for the
message and therefore its name can be omitted.

Then, the definitions of the blocks:

 <schema targetNamespace="MYNS"
   <element name="TradePriceRequest">
    <complexType>
     <all>
      <element name="tickerSymbol" type="string"/>

   <element name="TradePrice">
    <complexType>
     <all>
      <element name="price" type="float"/>
 </schema>

Now, calling the compiled function can be done like this:

  my $got
     = $call->(  count => 5, request => {tickerSymbol => 'IBM'}  );
     = $call->({ count => 5, request => {tickerSymbol => 'IBM'} });
     = $call->({ count => 5, request => {tickerSymbol => 'IBM'} }
        , 'UTF-8');

If the first arguments for the code ref is a HASH, then there may be
a second which specifies the required character-set.  The default is
C<UTF-8>, which is very much advised.

=subsection Parameter unpacking (Document Style)

In the example situation of previous section, you may simplify the
call even further.  To understand how, we need to understand the
parameter unpacking algorithm.

The structure which we need to end up with, looks like this

  $call->(\%data, $charset);
  %data = ( Header => {count => 5}
          , Body   =>
             { request => {tickerSymbol => 'IBM'} }
          );

The structure of the SOAP message is directly mapped on this
nested complex HASH.  But is inconvenient to write each call
like this, therefore the C<$call> parameters are transformed into
the required structure according to the following rules:

=over 4
=item 1.
if called with a LIST, then that will become a HASH

=item 2.
when a C<Header> and/or C<Body> are found in the HASH, those are used

=item 3.
if there are more parameters in the HASH, then those with names of
known header and headerfault message parts are moved to the C<Header>
sub-structure.  Body and fault message parts are moved to the C<Body>
sub-structure.

=item 4.
If the C<Body> sub-structure is empty, and there is only one body part
expected, then all remaining parameters are put in a HASH for that part.
This also happens if there are not parameters: it will result in an
empty HASH for that block.

=back

So, in our case this will also do, because C<count> is a known part,
and C<request> gets all left-overs, being the only body part.

 my $got = $call->(count => 5, tickerSymbol => 'IBM');

This does not work if the block element is a simple type.  In most
existing Document style SOAP schemas, this simplification probably
is possible.

=subsection Understanding the output (Document style)

The C<$got> is a HASH, which will not be simplified automatically:
it may change with future extensions of the interface.  The return
is a complex nested structure, and M<Data::Dumper> is your friend.

 $got = { answer => { price => 16.3 } }

To access the value use

 printf "%.2f US\$\n", $got->{answer}->{price};
 printf "%.2f US\$\n", $got->{answer}{price};   # same

or

 my $answer = $got->{answer};
 printf "%.2f US\$\n", $answer->{price};

=subsection Calling the server (SOAP-RPC style literal)

SOAP-RPC style messages which have C<<use=literal>> cannot be used
without a little help.  However, one extra definition per procedure
call suffices.

This a complete code example, although you need to fill in some
specifics about your environment.  If you have a WSDL file, then it
will be a little simpler, see M<XML::Compile::WSDL11::compileClient()>.

 # You probably need these
 use XML::Compile::SOAP11::Client;
 use XML::Compile::Transport::SOAPHTTP;
 use XML::Compile::Util  qw/pack_type/;

 # Literal style RPC
 my $outtype = pack_type $MYNS, 'myFunction';
 my $intype  = pack_type $MYNS, 'myFunctionResponse';

 # Encoded style RPC (see next section on these functions)
 my $outtype = \&my_pack_params;
 my $intype  = \&my_unpack_params;

 # For all RPC calls, you need this only once (or have a WSDL):
 my $transp  = XML::Compile::Transport::SOAPHTTP->new(...);
 my $http    = $transp->compileClient(...);
 my $soap    = XML::Compile::SOAP11::Client->new(...);
 my $send    = $soap->compileMessage('SENDER',   style => $style, ...);
 my $get     = $soap->compileMessage('RECEIVER', style => $style, ...);

 # Per RPC procedure
 my $myproc = $soap->compileClient
   ( name   => 'MyProc'
   , encode => $send, decode => $get, transport => $http
   );

 my $answer = $myproc->(@parameters);   # as document style

Actually, the C<< @paramers >> are slightly less flexible as in document
style SOAP.  If you use header blocks, then the called CODE reference
will not be able to distinguish between parameters for the RPC block and
parameters for the header blocks.

  my $answer = $trade_price
    ->( {symbol => 'IBM'}    # the RPC package implicit
      , transaction => 5     # in the header
      );

When the number of arguments is odd, the first is indicating the RPC
element, and the other pairs refer to header blocks.

The C<$answer> structure may contain a C<Fault> entry, or a decoded
datastructure with the results of your query.  One call using
M<Data::Dumper> will show you more than I can explain in a few hundred
words.

=subsection Calling the server (SOAP-RPC style, encoded)

SOAP-RPC is a simplification of the interface description: basically,
the interface is not described at all, but left to good communication
between the client and server authors.  In strongly typed languages,
this is quite simple to enforce: the client side and server side use
the same method prototypes.  However, in Perl we are blessed to go
without these strongly typed prototypes.

The approach of M<SOAP::Lite>, is to guess the types of the passed
parameters.  For instance, "42" will get passed as Integer.  This
may lead to nasty problems: a float parameter "2.0" will get passed
as integer "2", or a string representing a house number "8" is passed
as an number.  This may not be accepted by the SOAP server.

So, using SOAP-RPC in M<XML::Compile::SOAP> will ask a little more
effort from you: you have to state parameter types explicitly.  In
the F<examples/namesservice/> directory, you find a detailed example.
You have to create a CODE ref which produces the message, using
methods defined provided by M<XML::Compile::SOAP11::Encoding>.

=subsection Faults (Document and RPC style)

Faults and headerfaults are a slightly different story: the type which
is specified with them is not of the fault XML node itself, but of the
C<detail> sub-element within the standard fault structure.

When producing the data for faults, you must be aware of the fact that
the structure is different for SOAP1.1 and SOAP1.2.  When interpreting
faults, the same problems are present, although the implementation
tries to help you by hiding the differences.

Check whether SOAP1.1 or SOAP1.2 is used by looking for a C<faultcode>
(SOAP1.1) or a C<Code> (SOAP1.2) field in the data:

  if(my $fault = $got->{Fault})
  {  if($fault->{faultcode}) { ... SOAP1.1 ... }
     elsif($fault->{Code})   { ... SOAP1.2 ... }
     else { die }
  }

In either protocol case, the following will get you at a compatible
structure in two steps:

  if(my $fault = $got->{Fault})
  {   my $decoded = fault->{_NAME}};
      print $got->{$decoded}->{code};
      ...
  }

See the respective manuals M<XML::Compile::SOAP11> and
M<XML::Compile::SOAP12> for the hairy details.  But one thing can be said:
when the fault is declared formally, then the C<_NAME> will be the name
of that part.

=section SOAP without WSDL (Document style)

See the manual page of M<XML::Compile::WSDL11> to see how simple you
can use this module when you have a WSDL file at hand.  The creation of
a correct WSDL file is NOT SIMPLE.

When using SOAP without WSDL file, it gets a little bit more complicate
to use: you need to describe the content of the messages yourself.
The following example is used as test-case C<t/10soap11.t>, directly
taken from the SOAP11 specs section 1.3 example 1.

 # for simplification
 my $TestNS   = 'http://test-types';
 use XML::Compile::Util qw/SCHEMA2001/;
 my $SchemaNS = SCHEMA2001;

First, the schema (hopefully someone else created for you, because they
can be quite hard to create correctly) is in file C<myschema.xsd>

 <schema targetNamespace="$TestNS"
   xmlns="$SchemaNS">

 <element name="GetLastTradePrice">
   <complexType>
      <all>
        <element name="symbol" type="string"/>
      </all>
   </complexType>
 </element>

 <element name="GetLastTradePriceResponse">
   <complexType>
      <all>
         <element name="price" type="float"/>
      </all>
   </complexType>
 </element>

 <element name="Transaction" type="int"/>
 </schema>

Ok, now the program you create the request:

 use XML::Compile::SOAP11;
 use XML::Compile::Util  qw/pack_type/;

 my $soap   = XML::Compile::SOAP11->new;
 $soap->schemas->importDefinitions('myschema.xsd');

 my $get_price = $soap->compileMessage
   ( 'SENDER'
   , header =>
      [ transaction => pack_type($TestNS, 'Transaction') ]
   , body  =>
      [ request => pack_type($TestNS, 'GetLastTradePrice') ]
   , mustUnderstand => 'transaction'
   , destination    => [ transaction => 'NEXT http://actor' ]
   );

C<INPUT> is used in the WSDL terminology, indicating this message is
an input message for the server.  This C<$get_price> is a WRITER.  Above
is done only once in the initialization phase of your program.

At run-time, you have to call the CODE reference with a
data-structure which is compatible with the schema structure.
(See M<XML::Compile::Schema::template()> if you have no clue how it should
look)  So: let's send this:

 # insert your data
 my %data_in = (transaction => 5, request => {symbol => 'DIS'});
 my %data_in = (transaction => 5, symbol => 'DIS'); # alternative

 # create a XML::LibXML tree
 my $xml  = $get_price->(\%data_in, 'UTF-8');
 print $xml->toString;

And the output is:

 <SOAP-ENV:Envelope
    xmlns:x0="http://test-types"
    xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/">
   <SOAP-ENV:Header>
     <x0:Transaction
       mustUnderstand="1"
       actor="http://schemas.xmlsoap.org/soap/actor/next http://actor">
         5
     </x0:Transaction>
   </SOAP-ENV:Header>
   <SOAP-ENV:Body>
     <x0:GetLastTradePrice>
       <symbol>DIS</symbol>
     </x0:GetLastTradePrice>
   </SOAP-ENV:Body>
 </SOAP-ENV:Envelope>

Some transport protocol will sent this data from the client to the
server.  See M<XML::Compile::Transport::SOAPHTTP>, as one example.

On the SOAP server side, we will parse the message.  The string C<$soap>
contains the XML.  The program looks like this:

 my $server = $soap->compileMessage # create once
  ( 'RECEIVER'
  , header => [ transaction => pack_type($TestNS, 'Transaction') ]
  , body   => [ request => pack_type($TestNS, 'GetLastTradePrice') ]
  );

 my $data_out = $server->($soap);   # call often

Now, the C<$data_out> reference on the server, is stucturally exactly 
equivalent to the C<%data_in> from the client.

=cut

1;
