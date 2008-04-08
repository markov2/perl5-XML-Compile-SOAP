use warnings;
use strict;

package XML::Compile::SOAP::Util;
use base 'Exporter';

my @soap11 = qw/SOAP11ENV SOAP11ENC SOAP11NEXT SOAP11HTTP/;
my @soap12 = qw/SOAP12ENV SOAP12ENC SOAP12RPC
  SOAP12NONE SOAP12NEXT SOAP12ULTIMATE/;
my @wsdl11 = qw/WSDL11 WSDL11SOAP WSDL11HTTP WSDL11MIME WSDL11SOAP12/;
my @daemon = qw/MSEXT/;

our @EXPORT_OK = (@soap11, @soap12, @wsdl11, @daemon);
our %EXPORT_TAGS =
  ( soap11 => \@soap11
  , soap12 => \@soap12
  , wsdl11 => \@wsdl11
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

On the moment, only a long list of constant URIs are exported on
the moment.

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
The export TAG C<:soap12> groups the SOAP version 1.2 related exported
constants C<SOAP12ENV>, C<SOAP12ENC>, C<SOAP12RPC>, and role abbreviations
C<SOAP12NONE>, C<SOAP12NEXT>, C<SOAP12ULTIMATE>.

=cut

use constant SOAP12         => 'http://www.w3c.org/2003/05/';
use constant SOAP12ENV      => SOAP12. 'soap-envelope';
use constant SOAP12ENC      => SOAP12. 'soap-encoding';
use constant SOAP12RPC      => SOAP12. 'soap-rpc';

use constant SOAP12NONE     => SOAP12ENV.'/role/none';
use constant SOAP12NEXT     => SOAP12ENV.'/role/next';
use constant SOAP12ULTIMATE => SOAP12ENV.'/role/ultimateReceiver';

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
