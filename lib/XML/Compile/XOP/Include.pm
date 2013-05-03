use warnings;
use strict;

package XML::Compile::XOP::Include;

use Log::Report 'xml-compile-soap', syntax => 'SHORT';
use XML::Compile::SOAP::Util qw/:xop10/;
use HTTP::Message            ();
use File::Slurp              qw/read_file write_file/;

=chapter NAME
XML::Compile::XOP::Include - Represents one XOP node.

=chapter SYNOPSIS

  # See also SYNOPSIS of XML::Compile::XOP
  my $xop       = XML::Compile::XOP->new;
  my $xop_image = $xop->bytes($binary_image);
  my $answer    = $call->(image => $xop_image);

=chapter DESCRIPTION
Represents one data-set which will be represented as separate (binary)
object during transport.  This can only be used on data fields which
are base64Binary.

YOU SHOULD NOT instantiate this kind of objects directly, but use the
M<XML::Compile::XOP> method to create them.

The object is overloaded to produce the contained data when a scalar is
required, for instance when you call functions like "length".  This means
that, hopefully, the end-user does not see much of a difference between
data which is transported inline or packaged separately.

=chapter OVERLOAD

=overload "" (stringification)

This object stringifies to its binary content.

=cut

use overload '""'     => 'content'
           , fallback => 1;

=chapter METHODS

=section Constructors

=c_method new OPTIONS
You have to specify either a C<file> or C<byte> source.  Otherwise, the
constructor will return C<undef>.

=option  file FILENAME|FILEHANDLE
=default file C<undef>
Take the data from the specified file.

=option  bytes STRING|SCALAR
=default bytes C<undef>
Take the data from a STRING of reference.

=requires cid   STRING
The Content-ID of the binary attachment.

=requires type MIMETYPE
The MIME-Type of the data.

=requires xmime VERSION
=requires xop   VERSION
=cut

sub new(@)
{   my ($class, %args) = @_;
    $args{bytes} = \(delete $args{bytes})
        if defined $args{bytes} && ref $args{bytes} ne 'SCALAR';
    bless \%args, $class;
}

=c_method fromMime OBJECT
Collect the data from a M<HTTP::Message> object.
=cut

sub fromMime($)
{   my ($class, $http) = @_;

    my $cid = $http->header('Content-ID') || '<NONE>';
    if($cid !~ s/^\s*\<(.*?)\>\s*$/$1/ )
    {   warning __x"part has illegal Content-ID: `{cid}'", cid => $cid;
        return ();
    }

    my $content = $http->decoded_content(ref => 1) || $http->content(ref => 1);
    $class->new
     ( bytes => $content
     , cid   => $cid
     , type  => scalar $http->content_type
     );
}

=section Accessors

=method cid
Returns the Content-ID.
=cut

sub cid { shift->{cid} }

=method content [BYREF]
Returns the content, when BYREF (boolean) is true, then the value is
returned by reference.
=cut

sub content(;$)
{   my ($self, $byref) = @_;
    unless($self->{bytes})
    {   my $f     = $self->{file};
        my $bytes = try { read_file $f };
        fault "failed reading XOP file {fn}", fn => $f;
        $self->{bytes} = \$bytes;
    }
    $byref ? $self->{bytes} : ${$self->{bytes}};
}

=section Processing

=method xmlNode DOCUMENT, PATH, TAG
The DOCUMENT will be used to construct the node from.  The PATH
is an indicator for the location of the node within the data
structure (used in error messages).  The TAG is the prefixed name
for the node to be created.

Returned is an XML node to be included in the output tree.
=cut

sub xmlNode($$$$)
{   my ($self, $doc, $path, $tag) = @_;
    my $node = $doc->createElement($tag);
    $node->setNamespace($self->{xmime}, 'xmime', 0);
    $node->setAttributeNS($self->{xmime}, contentType => $self->{type});

    my $include = $node->addChild($doc->createElement('Include'));
    $include->setNamespace($self->{xop}, 'xop', 1);
    $include->setAttribute(href => 'cid:'.$self->{cid});
    $node;
}

=method mimePart [HEADERS]
Produce the message part which contains a normal mime representation
of a binary file.  You may provide an initial HEADERS (M<HTTP::Headers>)
object, or an ARRAY of headers to instantiate such an object.
=cut

sub mimePart(;$)
{   my ($self, $headers) = @_;
    my $mime = HTTP::Message->new($headers);
    $mime->header
      ( Content_Type => $self->{type}
      , Content_Transfer_Encoding => 'binary'
      , Content_ID   => '<'.$self->{cid}.'>'
      );

    $mime->content_ref($self->content(1));
    $mime;
}

=method write FILENAME|FILEHANDLE
Write the content to the specified FILE.
=cut

sub write($)
{   my ($self, $file) = @_;
    write_file $file, {binmode => ':raw'}, $self->content(1);
}

1;
