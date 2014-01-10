use warnings;
use strict;

package XML::Compile::Transport;
use base 'XML::Compile::SOAP::Extension';

use Log::Report 'xml-compile-soap', syntax => 'SHORT';
use Log::Report::Exception ();

use XML::LibXML            ();
use Time::HiRes            qw/time/;

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

On the moment, there are two transporter implementations:

=over 4

=item M<XML::Compile::Transport::SOAPHTTP>
implements an synchronous message exchange; the library waits for an
answer before it returns to the user application. The information is
exchanged using HTTP with SOAP encapsulation (SOAP also defines a
transport protocol over HTTP without encapsulation)

=item M<XML::Compile::Transport::SOAPHTTP_AnyEvent>
This requires the installation of an additional module. The user
provides a callback to handle responses. Many queries can be spawned
in parallel.

=back

=chapter METHODS

=section Constructors

=c_method new OPTIONS

=option  charset STRING
=default charset 'utf-8'

=option  address URI|ARRAY-of-URI
=default address 'http://localhost'
One or more URI which represents the servers.

=cut

sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);
    $self->{charset} = $args->{charset} || 'utf-8';

    my $addr  = $args->{address} || 'http://localhost';
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
See section L</Use of the transport hook>.
When defined, the hook will be called, in stead of transmitting the
message.  The hook will gets three parameters passed in: the textual
representation of the XML message to be transmitted, the trace HASH with
all values collected so far, and the transporter object.  The trace HASH
will have a massive amount of additional information added as well.

You may add information to the trace.  You have to return a textual
representation of the XML answer, or C<undef> to indicate that the
message was totally unacceptable.

=option  kind STRING
=default kind 'request-response'
Kind of communication, as defined by WSDL.

=option  xml_format 0|1|2
=default xml_format 0
[2.26] See M<XML::LibXML::Document::toString()>.  With '1', you will get
beautified output.
=cut

sub compileClient(@)
{   my ($self, %args) = @_;
    my $call   = $self->_prepare_call(\%args);
    my $kind   = $args{kind} || 'request-response';
    my $format = $args{xml_format} || 0;

    sub
    {   my ($xmlout, $trace, $mtom) = @_;
        my $start     = time;
        my $textout   = ref $xmlout ? $xmlout->toString($format) : $xmlout;
#warn $xmlout->toString(1);   # show message sent

        my $stringify = time;
        $trace->{stringify_elapse} = $stringify - $start;
        $trace->{transport_start}  = $start;

        my ($textin, $xops) = try { $call->(\$textout, $trace, $mtom) };
        my $connected = time;
        $trace->{connect_elapse}   = $connected - $stringify;
        if($@)
        {   $trace->{errors} = [$@->wasFatal];
            return;
        }

        my $xmlin;
        if($textin)
        {   $xmlin = try {XML::LibXML->load_xml(string => $$textin)};
            if($@) { $trace->{errors} = [$@->wasFatal] }
            else   { $trace->{response_dom} = $xmlin }
        }

        my $answer = $xmlin;
        if($kind eq 'one-way')
        {   my $response = $trace->{http_response};
            my $code = defined $response ? $response->code : -1;
            if($code==202) { $answer ||= {} }
            else
            {   push @{$trace->{errors}}, Log::Report::Exception->new
                 (reason => 'error', message => __"call failed with code $code")
            }
        }
        elsif(!$xmlin)
        {   push @{$trace->{errors}}, Log::Report::Exception->new
              (reason => 'error', message => __"no xml as answer");
        }

        my $end = $trace->{transport_end} = time;

        $trace->{parse_elapse}     = $end - $connected;
        $trace->{transport_elapse} = $end - $start;

        wantarray || ! keys %$xops
            or warning "loosing received XOPs";

        wantarray ? ($answer, $xops) : $answer;
    }
}

sub _prepare_call($) { panic "not implemented" }

#--------------------------------------

=chapter Helpers

=c_method register URI
Declare an transporter type.
=cut

{   my %registered;
    sub register($)   { my ($class, $uri) = @_; $registered{$uri} = $class }
    sub plugin($)     { my ($class, $uri) = @_; $registered{$uri} }
    sub registered($) { values %registered }
}

#--------------------------------------

=chapter DETAILS

=section Use of the transport hook

A I<transport hook> can be used to follow the process of creating a
message to its furthest extend: it will be called with the data as
used by the actual protocol, but will not connect to the internet.
Within the transport hook routine, you have to simulate the remote
server's activities.

There are two reasons to use a hook:

=over 4

=item .
You want to fake a server, to produce a test environment.

=item .
You may need to modify the request or answer messages outside the
reach of M<XML::Compile::SOAP>, because something is wrong in either
your WSDL of M<XML::Compile> message processing.

=back

=subsection XML and Header Modifications
  
Some servers require special extensions, which do not follow any standard
(or logic). But even those features can be tricked, although it requires
quite some programming skills.

The C<transport_hook> routine is called with a C<$trace> hash, one of
whose entries is the UserAgent which was set up for the data transfer. You
can modify the outgoing message XML body and headers, carry out the data
exchange using the UserAgent, and then examine the returned Reponse for
content and headers using methods similar to the following:

 sub transport_hook($$$)
 {   my ($request, $trace, $transporter) = @_;
     my $content = $request->content;

     # ... modify content if you need
     my $new_content = encode "utf-8", $anything;
     $request->content($new_content);
     $request->header(Content_Length => length $new_content);
     $request->header(Content_Type => 'text/plain; charset="utf-8");

     # ... update the headers
     $request->header(Name => "value");

     # sent the request myself
     my $ua = $trace->{user_agent};
     my $response = $ua->request($request);

     # ... check the response headers
     my $name = $response->header('Name');

     # ... use the response content
     my $received = $response->decoded_content || $response->content;

     $response;
 }

You should be aware that if you change the size or length of the content
you MUST update the C<Content-Length> header value, as demonstrated above.

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
 
Then, the fake server is initiated in one of the follow ways:

  my $transport = XML::Compile::Transport::SOAPHTTP->new(...);
  my $http = $transport->compileClient(hook => \&fake_server, ...);
  $wsdl->compileClient('GetLastTracePrice', transporter => $http);

or

  my $soap = XML::Compile::SOAP11::Client->new(...);
  my $call = $soap->compileClient(encode => ..., decode => ...,
      transport_hook => \&fake_server);

or

  my $wsdl = XML::Compile::WSDL11->new(...);
  $wsdl->compileClient('GetLastTracePrice',
      transport_hook => \&fake_server);


=subsection Transport hook for basic authentication

[Adapted from an example contributed by Kieron Johnson]
This example shows a transport_hook for compileClient() to add to http
headers for the basic http authentication.  The parameter can also be
used for compileAll() and many other related functions.

  my $call = $wsdl->compileClient($operation
     , transport_hook => \&basic_auth );

  # HTTP basic authentication encodes the username and password with
  # Base64. The encoded source string has format: "username:password"
  # With the below HTTP header being required:
  #        "Authorization: Basic [encoded password]"

  use MIME::Base64 'encode_base64';

  my $user     = 'myuserid' ;
  my $password = 'mypassword';

  sub basic_auth($$)
  {   my ($request, $trace) = @_;

      # Encode userid and password
      my $authorization = 'Basic '. encode_base64 "$user:$password";

      # Modify http header to include basic authorisation
      $request->header(Authorization => $authorization );

      my $ua = $trace->{user_agent};
      $ua->request($request);
  }

=cut

1;
