use warnings;
use strict;

package XML::Compile::SOAP;

use Log::Report 'xml-compile-soap', syntax => 'SHORT';
use XML::Compile        qw//;
use XML::Compile::Util  qw/pack_type/;

=chapter NAME
XML::Compile::SOAP - base-class for SOAP implementations

=chapter SYNOPSIS
 **WARNING** Implementation not finished (but making
 ** progress): see STATUS statement below.

 use XML::Compile::SOAP11;
 use XML::Compile::Util qw/pack_type/;

 # There are quite some differences between SOAP1.1 and 1.2
 my $soap   = XML::Compile::SOAP11->new;

 # load extra schemas always explicitly
 $soap->schemas->importDefinitions(...);

 my $h1el = pack_type $myns, $some_element;
 my $b1el = "{$myns}$other_element";  # same, less clean

 # Request, answer, and call usually created via WSDL
 my $encode_query = $soap->compileMessage
   ( 'SENDER'
   , header   => [ h1 => $h1el ]
   , body     => [ b1 => $b1el ]
   , destination    => [ h1 => 'NEXT' ]
   , mustUnderstand => 'h1'
   , encodings => { b1 => { use => 'literal' }}
   );

 my $decode_response = $soap->compileMessage
   ( 'RECEIVER'
   , header    => [ h2 => $h2el ]
   , body      => [ b2 => $b2el ]
   , headerfault => [ ... ]
   , fault     => [ ... ]
   , encodings => { h2 => { use => 'literal' }}
   );

 my $http = XML::Compile::SOAP::HTTPClient->new(address => $server);

 # In nice, small steps:

 my @query    = (h1 => ..., b1 => ...);
 my $request  = $encode_query->($query);
 my $response = $http->($request);
 my $answer   = $decode_response->($resonse);
 use Data::Dumper;
 warn Dumper $answer;   # see: a HASH with h2 and b2!

 # Simplify your life

 my $call   = $soap->compileCall($encode_query, $decode_query, $http);
 my $result = $call->(h1 => ..., b1 => ...);
 print $result->{h2}->{...};
 print $result->{b2}->{...};

=chapter DESCRIPTION

This module handles the SOAP protocol.  The first implementation is
SOAP1.1 (F<http://www.w3.org/TR/2000/NOTE-SOAP-20000508/>), which is still
most often used.  The SOAP1.2 definition (F<http://www.w3.org/TR/soap12/>)
is quite different; this module tries to define a sufficiently abstract
interface to hide the protocol differences.

=section STATUS

On the moment, the following limitations exist:

=over 4
=item .
Only document/literal use is supported, not XML-RPC.

=item .
Faults and headerfaults not correctly processed.

=item .
No real-life tests yet.

=item .
No encoding.

=item .
Only SOAP1.1 sufficiently implemented (probably)

=item .
and so on...

=back

So: there is only a small chance that the current code works for you.

=chapter METHODS

=section Constructors

=method new OPTIONS
Create a new SOAP object.  You have to instantiate either the SOAP11 or
SOAP12 sub-class of this, because there are quite some differences (which
can be hidden for you)

=requires envelope_ns URI
=requires encoding_ns URI

=option   media_type MIMETYPE
=default  media_type C<application/soap+xml>

=option   schemas    C<XML::Compile::Schema> object
=default  schemas    created internally
Use this when you have already processed some schema definitions.  Otherwise,
you can add schemas later with C<< $soap->schames->importDefinitions() >>
=cut

sub new($@)
{   my $class = shift;
    error __x"you can only instantiate sub-classes of {class}"
        if $class eq __PACKAGE__;

    (bless {}, $class)->init( {@_} );
}

sub init($)
{   my ($self, $args) = @_;
    $self->{env}     = $args->{envelope_ns} || panic "no envelope namespace";
    $self->{enc}     = $args->{encoding_ns} || panic "no encoding namespace";
    $self->{mime}    = $args->{media_type}  || 'application/soap+xml';
    $self->{schemas} = $args->{schemas}     || XML::Compile::Schema->new;
    $self;
}

=section Accessors
=method envelopeNS
=method encodingNS
=cut

sub envelopeNS() {shift->{env}}
sub encodingNS() {shift->{enc}}

=method schemas
Returns the M<XML::Compile::Schema> object which contains the
knowledge about the types.
=cut

sub schemas()    {shift->{schemas}}

=method prefixPreferences TABLE
=cut

sub prefixPreferences($)
{   my ($self, $table) = @_;
    my %allns;
    my @allns  = @$table;
    while(@allns)
    {   my ($prefix, $uri) = splice @allns, 0, 2;
        $allns{$uri} = {uri => $uri, prefix => $prefix};
    }
    \%allns;
}

=section Single messages

=method compileMessage ('SENDER'|'RECEIVER'), OPTIONS
The payload is defined explicitly, where all headers and bodies are
specified as ARRAY containing key-value pairs (ENTRIES).  When you
have a WSDL file, these ENTRIES are generated automatically.

To make your life easy, the ENTRIES use a label (a free to choose key,
the I<part name> in WSDL terminology), to ease relation of your data with
the type where it belongs to.  The element of an entry (the value) is
defined as an C<any> element in the schema, and therefore you will need
to explicitly specify the element to be processed.

=option  header ENTRIES
=default header C<undef>
ARRAY of PAIRS, defining a nice LABEL (free of choice but unique)
and an element reference.  The LABEL will appear in the Perl HASH, to
refer to the element in a simple way.

=option  body   ENTRIES
=default body   []
ARRAY of PAIRS, defining a nice LABEL (free of choice but unique,
also w.r.t. the header and fault ENTRIES).  The LABEL will appear
in the Perl HASH only, to be able to refer to a body element in a
simple way.

=option  fault  ENTRIES
=default fault  []
The SOAP1.1 and SOAP1.2 protocols define fault entries in the
answer.  Both have a location to add your own additional
information: the type(-processor) is to specified here, but the
returned information structure is larger and differs per SOAP
implementation.

=option  mustUnderstand STRING|ARRAY-OF-STRING
=default mustUnderstand []
Writers only.  The specified header entry labels specify which elements
must be understood by the destination.  These elements will get the
C<mustUnderstand> attribute set to C<1> (soap1.1) or C<true> (soap1.2).

=option  destination ARRAY
=default destination []
Writers only.  Indicate who the target of the header entry is.
By default, the end-point is the destination of each header element.

The ARRAY contains a LIST of key-value pairs, specifing an entry label
followed by an I<actor> (soap1.1) or I<role> (soap1.2) URI.  You may use
the predefined actors/roles, like 'NEXT'.  See M<roleAbbreviation()>.

=option  role URI|ARRAY-OF-URI
=default role C<ULTIMATE>
Readers only.
One or more URIs, specifying the role(s) you application has in the
process.  Only when your role contains C<ULTIMATE>, the body is
parsed.  Otherwise, the body is returned as uninterpreted XML tree.
You should not use the role C<NEXT>, because every intermediate
node is a C<NEXT>.

All understood headers are parsed when the C<actor> (soap1.1) or
C<role> (soap1.2) attribute address the specified URI.  When other
headers emerge which are not understood but carry the C<mustUnderstood>
attribute, an fault is returned automatically.  In that case, the
call to the compiled subroutine will return C<undef>.

=option  roles ARRAY-OF-URI
=default roles []
Alternative for option C<role>

=option  encodings HASH-of-HASHes
=default encodings {}
Message components can be encoded, as defined in WSDL.   Typically, some
message part has a binding C<< use="encoded" >> and C<encodingStyle>
and C<namespace> parameters.  The encodings are organized per label.

=error an input message does not have faults
=error headerfault does only exist in SOAP1.1

=error option 'role' only for readers
=error option 'roles' only for readers
=error option 'destination' only for writers
=error option 'mustUnderstand' only for writers
=cut

sub compileMessage($@)
{   my ($self, $direction, %args) = @_;

      $direction eq 'SENDER'   ? $self->writer(\%args)
    : $direction eq 'RECEIVER' ? $self->reader(\%args)
    : error __x"message direction is 'SENDER' or 'RECEIVER', not {dir}"
         , dir => $direction;
}

#------------------------------------------------

=section Writer (internals)

=method writer ARGS
=cut

sub writer($)
{   my ($self, $args) = @_;

    die "ERROR: option 'role' only for readers"  if $args->{role};
    die "ERROR: option 'roles' only for readers" if $args->{roles};

    my $envns  = $self->envelopeNS;
    my $allns  = $self->prefixPreferences($args->{prefix_table} || []);

    # Translate message parts

    my ($header, $hlabels) = $self->writerCreateHeader
      ( $args->{header} || [], $allns
      , $args->{mustUnderstand}, $args->{destination}
      );

    my $headerhook = $self->writerHook($envns, 'Header', @$header);

    my ($body, $blabels) = $self->writerCreateBody
      ( $args->{body} || [], $allns );

    my ($fault, $flabels) = $self->writerCreateFault
      ( $args->{fault} || [], $allns
      , pack_type($envns, 'Fault')
      );

    my $bodyhook = $self->writerHook($envns, 'Body', @$body, @$fault);
    my $encstyle = $self->writerEncstyleHook($allns);

    #
    # Pack everything together in one procedure
    #

    my $envelope = $self->schemas->compile
     ( WRITER => pack_type($envns, 'Envelope')
     , hooks  => [ $encstyle, $headerhook, $bodyhook ]
     , output_namespaces    => $allns
     , elements_qualified   => 1
     , attributes_qualified => 1
     );

    sub { my ($values, $charset) = @_;
          my $doc = XML::LibXML::Document->new('1.0', $charset);
          my %data = %$values;  # do not destroy the calling hash

          $data{Header}{$_} = delete $data{$_} for @$hlabels;
          $data{Body}{$_}   = delete $data{$_} for @$blabels, @$flabels;
          $envelope->($doc, \%data);
        };
}

=method writerHook NAMESPACE, LOCAL, ACTIONS
=cut

sub writerHook($$@)
{   my ($self, $ns, $local, @do) = @_;
 
   +{ type    => pack_type($ns, $local)
    , replace =>
         sub { my ($doc, $data, $path, $tag) = @_;
               my %data = %$data;
               my @h = @do;
               my @childs;
               while(@h)
               {   my ($k, $c) = (shift @h, shift @h);
                   if(my $v = delete $data{$k})
                   {    my $g = $c->($doc, $v);
                        push @childs, $g if $g;
                   }
               }
               warn "ERROR: unused values @{[ keys %data ]}\n"
                   if keys %data;

               @childs or return ();
               my $node = $doc->createElement($tag);
               $node->appendChild($_) for @childs;
               $node;
             }
    };
}

=method writerEncstyleHook NAMESPACE-TABLE
=cut

sub writerEncstyleHook($)
{   my ($self, $allns) = @_;
    my $envns   = $self->envelopeNS;
    my $style_w = $self->schemas->compile
     ( WRITER => pack_type($envns, 'encodingStyle')
     , output_namespaces    => $allns
     , include_namespaces   => 0
     , attributes_qualified => 1
     );
    my $style;

    my $before  = sub {
	my ($doc, $values, $path) = @_;
        ref $values eq 'HASH' or return $values;
        $style = $style_w->($doc, delete $values->{encodingStyle});
        $values;
      };

    my $after = sub {
        my ($doc, $node, $path) = @_;
        $node->addChild($style) if defined $style;
        $node;
      };

   { before => $before, after => $after };
}

=method writerCreateHeader HEADER-DEFS, NS-TABLE, UNDERSTAND, DESTINATION
=cut

sub writerCreateHeader($$$$)
{   my ($self, $header, $allns, $understand, $destination) = @_;
    my (@rules, @hlabels);
    my $schema      = $self->schemas;
    my %destination = ref $destination eq 'ARRAY' ? @$destination : ();

    my %understand  = map { ($_ => 1) }
        ref $understand eq 'ARRAY' ? @$understand
      : defined $understand ? "$understand" : ();

    my @h = @$header;
    while(@h)
    {   my ($label, $element) = splice @h, 0, 2;

        my $code = $schema->compile
           ( WRITER => $element
           , output_namespaces  => $allns
           , include_namespaces => 0
           , elements_qualified => 'TOP'
           );

        push @rules, $label => $self->writerHeaderEnv($code, $allns
           , delete $understand{$label}, delete $destination{$label});

        push @hlabels, $label;
    }

    keys %understand
        and error __x"mustUnderstand for unknown header {headers}"
                , headers => [keys %understand];

    keys %destination
        and error __x"actor for unknown header {headers}"
                , headers => [keys %destination];

    (\@rules, \@hlabels);
}

=method writerCreateBody BODY-DEFS, NAMESPACE-TABLE
=cut

sub writerCreateBody($$)
{   my ($self, $body, $allns) = @_;
    my (@rules, @blabels);
    my $schema = $self->schemas;
    my @b      = @$body;
    while(@b)
    {   my ($label, $element) = splice @b, 0, 2;

        my $code = $schema->compile
           ( WRITER => $element
           , output_namespaces  => $allns
           , include_namespaces => 0
           , elements_qualified => 'TOP'
           );

        push @rules, $label => $code;
        push @blabels, $label;
    }

    (\@rules, \@blabels);
}

=method writerCreateFault FAULT-DEFS, NAMESPACE-TABLE, FAULTTYPE
=cut

sub writerCreateFault($$$)
{   my ($self, $faults, $allns, $faulttype) = @_;
    my (@rules, @flabels);
    my $schema = $self->schemas;
    my @f      = @$faults;

    while(@f)
    {   my ($label, $type) = splice @f, 0, 2;
        my $details = $schema->compile
          ( WRITER => $type
          , output_namespaces  => $allns
          , include_namespaces => 0
          );

        my $fault = $schema->compile
         ( WRITER => $faulttype
         , output_namespaces  => $allns
         , include_namespaces => 0
         , elements_qualified => 'TOP'
         );

        my $code = sub
         { my $doc  = shift;
           my $data = $self->writerConvertFault($type, shift);
           $data->{$type} = $details->(delete $data->{details});
           $fault->($doc, $data);
         };

        push @rules, $label => $code;
        push @flabels, $label;
    }

    (\@rules, \@flabels);
}

=method writerConvertFault NAME, DATA
The fault data can be provided in SOAP1.1 or SOAP1.2 format, or even
both mixed.  The data structure is transformed to fit the used
protocol level.  See L<DETAILS/Faults>.
=cut

#------------------------------------------------

=section Reader (internals)

=method reader ARGS
=cut

sub reader($)
{   my ($self, $args) = @_;

    die "ERROR: option 'destination' only for writers"
        if $args->{destination};

    die "ERROR: option 'mustUnderstand' only for writers"
        if $args->{understand};

    my $schema = $self->schemas;
    my $envns  = $self->envelopeNS;

#   my $roles  = $args->{roles} || $args->{role} || 'ULTIMATE';
#   my @roles  = ref $roles eq 'ARRAY' ? @$roles : $roles;

    my $header = $self->readerParseHeader($args->{header} || []);
    my $body   = $self->readerParseBody($args->{body} || []);

    my $headerhook = $self->readerHook($envns, 'Header', @$header);
    my $bodyhook   = $self->readerHook($envns, 'Body', @$body);
    my $encstyle   = $self->readerEncstyleHook;

    my $envelope = $self->schemas->compile
     ( READER => pack_type($envns, 'Envelope')
     , hooks  => [ $encstyle, $headerhook, $bodyhook ]
     );

    sub { my $xml   = shift;
          my $data  = $envelope->($xml);
          my @pairs = ( %{delete $data->{Header} || {}}
                      , %{delete $data->{Body}   || {}});
          while(@pairs)
          {  my $k       = shift @pairs;
             $data->{$k} = shift @pairs;
          }
          $data;
        }
}

=method readerHook NAMESPACE, LOCAL, ACTIONS
=cut

sub readerHook($$@)
{   my ($self, $ns, $local, @do) = @_;
    my %trans = map { ($_->[1] => [ $_->[0], $_->[2] ]) } @do; # we need copies
 
   +{ type    => pack_type($ns, $local)
    , replace =>
        sub
          { my ($xml, $trans, $path, $label) = @_;
            my %h;
            foreach my $child ($xml->childNodes)
            {   next unless $child->isa('XML::LibXML::Element');
                my $type = pack_type $child->namespaceURI, $child->localName;
                if(my $t = $trans{$type})
                {   my $v = $t->[1]->($child);
                    $h{$t->[0]} = $v if defined $v;
                }
                else
                {   $h{$type} = $child;
                }
            }
            ($label => \%h);
          }
    };
}

=method readerParseHeader HEADERDEF
=cut

sub readerParseHeader($)
{   my ($self, $header) = @_;
    my @rules;

    my $schema = $self->schemas;
    my @h      = @$header;
    while(@h)
    {   my ($label, $element) = splice @h, 0, 2;
        push @rules, [$label, $element, $schema->compile(READER => $element)];
    }

    \@rules;
}

=method readerParseBody BODYDEF
=cut

sub readerParseBody($)
{   my ($self, $body) = @_;
    my @rules;

    my $schema = $self->schemas;
    my @b      = @$body;
    while(@b)
    {   my ($label, $element) = splice @b, 0, 2;
        push @rules, [$label, $element, $schema->compile(READER => $element)];
    }

    \@rules;
}

=method readerEncstyleHook
=cut

sub readerEncstyleHook()
{   my $self     = shift;
    my $envns    = $self->envelopeNS;
    my $style_r = $self->schemas->compile
      (READER => pack_type($envns, 'encodingStyle'));  # is attribute

    my $encstyle;  # yes, closures!

    my $before = sub
      { my ($xml, $path) = @_;
        if(my $attr = $xml->getAttributeNode('encodingStyle'))
        {   $encstyle = $style_r->($attr, $path);
            $xml->removeAttribute('encodingStyle');
        }
        $xml;
      };

   my $after   = sub
      { defined $encstyle or return $_[1];
        my $h = $_[1];
        ref $h eq 'HASH' or $h = { _ => $h };
        $h->{encodingStyle} = $encstyle;
        $h;
      };

   { before => $before, after => $after };
}

=method roleAbbreviation STRING
Translates actor/role/destination abbreviations into URIs. Various
SOAP protocol versions have different pre-defined URIs, which can
be abbreviated for readibility.  Returns the unmodified STRING in
all other cases.
=cut

sub roleAbbreviation($) { panic "not implemented" }

#------------------------------------------------

=chapter DETAILS

=section Do it yourself, no WSDL

Does this all look too complicated?  It isn't that bad.  The following
example is used as test-case t/82soap11.t, directly taken from the SOAP11
specs section 1.3 example 1.

 # for simplification
 my $TestNS   = 'http://test-types';
 my $SchemaNS = 'http://www.w3.org/2001/XMLSchema';

First, the schema (hopefully someone else created for you, because they
can be quite hard to create correctly) is in file C<myschema.xsd>

 <schema targetNamespace="$TestNS"
   xmlns="$SchemaNS">

 <element name="GetLastTradePrice">
   <complexType>
      <all>
        <element name="symbol" type="string"/>
      </all>
   </complexType>
 </element>

 <element name="GetLastTradePriceResponse">
   <complexType>
      <all>
         <element name="price" type="float"/>
      </all>
   </complexType>
 </element>

 <element name="Transaction" type="int"/>
 </schema>

Ok, now the program you create the request:

 use XML::Compile::SOAP11;
 use XML::Compile::Util  qw/pack_type/;

 my $soap   = XML::Compile::SOAP11->new;
 $soap->schemas->importDefinitions('myschema.xsd');

 my $get_price = $soap->compileMessage
   ( 'SENDER'
   , header =>
      [ transaction => pack_type($TestNS, 'Transaction') ]
   , body  =>
      [ request => pack_type($TestNS, 'GetLastTradePrice') ]
   , mustUnderstand => 'transaction'
   , destination    => [ transaction => 'NEXT http://actor' ]
   );

C<INPUT> is used in the WSDL terminology, indicating this message is
an input message for the server.  This C<$get_price> is a WRITER.  Above
is done only once in the initialization phase of your program.

At run-time, you have to call the CODE reference with a
data-structure which is compatible with the schema structure.
(See M<XML::Compile::Schema::template()> if you have no clue how it should
look)  So: let's send this:

 # insert your data
 my %data_in =
  ( transaction => 5
  , request     => {symbol => 'DIS'}
  );

 # create a XML::LibXML tree
 my $xml  = $get_price->(\%data_in, 'UTF-8');
 print $xml->toString;

And the output is:

 <SOAP-ENV:Envelope
    xmlns:x0="http://test-types"
    xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/">
   <SOAP-ENV:Header>
     <x0:Transaction
       mustUnderstand="1"
       actor="http://schemas.xmlsoap.org/soap/actor/next http://actor">
         5
     </x0:Transaction>
   </SOAP-ENV:Header>
   <SOAP-ENV:Body>
     <x0:GetLastTradePrice>
       <symbol>DIS</symbol>
     </x0:GetLastTradePrice>
   </SOAP-ENV:Body>
 </SOAP-ENV:Envelope>

Some transport protocol will sent this data from the client to the
server.  See M<XML::Compile::SOAP::HTTPClient>, as one example.

On the SOAP server side, we will parse the message.  The string C<$soap>
contains the XML.  The program looks like this:

 my $server = $soap->compileMessage # create once
  ( 'RECEIVER'
  , header => [ transaction => pack_type($TestNS, 'Transaction') ]
  , body   => [ request => pack_type($TestNS, 'GetLastTradePrice') ]
  );

 my $data_out = $server->($soap);   # call often

Now, the C<$data_out> reference on the server, is stucturally exactly 
equivalent to the C<%data_in> from the client.

=section Encodings

=section Faults
It is quite simple to produce a WSDL file which is capable of handling
SOAP1.1 and SOAP1.2 protocols with the same messages.  However, when
faults are being generated, then differences show up. Therefore,
M<writerConvertFault()> is used to hide the differences.
=cut

1;
