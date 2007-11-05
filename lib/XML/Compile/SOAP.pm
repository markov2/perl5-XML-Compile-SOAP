use warnings;
use strict;

package XML::Compile::SOAP;

use Log::Report 'xml-compile-soap', syntax => 'SHORT';
use XML::Compile        ();
use XML::Compile::Util  qw/pack_type unpack_type/;

=chapter NAME
XML::Compile::SOAP - base-class for SOAP implementations

=chapter SYNOPSIS
 ** WARNING: Implementation not finished (but making progress)
 ** see README.todo in distribution!!!

 use XML::Compile::SOAP11::Client;
 use XML::Compile::Util qw/pack_type/;

 # There are some (hidden) differences between SOAP1.1 and 1.2
 my $client = XML::Compile::SOAP11::Client->new;

 # load extra schemas always explicitly
 $client->schemas->importDefinitions(...);

 # !!! THE NEXT STEPS ARE ONLY REQUIRED WHEN YOU DO NOT HAVE A WSDL
 # !!! SEE XML::Compile::WSDL11 IF YOU HAVE A WSDL FILE
 
 my $h1el = pack_type $myns, $some_element;
 my $b1el = "{$myns}$other_element";  # same, less clean

 my $encode_query = $client->compileMessage
   ( 'SENDER'
   , header   => [ h1 => $h1el ]
   , body     => [ b1 => $b1el ]
   , destination    => [ h1 => 'NEXT' ]
   , mustUnderstand => 'h1'
   , encodings => { b1 => { use => 'literal' }}
   );

 my $decode_response = $client->compileMessage
   ( 'RECEIVER'
   , header    => [ h2 => $h2el ]
   , body      => [ b2 => $b2el ]
   , faults    => [ ... ]
   , encodings => { h2 => { use => 'literal' }}
   );

 my $http = XML::Compile::SOAP::HTTPClient->new
   ( action  => 'http://...'
   , address => $server
   );

 # In nice, small steps:

 my @query    = (h1 => ..., b1 => ...);
 my $request  = $encode_query->($query);
 my ($response, $trace) = $http->($request);
 my $answer   = $decode_response->($response);
 use Data::Dumper;
 warn Dumper $answer;     # see: a HASH with h2 and b2!
 if($answer->{Fault}) ... # error

 # Simplify your life

 my $call   = $client->compileClient
   ( kind      => 'request-response'
   , request   => $encode_query
   , response  => $decode_response
   , transport => $http
   );

 my $result = $call->(h1 => ..., b1 => ...);
 print $result->{h2}->{...};
 print $result->{b2}->{...};

 my ($result, $trace) = $call->(...);

=chapter DESCRIPTION

This module handles the SOAP protocol.  The first implementation is
SOAP1.1 (F<http://www.w3.org/TR/2000/NOTE-SOAP-20000508/>), which is still
most often used.  The SOAP1.2 definition (F<http://www.w3.org/TR/soap12/>)
is quite different; this module tries to define a sufficiently abstract
interface to hide the protocol differences.

On the moment, B<XML-RPC is not supported>.  There are many more limitations,
which can be found in the README.todo file which is part of the
distribution package.

=chapter METHODS

=section Constructors

=method new OPTIONS
Create a new SOAP object.  You have to instantiate either the SOAP11 or
SOAP12 sub-class of this, because there are quite some differences (which
can be hidden for you)

=requires envelope_ns URI
=requires encoding_ns URI
=requires schema_ns URI
=option  schema_instance_ns URI
=default schema_instance_ns C<<$schema_ns . '-instance'>>

=option   media_type MIMETYPE
=default  media_type C<application/soap+xml>

=option   schemas    C<XML::Compile::Schema> object
=default  schemas    created internally
Use this when you have already processed some schema definitions.  Otherwise,
you can add schemas later with C<< $soap->schames->importDefinitions() >>

=requires version    STRING
The simple string representation of the protocol.
=cut

sub new($@)
{   my $class = shift;

    error __x"you can only instantiate sub-classes of {class}"
        if $class eq __PACKAGE__;

    (bless {}, $class)->init( {@_} );
}

sub init($)
{   my ($self, $args) = @_;
    $self->{envns}   = $args->{envelope_ns} || panic "no envelope namespace";
    $self->{encns}   = $args->{encoding_ns} || panic "no encoding namespace";
    $self->{schemans}= $args->{schema_ns}   || panic "no schema namespace";
    $self->{mimens}  = $args->{media_type}  || 'application/soap+xml';
    $self->{schemas} = $args->{schemas}     || XML::Compile::Schema->new;
    $self->{version} = $args->{version}     || panic "no version string";

    $self->{schemains} = $args->{schema_instance_ns}
      || $self->{schemans}.'-instance';

    $self;
}

=section Accessors
=method version
=method envelopeNS
=method encodingNS
=method schemaNS
=method schemaInstanceNS() {shift->{schemains}}
=cut

sub version()    {shift->{version}}
sub envelopeNS() {shift->{envns}}
sub encodingNS() {shift->{encns}}
sub schemaNS()   {shift->{schemans}}
sub schemaInstanceNS() {shift->{schemains}}

=method schemas
Returns the M<XML::Compile::Schema> object which contains the
knowledge about the types.
=cut

sub schemas()    {shift->{schemas}}

=method prefixPreferences TABLE, NEW, [USED]
NEW is a HASH or ARRAY-of-PAIRS which define prefix-to-uri relations,
which are added to the list defined in the TABLE (a HASH-of-HASHes).
When USED is set, then it will show-up in the output message.  At
compile-time, the value of USED is auto-detect.

This method is called for the soap specification preferred namespaces,
and for your M<compileMessage(prefixes)>.
=cut

sub prefixPreferences($$;$)
{   my ($self, $table, $new, $used) = @_;
    my @allns  = ref $new eq 'ARRAY' ? @$new : %$new;
    while(@allns)
    {   my ($prefix, $uri) = splice @allns, 0, 2;
        $table->{$uri} = {uri => $uri, prefix => $prefix, used => $used};
    }
    $table;
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

=option  faults ENTRIES
=default faults []
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
the predefined actors/roles, like 'NEXT'.  See M<roleURI()> and
M<roleAbbreviation()>.

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

=option  style 'document'|'rpc'
=default style 'document'

=option  prefixes HASH
=default prefixes {}
For the sender only: add additional prefix definitions.  All provided
names will be used always.
=cut

sub compileMessage($@)
{   my ($self, $direction, %args) = @_;
    $args{style} ||= 'document';

      $direction eq 'SENDER'   ? $self->sender(\%args)
    : $direction eq 'RECEIVER' ? $self->receiver(\%args)
    : error __x"message direction is 'SENDER' or 'RECEIVER', not {dir}"
         , dir => $direction;
}

#------------------------------------------------

=section Sender (internals)

=method sender ARGS
=cut

sub sender($)
{   my ($self, $args) = @_;

    error __"option 'role' only for readers"  if $args->{role};
    error __"option 'roles' only for readers" if $args->{roles};

    my $envns  = $self->envelopeNS;
    my $allns  = $self->prefixPreferences({}, $args->{prefix_table}, 0);
    $self->prefixPreferences($allns, $args->{prefixes}, 1)
        if $args->{prefixes};

    $allns->{$self->schemaInstanceNS}{used}++
        if $args->{style} eq 'rpc';

    # Translate message parts

    my ($header, $hlabels) = $self->writerCreateHeader
      ( $args->{header} || [], $allns
      , $args->{mustUnderstand}, $args->{destination}
      );

    my $headerhook = $self->writerHook($envns, 'Header', @$header);

    my ($body, $blabels) = $self->writerCreateBody
      ( $args->{body} || [], $allns );

    my ($fault, $flabels) = $self->writerCreateFault
      ( $args->{faults} || [], $allns
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

    sub { my ($values, $charset) = ref $_[0] eq 'HASH' ? @_ : ( {@_}, undef);
          my $doc   = XML::LibXML::Document->new('1.0', $charset || 'UTF-8');
          my %copy  = %$values;  # do not destroy the calling hash
          my %data;

          $data{$_}         = delete $copy{$_} for qw/Header Body/;
          $data{Body}     ||= {};

          $data{Header}{$_} = delete $copy{$_} for @$hlabels;
          $data{Body}{$_}   = delete $copy{$_} for @$blabels, @$flabels;

          if(!keys %copy) { ; }
          elsif(@$blabels==1 && !$data{Body}{$blabels->[0]})
          {   $data{Body}{$blabels->[0]} = \%copy;
          }
          else
          {   error __x"blocks not used: {blocks}", blocks => [keys %copy];
          }

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
               warning __x"unused values {names}", names => [keys %data]
                   if keys %data;

               # Body must be present, even empty, Header doesn't
               @childs || $tag =~ m/Body$/ or return ();

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
    my $fault  = $schema->compile
      ( WRITER => $faulttype
      , output_namespaces  => $allns
      , include_namespaces => 0
      , elements_qualified => 'TOP'
      );

    my @f      = @$faults;
    while(@f)
    {   my ($label, $type) = splice @f, 0, 2;
        my $details = $schema->compile
          ( WRITER => $type
          , output_namespaces  => $allns
          , include_namespaces => 0
          , elements_qualified => 'TOP'
          );

        my $code = sub
         { my ($doc, $data)  = (shift, shift);
           my %copy = %$data;
           $copy{faultactor} = $self->roleURI($copy{faultactor});
           my $det = delete $copy{detail};
           my @det = !defined $det ? () : ref $det eq 'ARRAY' ? @$det : $det;
           $copy{detail}{$type} = [ map {$details->($doc, $_)} @det ];
           $fault->($doc, \%copy);
         };

        push @rules, $label => $code;
        push @flabels, $label;
    }

    (\@rules, \@flabels);
}

#------------------------------------------------

=section Receiver (internals)

=method receiver ARGS
=cut

sub receiver($)
{   my ($self, $args) = @_;

    error __"option 'destination' only for writers"
        if $args->{destination};

    error __"option 'mustUnderstand' only for writers"
        if $args->{understand};

    my $schema = $self->schemas;
    my $envns  = $self->envelopeNS;

# roles are not checked (yet)
#   my $roles  = $args->{roles} || $args->{role} || 'ULTIMATE';
#   my @roles  = ref $roles eq 'ARRAY' ? @$roles : $roles;

    my $faultdec   = $self->readerParseFaults($args->{faults} || [], $envns);
    my $header     = $self->readerParseHeader($args->{header} || []);
    my $body       = $self->readerParseBody($args->{body} || []);

    my $headerhook = $self->readerHook($envns, 'Header', @$header);
    my $bodyhook   = $self->readerHook($envns, 'Body',   @$body);
    my $encstyle   = $self->readerEncstyleHook;

    my $envelope   = $self->schemas->compile
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

          $faultdec->($data);
          $data;
        }
}

=method readerHook NAMESPACE, LOCAL, ACTIONS
=cut

sub readerHook($$$@)
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
                    next;
                }
                return ($label => $self->replyMustUnderstandFault($type))
                    if $child->getAttribute('mustUnderstand') || 0;

                $h{$type} = $child;  # not decoded
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
        push @rules, [$label, $element
          , $schema->compile(READER => $element, anyElement => 'TAKE_ALL')];

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
        push @rules, [$label, $element
          , $schema->compile(READER => $element, anyElement => 'TAKE_ALL')];
    }

    \@rules;
}

=method readerParseFaults FAULTSDEF
=cut

sub readerParseFaults($)
{   my ($self, $faults) = @_;
    sub { shift };
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


#------------------------------------------------

=section Transcoding
SOAP defines encodings, especially for XML-RPC.
=cut

sub startEncoding(@)
{   my ($self, %args) = @_;
    require XML::Compile::SOAP::Encoding;
    $self->_init_encoding(\%args);
}

sub startDecoding(@)
{   my ($self, %args) = @_;
    require XML::Compile::SOAP::Encoding;
    $self->_init_decoding(\%args);
}

#------------------------------------------------

=section Helpers

=method roleURI URI|STRING
Translates actor/role/destination abbreviations into URIs. Various
SOAP protocol versions have different pre-defined STRINGs, which can
be abbreviated for readibility.  Returns the unmodified URI in
all other cases.

SOAP11 only defines C<NEXT>.  SOAP12 defines C<NEXT>, C<NONE>, and
C<ULTIMATE>.
=cut

sub roleURI($) { panic "not implemented" }

=method roleAbbreviation URI
Translate a role URI into a simple string, if predefined.  See
M<roleURI()>.
=cut

sub roleAbbreviation($) { panic "not implemented" }

=method replyMustUnderstandFault TYPE
Produce an error structure to be returned to the sender.
=cut

sub replyMustUnderstandFault($) { panic "not implemented" }

=chapter DETAILS

=section Using the produced calls

First, you compile the call either via a WSDL file (see
M<XML::Compile::WSDL11>), or in small manual steps, as described in
the next section.  So, in one of both ways, you end-up with

    # compile once
    my $call = $soap->compileClient(...);

    # and call often
    my $anwer = $call->(%request);  # list of pairs
    my $anwer = $call->(\%request); # same, but HASH
    my $anwer = $call->(\%request, 'UTF-8');  # same

But what is the structure of C<%request> and C<$answer> ?  Well, there
are various syntaxes possible: from structurally perfect, to user-friendly.

First, find out which data structures can be present.  When you compiled
your messages explicitly, you have picked your own names.  When the
call was initiated from a WSDL file, then you have to find the names
of the message parts which can be used.  The component names are for
header blocks, body blocks, headerfaults, and (body) faults.

Let's say that the WSDL defines this (ignoring all name-space issues)

 <message name="GetLastTradePriceInput">
   <part name="count" type="int" />
   <part name="request" element="TradePriceRequest"/>
 </message>

 <message name="GetLastTradePriceOutput">
   <part name="answer" element="TradePrice"/>
 </message>

 <definitions ...>
  <binding ...>
   <operation ...>
    <input>
     <soap:header message="GetLastTradePriceInput" part="count"
     <soap:body message="GetLastTradePriceInput" parts="request"
    <output>
     <soap:body message="GetLastTradePriceOutput"

The input message needs explicitly named parts, in this case, where the
output message simply uses all defined in the body.  So, the input message
has one header block C<count>, and one body block C<request>.  The output
message only has one body block C<answer>.

Then, the definitions of the blocks:

 <element name="TradePriceRequest">
   <complexType>
     <all>
       <element name="tickerSymbol" type="string"/>

 <element name="TradePrice">
   <complexType>
     <all>
       <element name="price" type="float"/>

Now, calling the compiled function can be done like this:

  my $anwer = $call->(count => 5, request => {tickerSymbol => 'IBM'});
  my $anwer = $call->(
      {count => 5, request => {tickerSymbol => 'IBM'}}, 'UTF-8');

However, in this case you may simplify the call.  First, all pairs
which use known block names are collected.  Then, if there is exactly
one body block which is not used yet, it will get all of the left over
names.  So... in this case, you could also use

 my $got = $call->(count => 5, tickerSymbol => 'IBM');

This does not work if the block element is a simple type.  In most
existing SOAP schemas, this simplification probably is possible.

The C<$got> is a HASH, which will not be simplified.  The return
might be (M<Data::Dumper> is your friend)

 $got = { answer => { price => 16.3 } }

To access the value use

 printf "%.2f US\$\n", $got->{answer}->{price};
 printf "%.2f US\$\n", $got->{answer}{price};

=subsection Faults

Faults and headerfaults are a slightly different story: the type which
is specified with them is not of the fault XML node itself, but of the
C<details> sub-element within the standard fault structure.

When producing the data for faults, you must be aware of the fact that
the structure is different for SOAP1.1 and SOAP1.2.  When interpreting
faults, the same problems are present, although the implementation
tries to help you.

Check whether SOAP1.1 or SOAP1.2 is used by looking for a C<faultcode>
(SOAP1.1) or a C<Code> (SOAP1.2) field in the data:

  if(my $fault = $got->{Fault})
  {  if($fault->{faultcode}) { ... SOAP1.1 ... }
     elsif($fault->{Code})   { ... SOAP1.2 ... }
     else { die }
  }

In either protocol case, the following will get you at a compatible
structure:

  if(my $fault = $got->{Fault})
  {   my $decoded = $got->{$fault->{_NAME}};
      print $decoded->{code};
      ...
  }

See the respective manuals M<XML::Compile::SOAP11> and
M<XML::Compile::SOAP12> for the (ugly) specifics.

=section Calling SOAP without WSDL

See the manual page of M<XML::Compile::WSDL11> to see how simple
you can use this module when you have a WSDL file at hand.  The
creation of a correct WSDL file is NOT SIMPLE.

When using SOAP without WSDL file, it gets a little bit more complicate
to use: you need to describe the content of the messages yourself.
The following example is used as test-case C<t/10soap11.t>, directly
taken from the SOAP11 specs section 1.3 example 1.

 # for simplification
 my $TestNS   = 'http://test-types';
 use XML::Compile::Util qw/SCHEMA2001/;
 my $SchemaNS = SCHEMA2001;

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
 my %data_in = (transaction => 5, request => {symbol => 'DIS'});
 my %data_in = (transaction => 5, symbol => 'DIS'); # alternative

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
=cut

1;
