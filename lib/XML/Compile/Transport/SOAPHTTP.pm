use warnings;
use strict;

package XML::Compile::Transport::SOAPHTTP;
use base 'XML::Compile::Transport';

use Log::Report 'xml-compile-soap', syntax => 'SHORT';
use XML::Compile::SOAP::Util qw/SOAP11ENV/;

use LWP            ();
use LWP::UserAgent ();
use HTTP::Request  ();
use HTTP::Headers  ();

use XML::LibXML   ();
use Encode;

my $parser = XML::LibXML->new;

# (Microsofts HTTP Extension Framework)
my $http_ext_id = SOAP11ENV;

=chapter NAME
XML::Compile::Transport::SOAPHTTP - exchange XML via HTTP

=chapter SYNOPSIS
 use XML::Compile::Transport::SOAPHTTP;

 my $http = XML::Compile::Transport::SOAPHTTP->new(@options);
 my $send = $transporter->compileClient(@options2);

 my $call = $wsdl->compileClient
  ( operation => 'some-port-name'
  , transport => $send
  );

 my ($xmlout, $trace) = $call->($xmlin);

=chapter DESCRIPTION
This module handles the exchange of (XML) messages, according to the
rules of SOAP (any version).  The module does not known how to parse
or compose XML, but only worries about the HTTP aspects.

=chapter METHODS

=c_method new OPTIONS
The C<keep_alive> and C<timeout> options are used when an M<LWP::UserAgent>
is created, and ignored when you provide such an object.  In the latter
case, the values for those are inquired such that you can see the setting
directly from the passed object.

If you need to change UserAgent settings later, you can always directly
access the M<LWP::UserAgent> object via M<userAgent()>.

=option  user_agent LWP::UserAgent object
=default user_agent <created when needed>
If you pass your own user agent, you will be able to configure
it. Otherwise, one will be created with all the defaults. Providing
your own user agents -or at least have a look at the configuration-
seems like a good idea.

=option  keep_alive BOOLEAN
=default keep_alive <true>
When connection can be re-used.

=option  timeout SECONDS
=default timeout 180
The maximum time for a single connection before the client will close it.
The server may close it earlier.  Do not set the timeout too long, because
you want objects to be cleaned-up.
=cut

sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);

    $self->userAgent
     ( $args->{user_agent}
     , keep_alive => (exists $args->{keep_alive} ? $args->{keep_alive} : 1)
     , timeout => ($args->{timeout} || 180)
     );
    $self;
}

#-------------------------------------------

=section Accessors

=method userAgent [AGENT|(undef, OPTIONS)]
Returns the User Agent which will be used.  You may change the
configuration of the AGENT (the returned M<LWP::UserAgent> object)
or provide one yourself.  See also M<new(user_agent)>.

Changes to the agent configuration can be made before or after the
compilation, or even inbetween SOAP calls.
=cut

sub userAgent(;$)
{   my ($self, $agent) = (shift, shift);
    return $self->{user_agent} = $agent
        if defined $agent;

    $self->{user_agent}
    ||= LWP::UserAgent->new
         ( requests_redirectable => [ qw/GET HEAD POST M-POST/ ]
         , parse_head => 0
         , protocols_allowed => [ qw/http https/ ]
         , @_
         );
}

#-------------------------------------------

=section Handlers

=method compileClient OPTIONS

Compile an HTTP client handler.  Returned is a subroutine which is called
with a text represenation of the XML request, or an XML::LibXML tree.
In SCALAR context, an XML::LibXML parsed tree of the answer message
is returned.  In LIST context, that answer is followed by a HASH which
contains trace information.

=option  method 'POST'|'M-POST'
=default method 'POST'
With C<POST>, you get the standard HTTP exchange.  The C<M-POST> is
implements the (Microsoft) HTTP Extension Framework.  Some servers
accept both, other require a specific request.

=option  mpost_id INTEGER
=default mpost_id 42
With method C<M-POST>, the header extension fields require (any) number
to be grouped.

=option  mime_type STRING
=default mime_type <depends on soap version>

=option  action URI
=default action ''

=option  soap 'SOAP11'|'SOAP12'|OBJECT
=default soap 'SOAP11'

=option  header  HTTP::Headers object
=default header  <created>
Versions of M<XML::Compile>, M<XML::Compile::SOAP>, and M<LWP> will be
added to simplify bug reports.

=example create a client
 my $trans = XML::Compile::Transport::SOAPHTTP->new
   ( address => 'http://www.stockquoteserver.com/StockQuote'
   );

 my $call = $trans->compileClient
   ( action  => 'http://example.com/GetLastTradePrice'
   );

 # $request and $answer are XML::LibXML trees!
 # see M<XML::Compile::SOAP::Client::compileClient()> for wrapper which
 # converts from and to Perl data structures.

 my ($answer, $trace) = $call->($request);
 my $answer = $call->($request); # drop $trace info immediately

=cut

# SUPER::compileClient() calls this method to do the real work
sub _prepare_call($)
{   my ($self, $args) = @_;
    my $method   = $args->{method}       || 'POST';
    my $soap     = $args->{soap}         || 'SOAP11';
    my $version  = ref $soap ? $soap->version : $soap;
    my $mpost_id = $args->{mpost_id}     || 42;
    my $mime     = $args->{mime};
    my $action   = $args->{action}       || '';

    my $charset  = $self->charset;
    my $ua       = $self->userAgent;

    # Prepare header

    my $header   = $args->{header}       || HTTP::Headers->new;
    $self->headerAddVersions($header);

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
    {   $header->header(SOAPAction => qq{"$action"})
            if defined $action;
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

    # Prepare request

    # Ideally, we should change server when one fails, and stick to that
    # one as long as possible.
    my $server  = $self->address;
    my $request = HTTP::Request->new($method => $server, $header);
    $request->protocol('HTTP/1.1');

    # Create handler

    my $hook = $args->{hook};

      $hook
    ? sub  # hooked code
      { my $trace = $_[1];
        my $u = encode($charset, $_[0]);
        $request->content($u);
        { use bytes; $request->header('Content-Length' => length $u); }
 
        $trace->{http_request}  = $request;
        $trace->{action}        = $action;
        $trace->{soap_version}  = $version;
        $trace->{server}        = $server;
        $trace->{user_agent}    = $ua;
        $trace->{hooked}        = 1;

        my $response = $hook->($request, $trace)
           or return undef;

        $trace->{http_response} = $response;

          defined $response && $response->content_type =~ m![/+]xml$!i
        ? $response->decoded_content
        : undef;
      }

    : sub  # normal code
      { my $trace = $_[1];
        my $u = encode($charset, $_[0]);
        $request->content($u);
        { use bytes; $request->header('Content-Length' => length $u); }

        $trace->{http_request}  = $request;

        my $response = $ua->request($request)
            or return undef;

        $trace->{http_response} = $response;

          $response->content_type =~ m![/+]xml$!i
        ? $response->decoded_content
        : undef;
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

1;
