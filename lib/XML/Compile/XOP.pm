use warnings;
use strict;

package XML::Compile::XOP;

use Log::Report 'xml-compile-soap', syntax => 'SHORT';
use XML::Compile::SOAP::Util   qw/:xop10/;
use XML::Compile::XOP::Include ();

XML::Compile->addSchemaDirs(__FILE__);
XML::Compile->knownNamespace
  ( &XMIME10   => '200411-xmlmime.xsd'
  , &XMIME11   => '200505-xmlmime.xsd'
  );

=chapter NAME
XML::Compile::XOP - MTOM and XOP handler

=chapter SYNOPSIS

  # by default, XML::Compile encodes binary data
  my $answer    = $call->(image => $binary_image);

  # to enable use of MTOM
  use XML::Compile::XOP;
  my $xop       = XML::Compile::XOP->new;
  my $xop_image = $xop->bytes($binary_image);
  my $answer    = $call->(image => $xop_image);

  # returned XOPs in SOAP
  my ($answer, $trace, $xop) = $wsdl->call($operation)->(%data);

=chapter DESCRIPTION
The SOAP Message Transmission Optimization Mechanism (MTOM) is designed
for SOAP1.2, but also usable for SOAP1.1.  It optimizes the transport of
binary information (like images) which are part of the XML message: in
stead of base64 encoding them adding 25% to the size of the data, these
binaries are added as pure binary attachment to the SOAP message.

In the official specification, the XML message will be created first
with the base64 representation of the data in it. Only at transmission,
a preprocessor XOP (XML-binary Optimized Packaging) extracts those
components to be send separately.  In Perl, we have to be more careful
about performance.  Therefore, the path via encoding to base64 and then
decoding it back to binary in the sender (and the reverse process for
the receiver) is avoided.

=chapter METHODS

=section Constructors

=c_method new %options

=option  xmlmime_version URI
=default xmlmime_version XMIME11

=option  xop_version     URI
=default xop_version     XOP10

=option  hostname        STRING
=default hostname        'localhost'
This is used as part of generated Content-IDs, which have the form of
a email address.
=cut

sub new(@) { my $class = shift; (bless {})->init( {@_} ) }

sub init($)
{   my ($self, $args) = @_;

    $self->{XCX_xmime} = $args->{xmlmime_version} || XMIME11;
    $self->{XCX_xop}   = $args->{xop_version}     || XOP10;
    $self->{XCX_host}  = $args->{hostname}        || 'localhost';
    $self->{XCX_cid}   = time;
    $self;
}

=method file <$filename|$fh>, %options
Create a M<XML::Compile::XOP::Include> object which sources from a
FILE specified by NAME or HANDLE.  With the %options, you can overrule
defaults generated for the "Include" object.

=example use of file()
  use MIME::Types;
  my $mimetypes = MIME::Types->new;

  my $type = $mimetypes->mimeTypeOf($fn);
  my $data = $xop->file($fn, type => $fn);
  # $data is a XML::Compile::XOP::Include

=method bytes <STRING|SCALAR>, %options
Create a M<XML::Compile::XOP::Include> object which sources from a
STRING (representing bytes) or a SCALAR reference to such a string.
With the %options, you can overrule defaults generated for the "Include"
object.

=example use of bytes()
  my $data = $xop->bytes($string, type => 'text/html');
  # $data is a XML::Compile::XOP::Include
=cut

sub _include(@)
{   my $self = shift;
    XML::Compile::XOP::Include->new
      ( cid   => $self->{XCX_cid}++ . '@' . $self->{XCX_host}
      , xmime => $self->{XCX_xmime}
      , xop   => $self->{XCX_xop}
      , type  => 'application/octet-stream'
      , @_
      );
}
sub file(@)  { my $self = shift; $self->_include(file  => @_) }
sub bytes(@) { my $self = shift; $self->_include(bytes => @_) }

=chapter DETAILS

=chapter SEE ALSO
=over 4
=item MTOM SOAP1.2: F<http://www.w3.org/TR/soap12-mtom/>
=item MTOM SOAP1.1: F<http://schemas.xmlsoap.org/soap/mtom/SOAP11MTOM10.pdf>
=item XOP: F<http://www.w3.org/TR/xop10/>
=item XMLMIME: F<http://www.w3.org/TR/xml-media-types>
=back

=cut

1;
