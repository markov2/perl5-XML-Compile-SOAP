use warnings;
use strict;

package XML::Compile::SOAP;

use Log::Report 'xml-compile-soap', syntax => 'SHORT';
use XML::Compile         ();
use XML::Compile::Util   qw/pack_type type_of_node/;
use XML::Compile::Schema ();

use Time::HiRes          qw/time/;

=chapter NAME
XML::Compile::SOAP - base-class for SOAP implementations

=chapter SYNOPSIS
 ** Only use SOAP1.1 and WSDL1.1; SOAP1.2/WSDL1.2 not working!
 ** See TODO, at the end of this page

 use XML::Compile::SOAP11::Client;
 use XML::Compile::Util qw/pack_type/;

 my $client = XML::Compile::SOAP11::Client->new;

 # load extra schemas always explicitly
 $client->importDefinitions(...);

 # !!! The next steps are only required when you do not have
 # !!! a WSDL. See XML::Compile::WSDL11 if you have a WSDL.
 
 my $h1el = pack_type $myns, $some_element;
 my $b1el = "{$myns}$other_element";  # same, less clean

 my $encode_query = $client->compileMessage
   ( 'SENDER'
   , header   => [ h1 => $h1el ]
   , body     => [ b1 => $b1el ]
   , destination    => [ h1 => 'NEXT' ]
   , mustUnderstand => 'h1'
   );

 my $decode_response = $client->compileMessage
   ( 'RECEIVER'
   , header    => [ h2 => $h2el ]
   , body      => [ b2 => $b2el ]
   , faults    => [ ... ]
   );

 my $http = XML::Compile::Transport::SOAPHTTP
    ->new(address => $server);
 my $http = $transport->compileClient(action => ...);

 # Combine into one message exchange:

 my @query    = (h1 => ..., b1 => ...);
 my $request  = $encode_query->($query);
 my ($response, $trace) = $http->($request);
 my $answer   = $decode_response->($response);

 use Data::Dumper;
 warn Dumper $answer;     # see: a HASH with h2 and b2!
 if($answer->{Fault}) ... # error was reported

 # Simplify your life
 # also in this case: if you have a WSDL, this is created for you.
 # This is Document-style SOAP

 my $call   = $client->compileClient
   ( kind      => 'request-response'  # default
   , name      => 'my first call'
   , encode    => $encode_query
   , decode    => $decode_response
   , transport => $http
   );

 # With or without WSDL file the same

 my $result = $call->(h1 => ..., b1 => ...);
 print $result->{h2}->{...};
 print $result->{b2}->{...};

 my ($result, $trace) = $call->(...);  # LIST will show trace
 # $trace is an XML::Compile::SOAP::Trace object

=chapter DESCRIPTION

This module handles the SOAP protocol.  The first implementation is
SOAP1.1 (F<http://www.w3.org/TR/2000/NOTE-SOAP-20000508/>), which is still
most often used.  The SOAP1.2 definition (F<http://www.w3.org/TR/soap12/>)
is quite different; this module tries to define a sufficiently abstract
interface to hide the protocol differences.

Be aware that there are three kinds of SOAP:

=over 4
=item 1.
Document style (literal) SOAP, where there is a WSDL file which explicitly
types all out-going and incoming messages.  Very easy to use.

=item 2.
RPC style SOAP literal.  The WSDL file is not explicit about the
content of the messages, but all messages must be schema defined types.

=item 3.
RPC style SOAP encoded.  The sent data is nowhere described formally.
The data is transported in some ad-hoc way.
=back

=chapter METHODS

=section Constructors

=method new OPTIONS
Create a new SOAP object.  You have to instantiate either the SOAP11 or
SOAP12 sub-class of this, because there are quite some differences (which
can be hidden for you)

=requires envelope_ns URI
=requires encoding_ns URI
=requires schema_ns   URI

=option  schema_instance_ns URI
=default schema_instance_ns C<<$schema_ns . '-instance'>>

=option  media_type MIMETYPE
=default media_type C<application/soap+xml>

=option  schemas    C<XML::Compile::Schema> object
=default schemas    created internally
Use this when you have already processed some schema definitions.  Otherwise,
you can add schemas later with C<< $soap->schemas->importDefinitions() >>

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

As OPTIONS, you can specify any listed here, but also anything which is
accepted by M<XML::Compile::Schema::compile()>, like
C<< sloppy_integers => 1 >> and hooks.  These are applied to all header
and body elements (not to the SOAP wrappers)

=option  header ENTRIES
=default header C<undef>
ARRAY of PAIRS, defining a nice LABEL (free of choice but unique)
and an element type name.  The LABEL will appear in the Perl HASH, to
refer to the element in a simple way.

The element type is used to construct a reader or writer.  You may also
create your own reader or writer, and then pass a compatible CODE reference.

=option  body   ENTRIES
=default body   []
ARRAY of PAIRS, defining a nice LABEL (free of choice but unique, also
w.r.t. the header and fault ENTRIES) and an element type name or CODE
reference.  The LABEL will appear in the Perl HASH only, to be able to
refer to a body element in a simple way.

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

=option  style 'document'|'rpc-literal'|'rpc-encoded'
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
    : error __x"message direction is 'SENDER' or 'RECEIVER', not `{dir}'"
         , dir => $direction;
}

=ci_method messageStructure XML
Returns a HASH with some collected information from a complete SOAP
message (XML::LibXML::Document or XML::LibXML::Element).  Currenty,
the HASH contains a C<header> and a C<body> key, with each an ARRAY
of element names which where found in the header resp. body.
=cut

sub messageStructure($)
{   my ($thing, $xml) = @_;
    my $env = $xml->isa('XML::LibXML::Document') ? $xml->documentElement :$xml;

    my (@header, @body);
    if(my ($header) = $env->getChildrenByLocalName('Header'))
    {   @header = map { $_->isa('XML::LibXML::Element') ? type_of_node($_) : ()}
           $header->childNodes;
    }

    if(my ($body) = $env->getChildrenByLocalName('Body'))
    {   @body = map { $_->isa('XML::LibXML::Element') ? type_of_node($_) : () }
           $body->childNodes;
    }

    +{ header => \@header
     , body   => \@body
     };
}

=method importDefinitions XMLDATA, OPTIONS
Add definitions to the schema.  Simply calls
M<XML::Compile::Schema::importDefinitions()> for this SOAP object's
schema with all the parameters provided.  XMLDATA can be everything
accepted by M<XML::Compile::dataToXML()> plus an ARRAY of these things.
=cut

sub importDefinitions(@)
{   my $schemas = shift->schemas;
    $schemas->importDefinitions(@_);
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

    # Translate header

    my ($header, $hlabels) = $self->writerCreateHeader
      ( $args->{header} || [], $allns
      , $args->{mustUnderstand}, $args->{destination}
      , $args
      );

    # Translate body (3 options)

    my $style   = $args->{style};
    my $bodydef = $args->{body} || [];

    if($style eq 'rpc-literal')
    {   unshift @$bodydef, $self->writerCreateRpcLiteral($allns);
    }
    elsif($style eq 'rpc-encoded')
    {   unshift @$bodydef, $self->writerCreateRpcEncoded($allns);
    }
    elsif($style ne 'document')
    {   error __x"unknown soap message style `{style}'", style => $style;
    }

    my ($body, $blabels) = $self->writerCreateBody($bodydef, $allns, $args);

    # Translate body faults

    my ($fault, $flabels) = $self->writerCreateFault
      ( $args->{faults} || [], $allns
      , pack_type($envns, 'Fault')
      );

    my @hooks =
      ( ($style eq 'rpc-encoded' ? $self->writerEncstyleHook($allns) : ())
      , $self->writerHook($envns, 'Header', @$header)
      , $self->writerHook($envns, 'Body', @$body, @$fault)
      );

    #
    # Pack everything together in one procedure
    #

    my $envelope = $self->schemas->compile
      ( WRITER => pack_type($envns, 'Envelope')
      , %$args
      , hooks  => \@hooks
      , output_namespaces    => $allns
      , elements_qualified   => 1
      , attributes_qualified => 1
      );

    sub
    {   my ($values, $charset) = ref $_[0] eq 'HASH' ? @_ : ( {@_}, undef);
        my $doc   = XML::LibXML::Document->new('1.0', $charset || 'UTF-8');
        my %copy  = %$values;  # do not destroy the calling hash
        my %data;

        $data{$_}   = delete $copy{$_} for qw/Header Body/;
        $data{Body} ||= {};

        foreach my $label (@$hlabels)
        {   defined $copy{$label} or next;
            error __x"header part {name} specified twice", name => $label
                if defined $data{Header}{$label};
            $data{Header}{$label} ||= delete $copy{$label}
        }

        foreach my $label (@$blabels, @$flabels)
        {   defined $copy{$label} or next;
            error __x"body part {name} specified twice", name => $label
                if defined $data{Body}{$label};
            $data{Body}{$label} ||= delete $copy{$label};
        }

        if(@$blabels==2 && !keys %{$data{Body}} ) # ignore 'Fault'
        {  # even when no params, we fill at least one body element
            $data{Body}{$blabels->[0]} = \%copy;
        }
        elsif(keys %copy)
        {   error __x"call data not used: {blocks}", blocks => [keys %copy];
        }

        my $root = $envelope->($doc, \%data)
            or return;
        $doc->setDocumentElement($root);
        $doc;
    };
}

=method writerHook NAMESPACE, LOCAL, ACTIONS
=cut

sub writerHook($$@)
{   my ($self, $ns, $local, @do) = @_;
 
   +{ type    => pack_type($ns, $local)
    , replace =>
        sub
        {   my ($doc, $data, $path, $tag) = @_;
            my %data = %$data;
            my @h = @do;
            my @childs;
            while(@h)
            {   my ($k, $c) = (shift @h, shift @h);
                if(my $v = delete $data{$k})
                {   push @childs, $c->($doc, $v);
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

    my $before  = sub
      { my ($doc, $values, $path) = @_;
        ref $values eq 'HASH' or return $values;
        $style = $style_w->($doc, delete $values->{encodingStyle});
        $values;
      };

    my $after = sub
      { my ($doc, $node, $path) = @_;
        $node->addChild($style) if defined $style;
        $node;
      };

   { before => $before, after => $after };
}

=method writerCreateHeader HEADER-DEFS, NS-TABLE, UNDERSTAND, DESTINATION, OPTS
=cut

sub writerCreateHeader($$$$)
{   my ($self, $header, $allns, $understand, $destination, $opts) = @_;
    my (@rules, @hlabels);
    my $schema      = $self->schemas;
    my %destination = ref $destination eq 'ARRAY' ? @$destination : ();

    my %understand  = map { ($_ => 1) }
        ref $understand eq 'ARRAY' ? @$understand
      : defined $understand ? "$understand" : ();

    my @h = @$header;
    while(@h)
    {   my ($label, $element) = splice @h, 0, 2;

        my $code = UNIVERSAL::isa($element,'CODE') ? $element
         : $schema->compile
           ( WRITER => $element, %$opts
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

=method writerCreateBody BODY-DEFS, NAMESPACE-TABLE, OPTS
=cut

sub writerCreateBody($$)
{   my ($self, $body, $allns, $opts) = @_;
    my (@rules, @blabels);
    my $schema = $self->schemas;
    my @b      = @$body;
    while(@b)
    {   my ($label, $element) = splice @b, 0, 2;

        my $code = UNIVERSAL::isa($element, 'CODE') ? $element
        : $schema->compile
          ( WRITER => $element, %$opts
          , output_namespaces  => $allns
          , include_namespaces => 0
          , elements_qualified => 'TOP'
          );

        push @rules, $label => $code;
        push @blabels, $label;
    }

    (\@rules, \@blabels);
}

=method writerCreateRpcLiteral NAMESPACE-TABLE
Create a handler which understands RPC literal specifications.
=cut

sub writerCreateRpcLiteral($)
{   my ($self, $allns) = @_;
    my $lit = sub
     { my ($doc, $def) = @_;
       UNIVERSAL::isa($def, 'ARRAY')
           or error __x"rpc style requires compileClient with rpcin parameters as array";

       my ($code, $data) = @$def;
       $code->($doc, $data);
     };

    (rpc => $lit);
}

=method writerCreateRpcEncoded NAMESPACE-TABLE
Create a handler which understands RPC encoded specifications.
=cut

sub writerCreateRpcEncoded($)
{   my ($self, $allns) = @_;
    my $lit = sub
     { my ($doc, $def) = @_;
       UNIVERSAL::isa($def, 'ARRAY')
           or error __x"rpc style requires compileClient with rpcin parameters";

       my ($code, $data) = @$def;
       $self->startEncoding(doc => $doc);

       my @body = $code->($self, $doc, $data)
           or return ();

       $_->isa('XML::LibXML::Element')
           or error __x"rpc body must contain elements, not {el}", el => $_
              foreach @body;

       my $top = $body[0];
       my ($topns, $toplocal) = ($top->namespaceURI, $top->localName);
       $topns || index($toplocal, ':') >= 0
           or error __x"rpc first body element requires namespace";

       $top->setAttribute($allns->{$self->envelopeNS}{prefix}.':encodingStyle'
          , $self->encodingNS);

       my $enc = $self->{enc};

       # add namespaces to first body element.  Sorted for reproducible
       # results there may be problems with multiple body elements.
       $top->setAttribute("xmlns:$_->{prefix}", $_->{uri})
           for sort {$a->{prefix} cmp $b->{prefix}}
                   values %{$enc->{namespaces}};

       @body;
     };

    (rpc => $lit);
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

    my $style   = $args->{style};
    my $bodydef = $args->{body} || [];

    $style =~ m/^(?:rpc-literal|rpc-encoded|document)$/
        or error __x"unknown soap message style `{style}'", style => $style;

# roles are not checked (yet)
#   my $roles  = $args->{roles} || $args->{role} || 'ULTIMATE';
#   my @roles  = ref $roles eq 'ARRAY' ? @$roles : $roles;

    my $faultdec = $self->readerParseFaults($args->{faults} || []);
    my $header   = $self->readerParseHeader($args->{header} || [], $args);
    my $body     = $self->readerParseBody($bodydef, $args);

    my $envns    = $self->envelopeNS;
    my @hooks    = 
      ( ($style eq 'rpc-encoded' ? $self->readerEncstyleHook : ())
      , $self->readerHook($envns, 'Header', @$header)
      , $self->readerHook($envns, 'Body',   @$body)
      );

    my $envelope = $self->schemas->compile
     ( READER => pack_type($envns, 'Envelope')
     , hooks  => \@hooks
     , anyElement   => 'TAKE_ALL'
     , anyAttribute => 'TAKE_ALL'
     );

    sub
    {   my $xml   = shift;
        my $data  = $envelope->($xml);
        my @pairs = ( %{delete $data->{Header} || {}}
                    , %{delete $data->{Body}   || {}});
        while(@pairs)
        {  my $k       = shift @pairs;
           $data->{$k} = shift @pairs;
        }

        $faultdec->($data);
        $data;
    };
}

=method readerHook NAMESPACE, LOCAL, ACTIONS
=cut

sub readerHook($$$@)
{   my ($self, $ns, $local, @do) = @_;
    my %trans = map { ($_->[1] => [ $_->[0], $_->[2] ]) } @do; # we need copies
 
    my $replace = sub
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

            # not decoded right now: rpc
            if(! exists $h{$type}) { $h{$type} = $child }
            elsif(ref $h{$type} eq 'ARRAY') { push @{$h{$type}}, $child }
            else { $h{$type} = [ $h{$type}, $child ] }
        }
        ($label => \%h);
      };

   +{ type    => pack_type($ns, $local)
    , replace => $replace
    };
}

=method readerParseHeader HEADERDEF, OPTS
=cut

sub readerParseHeader($$)
{   my ($self, $header, $opts) = @_;
    my @rules;

    my $schema = $self->schemas;
    my @h      = @$header;
    @h % 2
       and error __x"reader header definition list has odd length";

    while(@h)
    {   my ($label, $element) = splice @h, 0, 2;
        my $code = UNIVERSAL::isa($element, 'CODE') ? $element
          : $schema->compile
              ( READER => $element, %$opts
              , anyElement => 'TAKE_ALL'
              );
        push @rules, [$label, $element, $code];

    }

    \@rules;
}

=method readerParseBody BODYDEF, OPTS
=cut

sub readerParseBody($$$)
{   my ($self, $body, $opts) = @_;
    my @rules;

    my $schema = $self->schemas;
    my @b      = @$body;
    @b % 2
       and error __x"reader body definition list has odd length";

    while(@b)
    {   my ($label, $element) = splice @b, 0, 2;
        my $code = UNIVERSAL::isa($element, 'CODE') ? $element
          : $schema->compile
              ( READER => $element, %$opts
              , anyElement => 'TAKE_ALL'
              );
        push @rules, [$label, $element, $code];
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
# Implemented in XML::Compile::SOAP::Encoding;

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

=section SOAP introduction

Although the specification of SOAP1.1 and WSDL1.1 are thin, the number
of special constructs are many.  And, of course, all poorly documented.
Both SOAP and WSDL have 1.2 versions, which will clear things up a lot,
but not used that often yet.

WSDL defines two kinds of messages: B<document> style SOAP and B<rpc>
style SOAP.  In I<Document style SOAP>, the messages are described in
great detail in the WSDL: the message components are all defined in
Schema's; the worst things you can (will) encounter are C<any> schema
elements which require additional manual processing.

I would like to express my personal disgust over I<RPC style SOAP>.
In this case, the body of the message is I<not> clearly specified in the
WSDL... which violates the whole purpose of using interface descriptions
in the first place!  In a client-server interface definition, you really
wish to be very explicit in the data you communicate.  Gladly, SOAP1.2
shares my feelings a little, and speaks against RPC although still
supporting it.

Anyway, we have to live with this feature.  SOAP-RPC is simple
to use on strongly typed languages, to exchange data when you create both
the client software and the server software.  You can simply autogenerate
the data encoding.  Clients written by third parties have to find the
documentation on how to use the RPC call in some other way... in text,
if they are lucky; the WSDL file does not contain the prototype of the
procedures, but that doesn't mean that they are free-format.

The B<encoded RPC> messsages are shaped to the procedures which are
being called on the server.  The body of the sent message contains the
ordered list of parameters to be passed as 'in' and 'in/out' values to the
remote procedure.  The body of the returned message lists the result value
of the procedure, followed by the ordered 'out' and 'in/out' parameters.

The B<literal RPC> messages are half-breed document style message: there is
a schema which tells you how to interpret the body, but the WSDL doesn't
tell you what the options are.

=section Naming types and elements

XML uses namespaces: URIs which are used as constants, grouping a set
of type and element definitions.  By using name-spaces, you can avoid
name clashes, which have frustrate many projects in history, when they
grew over a certain size... at a certain size, it becomes too hard to
think of good distriguishable names.  In such case, you must be happy
when you can place those names in a context, and use the same naming in
seperate contexts without confusion.

That being said: XML supports both namespace- and non-namespace elements
and schema's; and of cause many mixed cases.  It is by far preferred to
use namespace schemas only.  For a schema xsd file, look for the
C<targetNamespace> attribute of the C<schema> element: if present, it
uses namespaces.

In XML data, it is seen as a hassle to write the full length of the URI
each time that a namespace is addressed.  For this reason, prefixes
are used as abbreviations.  In programs, you can simply assign short
variable names to long URIs, so we do not need that trick.

Within your program, you use

  $MYSN = 'long URI of namespace';
  ... $type => "{$MYNS}typename" ...

or nicer

  use XML::Compile::Util qw/pack_type/;
  use constant MYNS => 'some uri';
  ... $type => pack_type(MYNS, 'typename') ...

The M<XML::Compile::Util> module provides a helpfull methods and constants,
as does the M<XML::Compile::SOAP::Util>.

=section Client, Proxy and Server implementations

To learn how to create clients in SOAP, read the DETAILS section in
M<XML::Compile::SOAP::Client>.  The client implementation is platform
independent.

A proxy is a complex kind of server, which in implemented
by <XML::Compile::SOAP::Server>, which is available from the
XML-Compile-SOAP-Daemon distribution.  The server is based on
M<Net::Server>, which may have some portability restrictions.

=chapter TODO

On the moment, the following limitations exist:

=over 4

=item .
Only SOAP1.1 sufficiently implemented (probably).  There are some
steps into SOAP1.2, but mainly as program infra-structure to have
the SOAP1.2 implementation fit in nicely.  B<No SOAP1.2>!

=item .
Only WSDL1.1 is implemented.  WSDL1.2 is not yet forseen.

=back

=cut

1;
