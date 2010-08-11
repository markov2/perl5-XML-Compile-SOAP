use warnings;
use strict;

package XML::Compile::SOAP10;
use base 'XML::Compile::SOAP';

use Log::Report 'xml-compile-soap', syntax => 'SHORT';
use XML::Compile::Util       qw/pack_type unpack_type SCHEMA2001/;
use XML::Compile::SOAP::Util qw/:soap11/;

use XML::Compile::SOAP10::Operation ();
use XML::Compile::SOAP11;  # for schemas

=chapter NAME
XML::Compile::SOAP10 - SOAP11 HTTP-GET/POST

=chapter SYNOPSIS
 # See XML::Compile::SOAP for global usage examples.

=chapter DESCRIPTION
WSDL 1.1 defines HTTP-GET and HTTP-POST bindings, which are nowhere
described (as far as I know). So, it is unclear where they came from.
Probably from the time before SOAP 1.1.  For simplicity, I name this
SOAP 1.0.  There is B<no SOAP 1.0> standard.

=chapter METHODS

=section Constructors

=method new OPTIONS
=cut

sub new($@)
{   my $class = shift;
    error __x"I have no idea how SOAP pure HTTP-GET and -POST are supposed to work. Please show me the spec";
}

1;
