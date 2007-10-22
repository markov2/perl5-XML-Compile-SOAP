use warnings;
use strict;

package XML::Compile::SOAP::Server;

use Log::Report 'xml-compile-soap', syntax => 'SHORT';

=chapter NAME
XML::Compile::SOAP::Server - SOAP message handlers

=chapter SYNOPSIS
 # never used directly.

=chapter DESCRIPTION
This class defines methods that each server side of the SOAP
message exchange protocols must implement.

=chapter METHODS

=section Instantiation
This object can not be instantiated, but is only used as secundary
base class.  The primary must contain the C<new>.
=cut

sub new(@) { panic __PACKAGE__." only secundary in multiple inheritance" }
sub init($) { shift }

1;
