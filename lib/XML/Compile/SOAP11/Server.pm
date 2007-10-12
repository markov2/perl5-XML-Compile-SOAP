use warnings;
use strict;

package XML::Compile::SOAP11::Server;
use base 'XML::Compile::SOAP11', 'XML::Compile::SOAP::Server';

use Log::Report 'xml-compile-soap', syntax => 'SHORT';

=chapter NAME
XML::Compile::SOAP11::Server - SOAP1.1 server needs

=chapter SYNOPSIS

=chapter DESCRIPTION
This module does not implement an actual soap server, but the
needs to create the server side.  The server daemon is implemented
by M<XML::Compile::SOAP::Daemon>

=chapter METHODS

=method prepareServer SERVER
The SERVER is a M<XML::Compile::SOAP::HTTPServer> object, which will
need some messages prepared for general purpose.
=cut

sub prepareServer($)
{   my ($self, $server) = @_;
}

1;
