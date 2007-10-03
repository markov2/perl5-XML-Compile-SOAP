use warnings;
use strict;

package XML::Compile::SOAP::HTTPClient;
use base 'XML::Compile::SOAP::Client';

use Log::Report 'xml-compile-soap', syntax => 'SHORT';

use LWP            ();
use LWP::UserAgent ();
use HTTP::Request  ();
use HTTP::Headers  ();

use Time::HiRes   qw/time/;
use XML::LibXML   ();

# (Microsofts HTTP Extension Framework)
my $http_ext_id = 'http://schemas.xmlsoap.org/soap/envelope/';

=chapter NAME
XML::Compile::SOAP::HTTPClient - exchange SOAP via HTTP

=chapter SYNOPSIS
 my $call = XML::Compile::SOAP::HTTPClient->new(@options);
 my ($answer, $trace) = $call->($request);
 my $answer = $call->($request);

=chapter DESCRIPTION
This module handles the exchange of (XML) messages, according to the
rules of SOAP (any version).  The module does not known how to parse
or compose XML, but only worries about the HTTP aspects.

=chapter METHODS

=c_method new OPTIONS
Compile an HTTP client handler.  Returned is a subroutine which is called
with a text represenation of the XML request, or an XML::LibXML tree.
In SCALAR context, an XML::LibXML parsed tree of the answer message
is returned.  In LIST context, that answer is followed by a HASH which
contains trace information.

=option  user_agent M<LWP::UserAgent>
=default user_agent <singleton created>
If you pass your own user agent, you will be able to configure
it. Otherwise, one will be created with all the defaults by
M<defaultUserAgent()>. Providing your own user agents -or at least
have a look at the configuration- seems like a good idea.

=option  method 'POST'|'M-POST'
=default method 'POST'
With C<POST>, you get the standard HTTP exchange.  The C<M-POST> is
implements the (Microsoft) HTTP Extension Framework.  Some servers
accept both, other require a specific request.

=option  mpost_id INTEGER
=default mpost_id 42
With method C<M-POST>, the header extension fields require (any) number
to be grouped.

=option  address URI|ARRAY-of-URI
=default address <derived from soap_action>
One or more URI which represents the servers. One is chosen at random.

=option  mime_type STRING
=default mime_type <depends on protocol>

=option  charset STRING
=default charset 'utf-8'

=option  soap_action URI
=default soap_action C<undef>

=option  soap_version 'SOAP11'|'SOAP12'
=default soap_version 'SOAP11'

=option  header  M<HTTP::Headers> object
=default header  <created>
Versions of M<XML::Compile>, M<XML::Compile::SOAP>, and M<LWP> will be
added to simplify bug reports.

=option  transport_hook CODE
=default transport_hook <undef>
Transport is handled by M<LWP::UserAgent::request()>, however... you
may need to modify the request or answer messages outside the reach of
M<XML::Compile::SOAP>.  This may also be used for debugging.  The CODE
reference provided will be called with the request message (M<HTTP::Request>)
as first parameter, and the user agent (M<LWP::UserAgent>) as second.  You
must return an answer (M<HTTP::Response>) or C<undef>.

See section L<DETAILS/Use of transport_hook>.

=example create a client
 my $call = XML::Compile::SOAP::HTTP->client
  ( address => 'http://www.stockquoteserver.com/StockQuote' );

 # $request and $answer are XML::LibXML trees
 my ($answer, $trace) = $call->($request);

 # drop $trace info immediately
 my $answer = $call->($request);

=cut

my $parser;
sub new(@)
{   my ($class, %args) = @_;
    my $ua       = $args{user_agent}   || $class->defaultUserAgent;
    my $method   = $args{method}       || 'POST';
    my $version  = $args{soap_version} || 'SOAP11';
    my $header   = $args{header}       || HTTP::Headers->new;
    my $charset  = $args{charset}      || 'utf-8';
    my $action   = $args{soap_action};
    my $mpost_id = $args{mpost_id}     || 42;
    my $mime     = $args{mime};
    my $address  = $args{address};

    unless($address)
    {   $address = $action
            or error "no address nor soap_action specified";
        $address =~ s/\#.*//;
    }
    my @addrs    = ref $address eq 'ARRAY' ? @$address : $address;

    $class->headerAddVersions($header);

    if($version eq 'SOAP11')
    {   $mime  ||= 'text/xml';
        $header->header(Content_Type => qq{$mime; charset="$charset"});
    }
    elsif($version eq 'SOAP12')
    {   $mime  ||= 'application/soap+xml';
        my $sa   = defined $action ? qq{; action="$action"} : '';
        $header->header(Content_Type => qq{$mime; charset="$charset"$action});
    }
    else
    {   error "SOAP version {version} not implemented", version => $version;
    }

    if($method eq 'POST')
    {   $header->header(SOAPAction => qq{"$action"}) if defined $action;
    }
    elsif($method eq 'M-POST')
    {   $header->header(Man => qq{"$http_ext_id"; ns=$mpost_id});
        $header->header("$mpost_id-SOAPAction", qq{"$action"})
            if $version eq 'SOAP11';
    }
    else
    {   error "SOAP method must be POST or M-POST, not {method}"
           , method => $method;
    }

    # pick random server.  Ideally, we should change server when one
    # fails, and stick to that one as long as possible.
    my $server  = @addrs[rand @addrs];

    my $request = HTTP::Request->new($method => $server, $header);
    $parser   ||= XML::LibXML->new;

    sub
    {   $request->content(ref $_[0] ? $_[0]->toString : $_[0]);
        my $start        = time;
        my %trace        = (start => scalar localtime, request => $request);

        my $response     = $ua->request($request);

        $trace{elapse}   = time - $start;
        $trace{response} = $response;

        my $answer;
        if($response->content_type =~ m![/+]xml$!i)
        {   $answer = eval {$parser->parser_string($response->content_decoded)};
            $trace{error} = $@ if $@;
        }
        else
        {   $trace{error} = 'no xml as answer';
        }

        wantarray ? ($answer, \%trace) : $answer;
    };
}

=ci_method headerAddVersions HEADER
Adds some lines about module versions, which may help debugging
or error reports.  This is called when a new client or server
is being created.
=cut

sub headerAddVersions($)
{   my ($thing, $h) = @_;
    foreach my $pkg ( qw/XML::Compile XML::Compile::SOAP LWP/ )
    {   no strict 'refs';
        my $version = ${"${pkg}::VERSION"} || 'undef';
        (my $field = "X-$pkg-Version") =~ s/\:\:/-/g;
        $h->header($field => $version);
    }
}

=c_method defaultUserAgent [AGENT]
Returns the User Agent which will be used when none is specified.  You
may change the configuration of the AGENT (the returned M<LWP::UserAgent>
object) or provide one yourself.  See also M<new(user_agent)>.

Changes to the agent configuration can be made before or after the
compilation, or even inbetween SOAP calls.
=cut

my $user_agent;
sub defaultUserAgent(;$)
{   my $class = shift;
    return $user_agent = shift if @_;

    $user_agent ||= LWP::UserAgent->new
     ( requests_redirectable => [ qw/GET HEAD POST M-POST/ ]
     );
}

=chapter DETAILS

=section Use of transport_hook
The M<new(transport_hook)> options can be used for various purposes.
These CODE references are called in stead of the actual HTTP transport,
but may still make that happen.

=subsection The dummy hook

A dummy client transport_hook is this:

 sub hook($$)
 {  my ($request, $user_agent) = @_;
    my $answer = $user_agent->request($request);
    return $answer;
 }
 # sub hook($$) { $_[1]->request($_[0]) }

 my $http = XML::Compile::SOAP::HTTP->client
   ( ...
   , transport_hook => \&hook
   )

or

 my $call = $wsdl->prepareClient
   ( 'some port'
   , transport_hook => \&hook
   );

=subsection Example use of transport_hook

Add a print statement before and after the actual transmission.
Of course, you can get a trace hash with timing info back from the call
(in LIST context as second returned element).

 sub hook
 {  my ($request, $user_agent) = @_;
    print "sending request\n";
    my $answer = $user_agent->request($request);
    print "received answer\n";
    $answer;
 }
 
=subsection Regression tests with transport_hook

In test-scripts, we may not have access to internet, and we may not know
how to create a daemon on all kinds of platforms.  Therefore, the
M<new(transport_hook)> can be used to connect the request directly
to an answer.

 my $operation = $wsdl->operation('my-port');
 my ($soapAction, $decode_request, $encode_answer)
    = $operation->prepareServer(...);

 # Simulate server daemon
 my $hook = sub               # closure!
 {   my ($request, $user_agent) = @_;
     my $received = $decode_request->($request);
     # .... server-side tests on $received data...
     my $send     = { ... };  # fake an answer
     $encode_answer->($send);
 }

 my $client = $operation->prepareClient
   ( ....
   , transport_hook => \&hook
   );

In this case, there is no actual message transmission, because the
C<user_agent> is not used.
=cut

1;
