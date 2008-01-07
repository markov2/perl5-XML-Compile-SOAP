use warnings;
use strict;

package XML::Compile::SOAP;

use Log::Report 'xml-compile-soap', syntax => 'SHORT';
use XML::Compile         ();
use XML::Compile::Util   qw/pack_type unpack_type/;
use XML::Compile::Schema ();

use Time::HiRes          qw/time/;

=chapter NAME
XML::Compile::SOAP - base-class for SOAP implementations

=chapter SYNOPSIS
 ** WARNING: This implementation is quite new!  Only SOAP1.1
 ** see TODO, at the end of this page

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

 # In nice, small steps:

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

 my ($result, $trace) = $call->(...);  # LIST with show trace

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

=method compileClient OPTIONS

=option  name STRING
=default name <from rpcout> or "unnamed"
Currently only used in some error messages, but may be used more intensively
in the future.  When C<rpcout> is a TYPE, then the local name of that type
is used as default.

=option  kind STRING
=default kind C<request-response>
Which kind of client is this.  WSDL11 defines four kinds of client-server
interaction.  Only C<request-response> (the default) and C<one-way> are
currently supported.

=requires encode CODE
The CODE reference is produced by M<compileMessage()>, and must be a
SENDER: translates Perl data structures into the SOAP message in XML.

=requires decode CODE
The CODE reference is produced by M<compileMessage()>, and must be a
RECEIVER: translate a SOAP message into Perl data.  Even in one-way
operation, this decode should be provided: some servers may pass back
some XML in case of errors.

=requires transport CODE
The CODE reference is produced by an extensions of
M<XML::Compile::Transport::compileClient()>
(usually M<XML::Compile::Transport::SOAPHTTP::compileClient()>.

=option  rpcout TYPE|CODE
=default rpcout C<undef>
The TYPE of the RPC output message (RPC literal style) or a CODE reference
which can be created to produce the RPC block (RPC encoded style).

=option  rpcin TYPE|CODE
=default rpcin <depends on type of rpcout>

The TYPE of the RPC input message (RPC literal style) or a CODE reference
which can be created to parse the RPC block (RPC encoded style).

If this option is not specified, but there is an C<rpcout> with TYPE
value, then the value for this options will default for that type name
with C<Response> concatenated: a commonly used convension.

If this option is not used, but there is an C<rpcout> with CODE
reference, then a standard decode routine is called.  That routine
does use M<XML::Compile::SOAP::Encoding::decSimplify()> to get an
as simple as possible return structure.

=cut

sub _rpcin_default($@)
{   my ($soap, @msgs) = @_;
    my $tree   = $soap->dec(@msgs) or return ();
    $soap->decSimplify($tree);
}

my $rr = 'request-response';
sub compileClient(@)
{   my ($self, %args) = @_;

    my $name   = $args{name};
    my $rpcout = $args{rpcout};

    unless(defined $name)
    {   (undef, $name) = unpack_type $rpcout
            if $rpcout && ! ref $rpcout;
        $name ||= 'unnamed';
    }

    my $kind = $args{kind} || $rr;
    $kind eq $rr || $kind eq 'one-way'
        or error __x"operation direction `{kind}' not supported for {name}"
             , rr => $rr, kind => $kind, name => $name;

    my $encode = $args{encode}
        or error __x"encode for client {name} required", name => $name;

    my $decode = $args{decode}
        or error __x"decode for client {name} required", name => $name;

    my $transport = $args{transport}
        or error __x"transport for client {name} required", name => $name;

    my $core = sub
    {   my $start = time;
        my ($data, $charset) = UNIVERSAL::isa($_[0], 'HASH') ? @_ : ({@_});
        my $req   = $encode->($data, $charset);

        my %trace;
        my $ans   = $transport->($req, \%trace);

        wantarray or return
            UNIVERSAL::isa($ans, 'XML::LibXML::Node') ? $decode->($ans) : $ans;

        $trace{date}   = localtime $start;
        $trace{start}  = $start;
        $trace{encode_elapse} = $trace{transport_start} - $start;

        UNIVERSAL::isa($ans, 'XML::LibXML::Node')
            or return ($ans, \%trace);

        my $dec = $decode->($ans);
        my $end = time;
        $trace{decode_elapse} = $end - $trace{transport_end};
        $trace{elapse} = $end - $start;

        ($dec, \%trace);
    };

    # Outgoing messages

    defined $rpcout
        or return $core;

    my $rpc_encoder
      = UNIVERSAL::isa($rpcout, 'CODE') ? $rpcout
      : $self->schemas->compile
        ( WRITER => $rpcout
        , include_namespaces => 1
        , elements_qualified => 'TOP'
        );

    my $out = sub
      {    @_ && @_ % 2  # auto-collect rpc parameters
      ? ( rpc => [$rpc_encoder, shift], @_ ) # possible header blocks
      : ( rpc => [$rpc_encoder, [@_] ]     ) # rpc body only
      };

    # Incoming messages

    my $rpcin = $args{rpcin} ||
      (UNIVERSAL::isa($rpcout, 'CODE') ? \&_rpcin_default : $rpcout.'Response');

    # RPC intelligence wrapper

    if(UNIVERSAL::isa($rpcin, 'CODE'))     # rpc-encoded
    {   return sub
        {   my ($dec, $trace) = $core->($out->(@_));
            return wantarray ? ($dec, $trace) : $dec
                if $dec->{Fault};

            my @raw;
            foreach my $k (keys %$dec)
            {   my $node = $dec->{$k};
                if(   ref $node eq 'ARRAY' && @$node
                   && $node->[0]->isa('XML::LibXML::Element'))
                {   push @raw, @$node;
                    delete $dec->{$k};
                }
                elsif(ref $node && $node->isa('XML::LibXML::Element'))
                {   push @raw, delete $dec->{$k};
                }
            }

            if(@raw)
            {   $self->startDecoding(simplify => 1);
                my @parsed = $rpcin->($self, @raw);
                if(@parsed==1) { $dec = $parsed[0] }
                else
                {   while(@parsed)
                    {   my $n = shift @parsed;
                        $dec->{$n} = shift @parsed;
                    }
                }
            }

            wantarray ? ($dec, $trace) : $dec;
        };
    }
    else                                   # rpc-literal
    {   my $rpc_decoder = $self->schemas->compile(READER => $rpcin);
        (undef, my $rpcin_local) = unpack_type $rpcin;

        return sub
        {   my ($dec, $trace) = $core->($out->(@_));
            $dec->{$rpcin_local} = $rpc_decoder->(delete $dec->{$rpcin})
              if $dec->{$rpcin};
            wantarray ? ($dec, $trace) : $dec;
        };
    }
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

    my ($body, $blabels) = $self->writerCreateBody($bodydef, $allns);

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

        $envelope->($doc, \%data);
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

        my $code = UNIVERSAL::isa($element,'CODE') ? $element
         : $schema->compile
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

        my $code = UNIVERSAL::isa($element, 'CODE') ? $element
        : $schema->compile
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

=method writerCreateRpcLiteral NAMESPACE-TABLE
Create a handler which understands RPC literal specifications.
=cut

sub writerCreateRpcLiteral($)
{   my ($self, $allns) = @_;
    my $lit = sub
     { my ($doc, $def) = @_;
       UNIVERSAL::isa($def, 'ARRAY')
           or error __x"rpc style requires compileClient with rpcin parameters";

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

       my $top = $code->($self, $doc, $data)
           or return ();

       my ($topns, $toplocal) = ($top->namespaceURI, $top->localName);
       $topns || index($toplocal, ':') >= 0
           or error __x"rpc top element requires namespace";

       $top->setAttribute($allns->{$self->envelopeNS}{prefix}.':encodingStyle'
          , $self->encodingNS);

       my $enc = $self->{enc};

       # add namespaces to top element.  Sorted for reproducible results
       $top->setAttribute("xmlns:$_->{prefix}", $_->{uri})
           for sort {$a->{prefix} cmp $b->{prefix}}
                   values %{$enc->{namespaces}};

       $top;
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
    my $header   = $self->readerParseHeader($args->{header} || []);
    my $body     = $self->readerParseBody($bodydef);

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

=method readerParseHeader HEADERDEF
=cut

sub readerParseHeader($)
{   my ($self, $header) = @_;
    my @rules;

    my $schema = $self->schemas;
    my @h      = @$header;
    while(@h)
    {   my ($label, $element) = splice @h, 0, 2;
        my $code = UNIVERSAL::isa($element, 'CODE') ? $element
          : $schema->compile(READER => $element, anyElement => 'TAKE_ALL');
        push @rules, [$label, $element, $code];

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
        my $code = UNIVERSAL::isa($element, 'CODE') ? $element
          : $schema->compile(READER => $element, anyElement => 'TAKE_ALL');
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

=section Transcoding
SOAP defines encodings, especially for SOAP-RPC.

=subsection Encoding
=subsection Decoding
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

=section Using SOAP calls

=subsection Naming types and elements

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

=subsection Calling the server (Document style)

First, you compile the call either via a WSDL file (see
M<XML::Compile::WSDL11>), or in a few manual steps (which are described
in the next section).  In either way, you end-up with a CODE references
which can be called multiple times.

    # compile once
    my $call   = $soap->compileClient(...);

    # and call often
    my $answer = $call->(%request);  # list of pairs
    my $answer = $call->(\%request); # same, but HASH
    my $answer = $call->(\%request, 'UTF-8');  # same

But what is the structure of C<%request> and C<$answer>?  Well, there
are various syntaxes possible: from structurally perfect, to user-friendly.

First, find out which data structures can be present: when you compiled
your messages explicitly, you have picked your own names.  When the
call was initiated from a WSDL file, then you have to find the names of
the message parts which can be used: the part names for header blocks,
body blocks, headerfaults, and (body) faults.  Do not worry to much,
you will get (hopefully understandable) run-time error messages when
the structure is incorrect.

Let's say that the WSDL defines this (ignoring all name-space issues)

 <definitions xmlns:xx="MYNS"
   <message name="GetLastTradePriceInput">
    <part name="count" type="int" />
    <part name="request" element="xx:TradePriceRequest"/>
   </message>

   <message name="GetLastTradePriceOutput">
    <part name="answer" element="xx:TradePrice"/>
   </message>

   <binding
    <operation
     <input>
      <soap:header message="GetLastTradePriceInput" part="count"
      <soap:body message="GetLastTradePriceInput" parts="request"
     <output>
      <soap:body message="GetLastTradePriceOutput"

The input message needs explicitly named parts in this case, where the
output message simply uses all defined in the body.  So, the input message
has one header part C<count>, and one body part C<request>.  The output
message only has one part named C<answer>, which is all defined for the
message and therefore its name can be omitted.

Then, the definitions of the blocks:

 <schema targetNamespace="MYNS"
   <element name="TradePriceRequest">
    <complexType>
     <all>
      <element name="tickerSymbol" type="string"/>

   <element name="TradePrice">
    <complexType>
     <all>
      <element name="price" type="float"/>
 </schema>

Now, calling the compiled function can be done like this:

  my $got
     = $call->(  count => 5, request => {tickerSymbol => 'IBM'}  );
     = $call->({ count => 5, request => {tickerSymbol => 'IBM'} });
     = $call->({ count => 5, request => {tickerSymbol => 'IBM'} }
        , 'UTF-8');

If the first arguments for the code ref is a HASH, then there may be
a second which specifies the required character-set.  The default is
C<UTF-8>, which is very much adviced.

=subsection Parameter unpacking (Document Style)

In the example situation of previous section, you may simplify the
call even further.  To understand how, we need to understand the
parameter unpacking algorithm.

The structure which we need to end up with, looks like this

  $call->(\%data, $charset);
  %data = ( Header => {count => 5}
          , Body   =>
             { request => {tickerSymbol => 'IBM'} }
          );

The structure of the SOAP message is directly mapped on this
nested complex HASH.  But is inconvenient to write each call
like this, therefore the C<$call> parameters are transformed into
the required structure according to the following rules:

=over 4
=item 1.
if called with a LIST, then that will become a HASH
=item 2.
when a C<Header> and/or C<Body> are found in the HASH, those are
used
=item 3.
if there are more parameters in the HASH, then those with names of
known header and headerfault message parts are moved to the C<Header>
sub-structure.  Body and fault message parts are moved to the C<Body>
sub-structure.
=item 4.
If the C<Body> sub-structure is empty, and there is only one body part
expected, then all remaining parameters are put in a HASH for that part.
This also happens if there are not parameters: it will result in an
empty HASH for that block.
=back

So, in our case this will also do, because C<count> is a known part,
and C<request> gets all left-overs, being the only body part.

 my $got = $call->(count => 5, tickerSymbol => 'IBM');

This does not work if the block element is a simple type.  In most
existing Document style SOAP schemas, this simplification probably
is possible.

=subsection Understanding the output (Document style)

The C<$got> is a HASH, which will not be simplified automatically:
it may change with future extensions of the interface.  The return
is a complex nested structure, and M<Data::Dumper> is your friend.

 $got = { answer => { price => 16.3 } }

To access the value use

 printf "%.2f US\$\n", $got->{answer}->{price};
 printf "%.2f US\$\n", $got->{answer}{price};   # same

or

 my $answer = $got->{answer};
 printf "%.2f US\$\n", $answer->{price};

=subsection Calling the server (SOAP-RPC style literal)

SOAP-RPC style messages which have C<<use=literal>> cannot be used
without a little help.  However, one extra definition per procedure
call suffices.

This a complete code example, although you need to fill in some
specifics about your environment.  If you have a WSDL file, then it
will be a little simpler, see M<XML::Compile::WSDL11::compileClient()>.

 # You probably need these
 use XML::Compile::SOAP11::Client;
 use XML::Compile::Transport::SOAPHTTP;
 use XML::Compile::Util  qw/pack_type/;

 # Literal style RPC
 my $outtype = pack_type $MYNS, 'myFunction';
 my $intype  = pack_type $MYNS, 'myFunctionResponse';
 my $style   = 'rpc-literal';

 # Encoded style RPC (see next section on these functions)
 my $outtype = \&my_pack_params;
 my $intype  = \&my_unpack_params;
 my $style   = 'rpc-encoded';

 # For all RPC calls, you need this only once (or have a WSDL):
 my $transp  = XML::Compile::Transport::SOAPHTTP->new(...);
 my $http    = $transp->compileClient(...);
 my $soap    = XML::Compile::SOAP11::Client->new(...);
 my $send    = $soap->compileMessage('SENDER',   style => $style, ...);
 my $get     = $soap->compileMessage('RECEIVER', style => $style, ...);

 # Per RPC procedure
 my $myproc = $soap->compileClient
   ( name   => 'MyProc'
   , encode => $send, decode => $get, transport => $http
   , rpcout => $outtype, rpcin => $intype
   );

 my $answer = $myproc->(@parameters);   # as document style

Actually, the C<< @paramers >> are slightly less flexible as in document
style SOAP.  If you use header blocks, then the called CODE reference
will not be able to distinguish between parameters for the RPC block and
parameters for the header blocks.  Therefore, in that situation, you
MUST separate the rpc data explicitly as one argument.

  my $answer = $trade_price
    ->( {symbol => 'IBM'}    # the RPC package implicit
      , transaction => 5     # in the header
      );

  my $answer = $trade_price  # RPC very explicit
    ->(rpc => {symbol => 'IBM'}, transaction => 5);

When the number of arguments is odd, the first is indicating the RPC
element, and the other pairs refer to header blocks.

The C<$answer> structure may contain a C<Fault> entry, or a decoded
datastructure with the results of your query.  One call using
M<Data::Dumper> will show you more than I can explain in a few hundred
words.

=subsection Calling the server (SOAP-RPC style, encoded)

SOAP-RPC is a simplification of the interface description: basically,
the interface is not described at all but left to good communication
between the client and server authors.  In strongly typed languages,
this is quite simple to enforce: the client side and server side use
the same (remote) method prototype.  However, in Perl we are blessed
without these typed prototypes...

The approach of M<SOAP::Lite>, is to guess the types of the passed
parameters.  For instance, "42" will get passed as Integer.  This
may lead to nasty problems: a float parameter "2.0" will get passed
as integer "2", or a string representing a house number "8" is passed
as an number.  This may not be accepted by the SOAP server.

So, using SOAP-RPC in M<XML::Compile::SOAP> will ask a little more
effort from you: you have to state parameter types explicitly.

=subsection Faults (Document and RPC style)

Faults and headerfaults are a slightly different story: the type which
is specified with them is not of the fault XML node itself, but of the
C<detail> sub-element within the standard fault structure.

When producing the data for faults, you must be aware of the fact that
the structure is different for SOAP1.1 and SOAP1.2.  When interpreting
faults, the same problems are present, although the implementation
tries to help you by hiding the differences.

Check whether SOAP1.1 or SOAP1.2 is used by looking for a C<faultcode>
(SOAP1.1) or a C<Code> (SOAP1.2) field in the data:

  if(my $fault = $got->{Fault})
  {  if($fault->{faultcode}) { ... SOAP1.1 ... }
     elsif($fault->{Code})   { ... SOAP1.2 ... }
     else { die }
  }

In either protocol case, the following will get you at a compatible
structure in two steps:

  if(my $fault = $got->{Fault})
  {   my $decoded = $got->{$fault->{_NAME}};
      print $decoded->{code};
      ...
  }

See the respective manuals M<XML::Compile::SOAP11> and
M<XML::Compile::SOAP12> for the hairy details.  But one thing can be said:
when the fault is declared formally, then the C<_NAME> will be the name
of that part.

=section SOAP without WSDL (Document style)

See the manual page of M<XML::Compile::WSDL11> to see how simple you
can use this module when you have a WSDL file at hand.  The creation of
a correct WSDL file is NOT SIMPLE.

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
server.  See M<XML::Compile::Transport::SOAPHTTP>, as one example.

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

=chapter TODO

On the moment, the following limitations exist:

=over 4

=item .
Only one real-life experiment with document style SOAP has been made:
see the examples directory.

=item .
Only SOAP1.1 sufficiently implemented (probably).  There are some
steps into SOAP1.2, but it is not yet tested nor ready to be tested.

=back

=cut

1;
