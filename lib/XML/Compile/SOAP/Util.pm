use warnings;
use strict;

package XML::Compile::SOAP::Util;
use base 'Exporter';

my @soap11 = qw/SOAP11ENV SOAP11ENC SOAP11NEXT SOAP11HTTP WSDL11SOAP/;
my @wsdl11 = qw/WSDL11 WSDL11SOAP WSDL11HTTP WSDL11MIME WSDL11SOAP12/;
my @http   = qw/SOAP11HTTP WSDL11HTTP SOAP11ENV/;
my @daemon = qw/MSEXT/;

our @EXPORT_OK = (@soap11, @wsdl11, @http, @daemon);
our %EXPORT_TAGS =
  ( soap11 => \@soap11
  , wsdl11 => \@wsdl11
  , http   => \@http
  , daemon => \@daemon
  );

=chapter NAME
XML::Compile::SOAP::Util - general purpose routines for XML::Compile::SOAP

=chapter SYNOPSYS
 use XML::Compile::SOAP::Util qw/:soap11 WSDL11/;

=chapter DESCRIPTION
This module collects functions which are useful on many places in the
SOAP implemention, just as M<XML::Compile::Util> does for general XML
implementations (often you will needs things from both).

On the moment, only a long list of constant URIs are exported.

=chapter FUNCTIONS

=section Constants
The export TAG C<:soap11> groups the SOAP version 1.1 related exported
constants C<SOAP11ENV>, C<SOAP11ENC>, actor C<SOAP11NEXT>, and http
indicator C<SOAP11HTTP>.

=cut

use constant SOAP11         => 'http://schemas.xmlsoap.org/soap/';
use constant SOAP11ENV      => SOAP11. 'envelope/';
use constant SOAP11ENC      => SOAP11. 'encoding/';
use constant SOAP11NEXT     => SOAP11. 'actor/next';
use constant SOAP11HTTP     => SOAP11. 'http';

=pod
The export TAG C<:wsdl11> groups the exported WSDL version 1.1 related
constants C<WSDL11>, C<WSDL11SOAP>, C<WSDL11HTTP>, C<WSDL11MIME>,
C<WSDL11SOAP12>.

=cut

use constant WSDL11         => 'http://schemas.xmlsoap.org/wsdl/';
use constant WSDL11SOAP     => WSDL11. 'soap/';
use constant WSDL11HTTP     => WSDL11. 'http/';
use constant WSDL11MIME     => WSDL11. 'mime/';
use constant WSDL11SOAP12   => WSDL11. 'soap12/';
 
=pod
The export TAG C<:daemon> refers currently only to the constant C<MSEXT>,
which refers to the MicroSoft Extension Framework namespace.

=cut

use constant MSEXT          => SOAP11ENV;

1;
