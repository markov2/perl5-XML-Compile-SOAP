use warnings;
use strict;

package XML::Compile::Transport;
use Log::Report 'xml-compile-soap', syntax => 'SHORT';

use XML::LibXML ();
use Time::HiRes qw/time/;

=chapter NAME
XML::Compile::Transport - base class for XML transporters

=chapter SYNOPSIS
 use XML::Compile::Transport::SOAPHTTP;
 my $trans  = XML::Compile::Transport::SOAPHTTP->new(...);
 my $call   = $trans->compileClient(...);

 my ($xmlout, $trace) = $call->($xmlin);
 my $xmlout = $call->($xmlin);   # when no trace needed

=chapter DESCRIPTION
This module defines the exchange of (XML) messages. The module does not
known how to parse or compose XML, but only worries about the transport
aspects.

On the moment, there is only one transporter implementation: the
M<XML::Compile::Transport::SOAPHTTP>.

=chapter METHODS

=section Constructors

=c_method new OPTIONS

=option  charset STRING
=default charset 'utf-8'

=option  address URI|ARRAY-of-URI
=default address 'localhost'
One or more URI which represents the servers.

=cut

sub new(@)
{   my $class = shift;
    (bless {}, $class)->init( {@_} );
}

sub init($)
{   my ($self, $args) = @_;
    $self->{charset} = $args->{charset} || 'utf-8';

    my $addr  = $args->{address} || 'localhost';
    my @addrs = ref $addr eq 'ARRAY' ? @$addr : $addr;

    $self->{addrs} = \@addrs;

    $self;
}

#-------------------------------------

=section Accessors

=method charset
Returns the charset to be used when sending,
=cut

sub charset() {shift->{charset}}

=method addresses
Returns a list of all server contact addresses (URIs)
=cut

sub addresses() { @{shift->{addrs}} }

=method address
Get a server address to contact. If multiple addresses were specified,
than one is chosen at random.
=cut

sub address()
{   my $addrs = shift->{addrs};
    @$addrs==1 ? $addrs->[0] : $addrs->[rand @$addrs];
}

#-------------------------------------

=section Handlers

=method compileClient OPTIONS
Compile a client handler.  Returned is a subroutine which is called
with a text represenation of the XML request, or an XML::LibXML tree.
In SCALAR context, an XML::LibXML parsed tree of the answer message
is returned.  In LIST context, that answer is followed by a HASH which
contains trace information.

=option  hook CODE
=default hook <undef>
See section L<DETAILS/Use of the transport hook>.
When defined, the hook will be called, in stead of transmitting the
message.  The hook will get a two parameters passed in: the textual
representation of the XML message to be transmitted, and the trace
HASH with all values collected so far.  The trace HASH will have a
massive amount of additional information added as well.

You may add information to the trace.  You have to return a textual
representation of the XML answer, or C<undef> to indicate that the
message was totally unacceptable.

=option  kind STRING
=default kind 'request-response'
Kind of communication, as defined by WSDL.
=cut

my $parser = XML::LibXML->new;
sub compileClient(@)
{   my ($self, %args) = @_;
    my $call  = $self->_prepare_call(\%args);
    my $kind  = $args{kind} || 'request-response';

    sub
    {   my ($xmlout, $trace) = @_;
        my $start     = time;
        my $textout   = ref $xmlout ? $xmlout->toString : $xmlout;

        my $stringify = time;
        $trace->{transport_start}  = $start;

        my $textin    = $call->($textout, $trace);
        my $connected = time;

        my $xmlin;
        if($textin)
        {   $xmlin = eval {$parser->parse_string($textin)};
            $trace->{error} = $@ if $@;
        }

        my $answer;
        if($kind eq 'one-way')
        {   my $response = $trace->{http_response};
            my $code = defined $response ? $response->code : -1;
            if($code==202) { $answer = $xmlin || {} }
            else { $trace->{error} = "call failed with code $code" }
        }
        elsif($xmlin) { $answer  = $xmlin }
        else { $trace->{error} = 'no xml as answer' }

        my $end = $trace->{transport_end} = time;

        $trace->{stringify_elapse} = $stringify - $start;
        $trace->{connect_elapse}   = $connected - $stringify;
        $trace->{parse_elapse}     = $end - $connected;
        $trace->{transport_elapse} = $end - $start;
        $answer;
    }
}

sub _prepare_call($) { panic "not implemented" }

=chapter DETAILS

=section Use of the transport hook

A transport hook can be used to follow the process of creating a
message to its furthest extend: it will be called with the data
as used by the actual protocol, but will not actually connect to
the internet.  Within the transport hook routine, you have to
simulate the remote server's activities.

There are two reasons to use a hook:

=over 4
=item .
You may need to modify the request or answer messages outside the
reach of M<XML::Compile::SOAP>, because something is wrong in either
your WSDL of M<XML::Compile> message processing.

=item .
You want to fake a server, to produce a test environment.
=back

=subsection Transport hook for debugging

The transport hook is a perfect means for producing automated tests.  Also,
the XML::Compile::SOAP module tests use it extensively.  It works like this
(for the SOAPHTTP simluation):

 use Test::More;

 sub fake_server($$)
 {  my ($request, $trace) = @_;
    my $content = $request->decoded_content;
    is($content, <<__EXPECTED_CONTENT);
<SOAP-ENV:Envelope>...</SOAP-ENV:Envelope>
__EXPECTED_CONTENT

    HTTP::Response->new(200, 'Constant'
      , [ 'Content-Type' => 'text/xml' ]
      , <<__ANSWER
<SOAP-ENV:Envelope>...</SOAP-ENV:Envelope>
__ANSWER
 }
 
Then, the fake server is initiated in one of the following ways:

  my $transport = XML::Compile::Transport::SOAPHTTP->new(...);
  my $http = $transport->createClient(hook => \&fake_server, ...);

or

  my $soap = XML::Compile::SOAP11::Client->new(...);
  my $call = $soap->compileClient(encode => ..., decode => ...,
      transport_hook => \&fake_server);

or

  my $wsdl = XML::Compile::WSDL11->new(...);
  $wsdl->compileClient('GetLastTracePrice',
      transport_hook => \&fake_server);

=cut

1;
