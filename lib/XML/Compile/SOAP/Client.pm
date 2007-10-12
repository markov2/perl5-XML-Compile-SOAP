use warnings;
use strict;

package XML::Compile::SOAP::Client;

use Log::Report 'xml-compile-soap', syntax => 'SHORT';

=chapter NAME
XML::Compile::SOAP::Client - SOAP message initiators

=chapter SYNOPSIS
 # never used directly.

=chapter DESCRIPTION
This class defines the methods that each client side of the SOAP
message exchange protocols must implement.

=chapter METHODS

=section Instantiation
This object can not be instantiated, but is only used as secundary
base class.  The primary must contain the C<new>.
=cut

sub new(@) { panic __PACKAGE__." only secundary in multiple inheritance" }
sub init($) { shift }

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
