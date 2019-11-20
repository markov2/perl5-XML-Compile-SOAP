# This code is part of distribution XML-Compile-SOAP.  Meta-POD processed
# with OODoc into POD and HTML manual-pages.  See README.md
# Copyright Mark Overmeer.  Licensed under the same terms as Perl itself.

package XML::Compile::Transport::SOAPHTTP;
use base 'XML::Compile::Transport';

use warnings;
use strict;

use Log::Report    'xml-compile-soap';

use XML::Compile::SOAP::Util qw/SOAP11ENV SOAP11HTTP/;
use XML::Compile   ();

use LWP            ();
use LWP::UserAgent ();
use HTTP::Request  ();
use HTTP::Headers  ();
use Encode;

# (Microsofts HTTP Extension Framework)
my $http_ext_id = SOAP11ENV;

my $mime_xop    = 'application/xop+xml';

__PACKAGE__->register(SOAP11HTTP);

=chapter NAME
XML::Compile::Transport::SOAPHTTP - exchange XML-SOAP via HTTP

=chapter SYNOPSIS
 use XML::Compile::Transport::SOAPHTTP;

 my $http = XML::Compile::Transport::SOAPHTTP->new(@options);
 my $send = $http->compileClient(@options2);

 my $call = $wsdl->compileClient
   ( operation => 'some-port-name'
   , transport => $send
   );

 my ($xmlout, $trace) = $call->($xmlin);

 $wsdl->compileCalls(transport => $send);

=chapter DESCRIPTION
This module handles the exchange of (XML) messages, according to the
rules of SOAP (any version).  The module does not known how to parse
or compose XML, but only worries about the HTTP aspects.

=chapter METHODS

=c_method new %options
Create a SOAP-over-HTTP handler, implemented as a wrapper around
M<LWP::UserAgent>.

If you need to change UserAgent settings (for instance at runtime),
you can always directly access the internal C<LWP::UserAgent> object
via M<userAgent()>.

B<Warning:> The C<keep_alive> and C<timeout> options are only used when
an default internal C<LWP::UserAgent> is created; this is only once in a
program.  Later instantiations of this ::SOAPHTTP will share that default
agent, even though these passed parameters have different parameters.
If that is not what you want, then pass your own C<user_agent> object to
the constructor to avoid the use of the default.

=option  user_agent LWP::UserAgent object
=default user_agent <created when needed>
If you do not pass your own user agent, a default will be created for you.

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
      , timeout    => ($args->{timeout} || 180)
      );
    $self;
}

sub initWSDL11($)
{   my ($class, $wsdl) = @_;
    trace "initialize SOAPHTTP transporter for WSDL11";
}

#-------------------------------------------

=section Accessors

=method userAgent [$agent|<undef, %options>]
Returns the User Agent which will be used.  You may change the
configuration of the $agent (the returned M<LWP::UserAgent> object)
or provide one yourself.  See also M<new(user_agent)>.

Changes to the agent configuration can be made before or after the
compilation, or even inbetween SOAP calls.
=cut

my $default_ua;
sub userAgent(;$)
{   my ($self, $agent) = (shift, shift);
    return $self->{user_agent} = $agent
        if defined $agent;

    $self->{user_agent} ||= $default_ua ||= LWP::UserAgent->new
      ( requests_redirectable => [ qw/GET HEAD POST M-POST/ ]
      , protocols_allowed     => [ qw/http https/ ]
      , parse_head            => 0
      , @_
      );
}

=ci_method defaultUserAgent
[3.07] Returns the used M<LWP::UserAgent>, available after the compilation
of the SOAP call(s).
=cut

sub defaultUserAgent() { $default_ua }

#-------------------------------------------

=section Handlers

=method compileClient %options

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

=option  kind    DIRECTION
=default kind    'request-response'
What kind of interactie, based on the four types defined by WSDL(1):
C<notification-operation> (server initiated, no answer required),
C<one-way> (client initiated, no answer required), C<request-response>
(client initiated, the usual in both directions), C<solicit-response> (server
initiated "challenge").

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
    my $method   = $args->{method}   || 'POST';
    my $soap     = $args->{soap}     || 'SOAP11';
    my $version  = ref $soap ? $soap->version : $soap;
    my $mpost_id = $args->{mpost_id} || 42;
    my $action   = $args->{action};
    my $mime     = $args->{mime};
    my $kind     = $args->{kind}     || 'request-response';
    my $expect   = $kind ne 'one-way' && $kind ne 'notification-operation';

    my $charset  = $self->charset;
    my $ua       = $self->userAgent;

    # Prepare header
    my $header   = $args->{header}   || HTTP::Headers->new;
    $self->headerAddVersions($header);

	# There is probably never a real HTTP server on the other side, but
    # HTTP/1.1 requires this.
	$header->header(Host => $1)
        if +($args->{endpoint} // '') =~ m!^\w+\://([^/:]+)!;

    my $content_type;
    if($version eq 'SOAP11')
    {   $mime  ||= 'text/xml';
        $content_type = qq{$mime; charset=$charset};
    }
    elsif($version eq 'SOAP12')
    {   $mime  ||= 'application/soap+xml';
        my $sa   = defined $action ? qq{; action="$action"} : '';
        $content_type = qq{$mime; charset=$charset$sa};
        $header->header(Accept => $mime);  # not the HTML answer
    }
    else
    {   error "SOAP version {version} not implemented", version => $version;
    }

    if($method eq 'POST')
    {   # should only be used by SOAP11, but you never know.  So, SOAP12
        # will have the action both ways.
        $header->header(SOAPAction => qq{"$action"})
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

    # Create handler

    my ($create_message, $parse_message)
      = exists $INC{'XML/Compile/XOP.pm'}
      ? $self->_prepare_xop_call($content_type)
      : $self->_prepare_simple_call($content_type);

    $parse_message = $self->_prepare_for_no_answer($parse_message)
        unless $expect;

    my $hook = $args->{hook};

    $hook
    ? sub  # hooked code
      { my $trace   = $_[1];

        my $request = HTTP::Request->new($method => $server, $header);
        $request->protocol('HTTP/1.1');
        $create_message->($request, $_[0], $_[2]);
 
        $trace->{http_request}  = $request;
        $trace->{action}        = $action;
        $trace->{soap_version}  = $version;
        $trace->{server}        = $server;
        $trace->{user_agent}    = $ua;
        $trace->{hooked}        = 1;

        my $response = $hook->($request, $trace, $self)
            or return undef;

	UNIVERSAL::isa($response, 'HTTP::Response')
            or error __x"transport_hook must produce a HTTP::Response, got {resp}"
                 , resp => $response;

        $trace->{http_response} = $response;
        if($response->is_error)
        {   error $response->message
                if $response->header('Client-Warning');

            warning $response->message;
            # still try to parse the response for Fault blocks
        }

        $parse_message->($response);
      }

    : sub  # real call
      { my $trace   = $_[1];

        my $request = HTTP::Request->new($method => $server, $header);
        $request->protocol('HTTP/1.1');
        $create_message->($request, $_[0], $_[2]);

        $trace->{http_request}  = $request;

        my $response = $ua->request($request)
            or return undef;

        $trace->{http_response} = $response;

        if($response->is_error)
        {   error $response->message
                if $response->header('Client-Warning');

            warning $response->message;
            # still try to parse the response for Fault blocks
        }

        $parse_message->($response);
      };
}

sub _prepare_simple_call($)
{   my ($self, $content_type) = @_;

    my $create = sub
      { my ($request, $content) = @_;
        $request->header(Content_Type => $content_type);
        $request->content_ref($content);   # already bytes (not utf-8)
        use bytes; $request->header('Content-Length' => length $$content);
      };

    my $parse  = sub
      { my $response = shift;
        UNIVERSAL::isa($response, 'HTTP::Response')
            or error __x"no response object received";

        my $ct       = $response->content_type || '';
        lc($ct) ne 'multipart/related'
            or error __x"remote system uses XOP, use XML::Compile::XOP";
 
        trace "received ".$response->status_line;

        $ct =~ m,[/+]xml$,i
            or error __x"answer is not xml but `{type}'", type => $ct;

        # HTTP::Message::decoded_content() does not work for old Perls
        my $content = $response->decoded_content(ref => 1)
                   || $response->content(ref => 1);

        ($content, {});
      };

    ($create, $parse);
}

sub _prepare_xop_call($)
{   my ($self, $content_type) = @_;

    my ($simple_create, $simple_parse)
      = $self->_prepare_simple_call($content_type);

    my $charset = $self->charset;
    my $create  = sub
      { my ($request, $content, $mtom) = @_;
        $mtom        ||= [];
        @$mtom or return $simple_create->($request, $content);

        my $bound      = "MIME-boundary-".int rand 10000;
        (my $start_cid = $mtom->[0]->cid) =~ s/^.*\@/xml@/;

        my $si         = "$content_type";
        $si            =~ s/\"/\\"/g;
        $request->header(Content_Type => <<__CT);
multipart/related;
 boundary="$bound";
 type="$mime_xop";
 start="<$start_cid>";
 start-info="$si"
__CT

        my $base = HTTP::Message->new
          ( [ Content_Type => qq{$mime_xop; charset="$charset"; type="$si"}
            , Content_Transfer_Encoding => '8bit'
            , Content_ID  => "<$start_cid>"
            ] );
        $base->content_ref($content);   # already bytes (not utf-8)

        my @parts = ($base, map $_->mimePart, @$mtom);
        $request->parts(@parts); #$base, map $_->mimePart, @$mtom);
        $request;
      };

    my $parse  = sub
      { my ($response, $mtom) = @_;
        my $ct = $response->header('Content-Type') || '';
        $ct    =~ m!^\s*multipart/related\s*\;!i
             or return $simple_parse->($response);

        my (@parts, %parts);
        foreach my $part ($response->parts)
        {   my $include = XML::Compile::XOP::Include->fromMime($part)
               or next;
            $parts{$include->cid} = $include;
            push @parts, $include;
        }

        @parts
            or error "no parts in response multi-part for XOP";

        my $root;
        if($ct =~ m!start\=(["']?)\<([^"']*)\>\1!)
        {   my $startid = $2;
            $root = delete $parts{$startid};
            defined $root
                or warning __x"cannot find root node id in parts `{id}'"
                    , id => $startid;
        }
        unless($root)
        {   $root = shift @parts;
            delete $parts{$root->cid};
        }

        ($root->content(1), \%parts);
      };

    ($create, $parse);
}

sub _prepare_for_no_answer($)
{   my $self = shift;
    sub
      { my $response = shift;
        my $ct       = $response->content_type || '';

        trace "received ".$response->status_line;

        my $content = '';
        if($ct =~ m,[/+]xml$,i)
        {   # HTTP::Message::decoded_content() does not work for old Perls
            $content = $] >= 5.008 ? $response->decoded_content(ref => 1)
              : $response->content(ref => 1);
        }

        ($content, {});
      };
}

=ci_method headerAddVersions $header
Adds some lines about module versions, which may help debugging
or error reports.  This is called when a new client or server
is being created.
=cut

sub headerAddVersions($)
{   my ($thing, $h) = @_;
    foreach my $pkg (qw/XML::Compile XML::Compile::Cache
       XML::Compile::SOAP XML::LibXML LWP/)
    {   no strict 'refs';
        my $version = ${"${pkg}::VERSION"} || 'undef';
        (my $field = "X-$pkg-Version") =~ s/\:\:/-/g;
        $h->header($field => $version);
    }
}

1;
