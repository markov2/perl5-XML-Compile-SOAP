use warnings;
use strict;

package XML::Compile::SOAP::Server;

use Log::Report 'xml-compile-soap', syntax => 'SHORT';

=chapter NAME
XML::Compile::SOAP::Server - base class for SOAP message servers

=chapter SYNOPSIS
 # never used directly.

=chapter DESCRIPTION
This base class defines the method that each server side of the SOAP
message exchange protocols must implement.

The commonatities on the level of options to the methods is not yet known,
where there is only one transport implementation available on the moment:
M<XML::Compile::SOAP::HTTPServer>, for transport over HTTP.

=chapter METHODS

=c_method new OPTIONS
Compile a server handler.
=cut

sub new(@) { panic "protocol server not implemented" }
sub init($) { shift }

1;
