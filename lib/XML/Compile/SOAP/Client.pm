use warnings;
use strict;

package XML::Compile::SOAP::Client;

use Log::Report 'xml-compile-soap', syntax => 'SHORT';

=chapter NAME
XML::Compile::SOAP::Client - base class for SOAP message clients

=chapter SYNOPSIS
 # never used directly.

=chapter DESCRIPTION
This base class defines the method that each client side of the SOAP
message exchange protocols must implement.

The commonatities on the level of options to the methods is not yet known,
where there is only one transport implementation available on the moment:
M<XML::Compile::SOAP::HTTPClient>, for transport over HTTP.

=chapter METHODS

=c_method new OPTIONS
Compile a client handler.
=cut

sub new(@) { panic "protocol client not implemented" }
sub init($) {shift}

1;
