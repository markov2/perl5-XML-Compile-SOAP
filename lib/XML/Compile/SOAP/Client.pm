use warnings;
use strict;

package XML::Compile::SOAP::Client;

use Log::Report 'xml-compile-soap', syntax => 'SHORT';

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

#------------------------------------------------

=section Single messages

=method compileClient OPTIONS
Combine sending a request, and receiving the answer.  In LIST context,
both the decoded answer, as a HASH with various trace information is
returned.  In SCALAR context, only the answer is given.

=option  kind STRING
=default kind 'request-response'
Four kinds of message exchange are defined in WSDL terminology:
C<request-response>, C<notification-operation>, C<one-way>, and
C<solicit-response>.  Only the first one is supported on the moment.

=requires request   CODE
=requires response  CODE
=requires transport CODE
=cut

sub compileCall(@)
{   my ($self, %args) = @_;

    my $kind = $args{kind} || 'request-response';
    $kind eq 'request-response'
        or error __x"soap call type {kind} not supported", kind => $kind;

    my $encode = $args{request}
        or error __x"call requires a request encoder";

    my $decode = $args{response}
        or error __x"call requires a response decoder";

    my $transport = $args{transport}
        or error __x"call requires a transport handler";

    sub
    { my $request  = $encode->(@_);
      my ($response, $trace) = $transport->($request);
      my $answer   = $decode->($response);
      wantarray ? ($answer, $trace) : $answer;
    };
}

#------------------------------------------------

=section Debugging

=ci_method fakeServer [FAKE|undef]
Returns the fake server, if defined: it will be called to simulate
an external SOAP server.  Use this for debugging and regression test
scripts.

Usually, you should set your own FAKE server, but simply instantiate
a M<XML::Compile::SOAP::Tester> object.

BE WARNED: this FAKE server must be instantiated B<before> the
SOAP client handlers are compiled.
=cut

my $fake_server;
sub fakeServer()
{   return $fake_server if @_==1;

    my $server = $_[1];
    defined $server
        or return $fake_server = undef;

    ref $server && $server->isa('XML::Compile::SOAP::Tester')
        or error __x"fake server isn't a XML::Compile::SOAP::Tester";

    $fake_server = $server;
}


1;
