use warnings;
use strict;

package XML::Compile::SOAP12::Server;
use base 'XML::Compile::SOAP12', 'XML::Compile::SOAP::Server';

use Log::Report 'xml-compile-soap', syntax => 'SHORT';

=chapter NAME
XML::Compile::SOAP12::Server - SOAP1.2 server needs

=chapter SYNOPSIS

=chapter DESCRIPTION
Thos module does not implement an actual soap server daemon, but the
needs to create the server side.  The server daemon is implemented
by M<XML::Compile::SOAP::Daemon>.

=chapter METHODS

=method prepareServer SERVER
=cut

sub prepareServer($)
{   my ($self, $server) = @_;
}

1;
