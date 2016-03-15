use warnings;
use strict;

package XML::Compile::SOAP;

use Log::Report          'xml-compile-soap';
use XML::Compile         ();
use XML::Compile::Util   qw(SCHEMA2001 SCHEMA2001i pack_type
   unpack_type type_of_node);
use XML::Compile::Cache  ();
use XML::Compile::SOAP::Util qw/:xop10 SOAP11ENC/;

use Time::HiRes          qw/time/;
use MIME::Base64         qw/decode_base64/;

# XML::Compile::WSA::Util often not installed
use constant WSA10 => 'http://www.w3.org/2005/08/addressing';

=chapter NAME
XML::Compile::SOAP - base-class for SOAP implementations

=chapter SYNOPSIS
 ** SOAP1.[12] and WSDL1.1 over HTTP

 # !!! The next steps are only required when you do not have
 # !!! a WSDL. See XML::Compile::WSDL11 if you have a WSDL.
 # !!! Without WSDL file, you need to do a lot manually

 use XML::Compile::SOAP11::Client;
 my $client = XML::Compile::SOAP11::Client->new;
 $client->schemas->importDefinitions(...);

 use XML::Compile::Util qw/pack_type/;
 my $h1el = pack_type $myns, $some_element;
 my $b1el = "{$myns}$other_element";  # same, less clean

 my $encode_query = $client->compileMessage
   ( 'SENDER'
   , style    => 'document'           # default
   , header   => [ h1 => $h1el ]
   , body     => [ b1 => $b1el ]
   , destination    => [ h1 => 'NEXT' ]
   , mustUnderstand => 'h1'
   );

 my $decode_response = $client->compileMessage
   ( 'RECEIVER'
   , header   => [ h2 => $h2el ]
   , body     => [ b2 => $b2el ]
   , faults   => [ ... ]
   );

 my $transport = XML::Compile::Transport::SOAPHTTP
    ->new(address => $server);
 my $http = $transport->compileClient(action => ...);

 my @query    = (h1 => ..., b1 => ...);
 my $request  = $encode_query->(@query);
 my ($response, $trace) = $http->($request);
 my $answer   = $decode_response->($response);

 use Data::Dumper;
 warn Dumper $answer;     # discover a HASH with h2 and b2!

 if($answer->{Fault}) ... # when an error was reported

 # Simplify your life: combine above into one call
 # Also in this case: if you have a WSDL, this is created
 # for you.   $wsdl->compileClient('MyFirstCall');

 my $call   = $client->compileClient
   ( kind      => 'request-response'  # default
   , name      => 'MyFirstCall'
   , encode    => $encode_query
   , decode    => $decode_response
   , transport => $http
   );

 # !!! Usage, with or without WSDL file the same

 my $result = $call->(@query)          # SCALAR only the result
 print $result->{h2}->{...};
 print $result->{b2}->{...};

 my ($result, $trace) = $call->(...);  # LIST will show trace
 # $trace is an XML::Compile::SOAP::Trace object

=chapter DESCRIPTION

This module handles the SOAP protocol.  The first implementation is
SOAP1.1 (F<http://www.w3.org/TR/2000/NOTE-SOAP-20000508/>), which is still
most often used.  The SOAP1.2 definition (F<http://www.w3.org/TR/soap12/>)
is provided via the separate distribution M<XML::Compile::SOAP12>.

Be aware that there are three kinds of SOAP:

=over 4
=item 1.
Document style (literal) SOAP, where there is a WSDL file which explicitly
types all out-going and incoming messages.  Very easy to use.

=item 2.
RPC style SOAP literal.  The body of the message has an extra element
wrapper, but the content is also well defined.

=item 3.
RPC style SOAP encoded.  The sent data is nowhere described formally.
The data is constructed in some ad-hoc way.
=back

Don't forget to have a look at the examples in the F<examples/> directory
included in the distribution.

Please support my development work by submitting bug-reports, patches
and (if available) a donation.

=chapter METHODS

=section Constructors

=method new %options
Create a new SOAP object.  You have to instantiate either the SOAP11 or
SOAP12 sub-class of this, because there are quite some differences (which
can be hidden for you)

=option  media_type MIMETYPE
=default media_type C<application/soap+xml>

=option  schemas    C<XML::Compile::Cache> object
=default schemas    created internally
Use this when you have already processed some schema definitions.  Otherwise,
you can add schemas later with C<< $soap->schemas->importDefinitions() >>
The Cache object must have C<any_element> and C<any_attribute> set to
C<'ATTEMPT'>

=cut

sub new($@)
{   my $class = shift;

    error __x"you can only instantiate sub-classes of {class}"
        if $class eq __PACKAGE__;

    (bless {}, $class)->init( {@_} );
}

sub init($)
{   my ($self, $args) = @_;
    $self->{XCS_mime}   = $args->{media_type} || 'application/soap+xml';

    my $schemas = $self->{XCS_schemas} = $args->{schemas}
     || XML::Compile::Cache->new(allow_undeclared => 1
          , any_element => 'ATTEMPT', any_attribute => 'ATTEMPT');

    UNIVERSAL::isa($schemas, 'XML::Compile::Cache')
        or panic "schemas must be a Cache object";

    $self;
}

sub _initSOAP($)
{   my ($thing, $schemas) = @_;
    return $thing
        if $schemas->{did_init_SOAP}++;   # ugly

    $schemas->addPrefixes(xsd => SCHEMA2001, xsi => SCHEMA2001i);

    $thing;
}

=c_method register $uri, $envns
Declare an operation type, being an (WSDL specific) $uri and envelope
namespace.
=cut

{   my (%registered, %envelope);
    sub register($)
    { my ($class, $uri, $env, $opclass) = @_;
      $registered{$uri} = $class;
      $envelope{$env}   = $opclass if $env;
    }
    sub plugin($)       { $registered{$_[1]} }
    sub fromEnvelope($) { $envelope{$_[1]} }
    sub registered($)   { values %registered }
}

#--------------------
=section Accessors
=method version 
=method mediaType 
=cut

sub version()   {panic "not implemented"}
sub mediaType() {shift->{XCS_mime}}

=method schemas 
Returns the M<XML::Compile::Cache> object which contains the
knowledge about the types.
=cut

sub schemas() {
use Carp 'cluck';
ref $_[0] or cluck;
shift->{XCS_schemas}}

#--------------------
=section Single message

=method compileMessage <'SENDER'|'RECEIVER'>, %options
The payload is defined explicitly, where all headers and bodies are
described in detail.  When you have a WSDL file, these ENTRIES are
generated automatically, but can be modified and extended (WSDL files
are often incomplete)

To make your life easy, the ENTRIES use a label (a free to choose key,
the I<part name> in WSDL terminology), to ease relation of your data with
the type where it belongs to.  The element of an entry (the value) is
defined as an C<any> element in the schema, and therefore you will need
to explicitly specify the element to be processed.

As %options, you can specify any listed here, but also anything which is
accepted by M<XML::Compile::Schema::compile()>, like
C<< sloppy_integers => 1 >> and hooks.  These are applied to all header
and body elements (not to the SOAP wrappers)

=option  header ENTRIES|HASH
=default header C<undef>
ARRAY of PAIRS, defining a nice LABEL (free of choice but unique)
and an element type name.  The LABEL will appear in the Perl HASH, to
refer to the element in a simple way.

The element type is used to construct a reader or writer.  You may also
create your own reader or writer, and then pass a compatible CODE reference.

=option  body   ENTRIES|HASH
=default body   []
ARRAY of PAIRS, defining a nice LABEL (free of choice but unique, also
w.r.t. the header and fault ENTRIES) and an element type name or CODE
reference.  The LABEL will appear in the Perl HASH only, to be able to
refer to a body element in a simple way.

=option  procedure TYPE
=default procedure C<undef>
Required in rpc style, when there is no C<body> which contains the
procedure name (when the RPC info does not come from a WSDL)

=option  faults ENTRIES|HASH
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

=option  destination ARRAY-OF-PAIRS
=default destination []
Writers only.  Indicate who the target of the header entry is.
By default, the end-point is the destination of each header element.

The ARRAY contains a LIST of key-value pairs, specifying an entry label
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

=cut

sub compileMessage($@)
{   my ($self, $direction, %args) = @_;
    $args{style} ||= 'document';

      $direction eq 'SENDER'   ? $self->_sender(%args)
    : $direction eq 'RECEIVER' ? $self->_receiver(%args)
    : error __x"message direction is 'SENDER' or 'RECEIVER', not `{dir}'"
         , dir => $direction;
}

=ci_method messageStructure $xml
Returns a HASH with some collected information from a complete SOAP
message (XML::LibXML::Document or XML::LibXML::Element).  Currenty,
the HASH contains a C<header> and a C<body> key, with each an ARRAY
of element names which where found in the header resp. body.
=cut

sub messageStructure($)
{   my ($thing, $xml) = @_;
    my $env = $xml->isa('XML::LibXML::Document') ? $xml->documentElement :$xml;

    my (@header, @body, $wsa_action);
    if(my ($header) = $env->getChildrenByLocalName('Header'))
    {   @header = map { $_->isa('XML::LibXML::Element') ? type_of_node($_) : ()}
           $header->childNodes;

        if(my $wsa = ($header->getChildrenByTagNameNS(WSA10, 'Action'))[0])
        {   $wsa_action = $wsa->textContent;
            for($wsa_action) { s/^\s+//; s/\s+$//; s/\s{2,}/ /g }
        }
    }

    if(my ($body) = $env->getChildrenByLocalName('Body'))
    {   @body = map { $_->isa('XML::LibXML::Element') ? type_of_node($_) : () }
           $body->childNodes;
    }

    +{ header     => \@header
     , body       => \@body
     , wsa_action => $wsa_action
     };
}

#------------------------------------------------
# Sender

sub _sender(@)
{   my ($self, %args) = @_;

    error __"option 'role' only for readers"  if $args{role};
    error __"option 'roles' only for readers" if $args{roles};

    my $hooks = $args{hooks}   # make copy of calling hook-list
      = $args{hooks} ? [ @{$args{hooks}} ] : [];

    my @mtom;
    push @$hooks, $self->_writer_xop_hook(\@mtom);
    my ($body,  $blabels) = $args{create_body}
       ? $args{create_body}->($self, %args)
       : $self->_writer_body(\%args);
    my ($faults, $flabels) = $self->_writer_faults(\%args, $args{faults});

    my ($header, $hlabels) = $self->_writer_header(\%args);
    push @$hooks, $self->_writer_hook($self->envType('Header'), @$header);

    my $style = $args{style} || 'none';
    if($style eq 'document')
    {   push @$hooks, $self->_writer_hook($self->envType('Body')
          , @$body, @$faults);
    }
    elsif($style eq 'rpc')
    {   my $procedure = $args{procedure} || $args{body}{procedure}
            or error __x"sending operation requires procedure name with RPC";

        my $use = $args{use} || $args{body}{use} || 'literal';
        my $bt  = $self->envType('Body');
        push @$hooks, $use eq 'literal'
           ? $self->_writer_body_rpclit_hook($bt, $procedure, $body, $faults)
           : $self->_writer_body_rpcenc_hook($bt, $procedure, $body, $faults);
    }
    else
    {   error __x"unknown style `{style}'", style => $style;
    }

    #
    # Pack everything together in one procedure
    #

    my $envelope = $self->_writer($self->envType('Envelope'), %args);

    sub
    {   my ($values, $charset) = ref $_[0] eq 'HASH' ? @_ : ( {@_}, undef);
        my %copy  = %$values;  # do not destroy the calling hash
        my $doc   = delete $copy{_doc}
          || XML::LibXML::Document->new('1.0', $charset || 'UTF-8');

        my %data;
        $data{$_}  = delete $copy{$_} for qw/Header Body/;
        $data{Body} ||= {};

        foreach my $label (@$hlabels)
        {   exists $copy{$label} or next;
            $data{Header}{$label} ||= delete $copy{$label};
        }

        foreach my $label (@$blabels, @$flabels)
        {   exists $copy{$label} or next;
            $data{Body}{$label} ||= delete $copy{$label};
        }

        if(@$blabels==2 && !keys %{$data{Body}} ) # ignore 'Fault'
        {  # even when no params, we fill at least one body element
            $data{Body}{$blabels->[0]} = \%copy;
        }
        elsif(keys %copy)
        {   trace __x"available blocks: {blocks}",
                 blocks => [ sort @$hlabels, @$blabels, @$flabels ];
            error __x"call data not used: {blocks}", blocks => [keys %copy];
        }

        @mtom = ();   # filled via hook

#use Data::Dumper;
#warn Dumper \%data;
        my $root = $envelope->($doc, \%data)
            or return;

        $doc->setDocumentElement($root);

        return ($doc, \@mtom)
            if wantarray;

        @mtom == 0
            or error __x"{nr} XOP objects lost in sender"
                 , nr => scalar @mtom;
        $doc;
    };
}

sub _writer_hook($$@)
{   my ($self, $type, @do) = @_;

    my $code = sub
     {  my ($doc, $data, $path, $tag) = @_;
        UNIVERSAL::isa($data, 'XML::LibXML::Element')
            and return $data;

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

        my $node = $doc->createElement($tag);
        $node->appendChild($_) for @childs;
        $node;
      };

   +{ type => $type, replace => $code };
}

sub _writer_body_rpclit_hook($$$$$)
{   my ($self, $type, $procedure, $params, $faults) = @_;
    my @params   = @$params;
    my @faults   = @$faults;
    my $schemas  = $self->schemas;

    my $proc     = $schemas->prefixed($procedure);
    my ($prefix) = split /\:/, $proc;
    my $prefdef  = $schemas->prefix($prefix);
    my $proc_ns  = $prefdef->{uri};
    $prefdef->{used} = 0;

    my $code   = sub
     {  my ($doc, $data, $path, $tag) = @_;
        UNIVERSAL::isa($data, 'XML::LibXML::Element')
            and return $data;

        my %data = %$data;
        my @f = @faults;
        my (@fchilds, @pchilds);
        while(@f)
        {   my ($k, $c) = (shift @f, shift @f);
            my $v = delete $data{$k};
            push @fchilds, $c->($doc, $v) if defined $v;
        }
        my @p = @params;
        while(@p)
        {   my ($k, $c) = (shift @p, shift @p);
            my $v = delete $data{$k};
            push @pchilds, $c->($doc, $v) if defined $v;
        }
        warning __x"unused values {names}", names => [keys %data]
            if keys %data;

        my $proc = $doc->createElement($proc);
        $proc->setNamespace($proc_ns, $prefix, 0);
        $proc->setAttribute("SOAP-ENV:encodingStyle", SOAP11ENC);

        $proc->appendChild($_) for @pchilds;

        my $node = $doc->createElement($tag);
        $node->appendChild($proc);
        $node->appendChild($_) for @fchilds;
        $node;
     };

   +{ type => $type, replace => $code };
}

sub _writer_header($)
{   my ($self, $args) = @_;
    my (@rules, @hlabels);

    my $header  = $args->{header} || [];
    my $soapenv = $self->envelopeNS;

    foreach my $h (ref $header eq 'ARRAY' ? @$header : $header)
    {   my $part    = $h->{parts}[0];
        my $label   = $part->{name};
        my $element = $part->{element};
        my $code    = $part->{writer}
         || $self->_writer($element, %$args
              , include_namespaces => sub {$_[0] ne $soapenv && $_[2]});

        push @rules, $label => $code;
        push @hlabels, $label;
    }

    (\@rules, \@hlabels);
}

sub _writer_body($)
{   my ($self, $args) = @_;
    my (@rules, @blabels);

    my $body  = $args->{body} || $args->{fault};
    my $use   = $body->{use}  || 'literal';
#   $use eq 'literal'
#       or error __x"RPC encoded not supported by this version";

    my $parts = $body->{parts} || [];
    my $style = $args->{style};
    local $args->{is_rpc_enc} = $style eq 'rpc' && $use eq 'encoded';

    foreach my $part (@$parts)
    {   my $label  = $part->{name};
        my $code;
        if($part->{element})
        {   $code  = $self->_writer_body_element($args, $part);
        }
        elsif(my $type = $part->{type})
        {   $code  = $self->_writer_body_type($args, $part);
            $label = (unpack_type $part->{name})[1];
        }
        else
        {   error __x"part {name} has neither `element' nor `type' specified"
              , name => $label;
        }

        push @rules, $label => $code;
        push @blabels, $label;
    }

    (\@rules, \@blabels);
}

sub _writer_body_element($$)
{   my ($self, $args, $part) = @_;
    my $element = $part->{element};
    my $soapenv = $self->envelopeNS;

    $part->{writer} ||= $self->_writer
      ( $element, %$args
      , include_namespaces  => sub {$_[0] ne $soapenv && $_[2]}
      , xsi_type_everywhere => $args->{is_rpc_enc}
      );
}

sub _writer_body_type($$)
{   my ($self, $args, $part) = @_;

    $args->{style} eq 'rpc'
        or error __x"part {name} uses `type', only for rpc not {style}"
             , name => $part->{name}, style => $args->{style};

    return $part->{writer}
        if $part->{writer};

    my $soapenv = $self->envelopeNS;

    $part->{writer} = $self->schemas->compileType
      ( WRITER  => $part->{type}, %$args, element => $part->{name}
      , include_namespaces => sub {$_[0] ne $soapenv && $_[2]}
      , xsi_type_everywhere => $args->{is_rpc_enc}
      );
}

sub _writer_faults($) { ([], []) }

sub _writer_xop_hook($)
{   my ($self, $xop_objects) = @_;

    my $collect_objects = sub {
        my ($doc, $val, $path, $tag, $r) = @_;
        return $r->($doc, $val)
            unless UNIVERSAL::isa($val, 'XML::Compile::XOP::Include');

        my $node = $val->xmlNode($doc, $path, $tag); 
        push @$xop_objects, $val;
        $node;
      };

   +{ type => 'xsd:base64Binary', replace => $collect_objects };
}

#------------------------------------------------
# Receiver

sub _receiver(@)
{   my ($self, %args) = @_;

    error __"option 'destination' only for writers"
        if $args{destination};

    error __"option 'mustUnderstand' only for writers"
        if $args{understand};

# roles are not checked (yet)
#   my $roles  = $args{roles} || $args{role} || 'ULTIMATE';
#   my @roles  = ref $roles eq 'ARRAY' ? @$roles : $roles;

    my $header = $self->_reader_header(\%args);

    my $xops;  # forward backwards pass-on
    my $body   = $self->_reader_body(\%args, \$xops);

    my $style  = $args{style} || 'document';
    my $kind   = $args{kind}  || 'request-response';
    if($style eq 'rpc')
    {   my $procedure = $args{procedure} || $args{body}{procedure};
        keys %{$args{body}}==0 || $procedure
            or error __x"receiving operation requires procedure name with RPC";

        my $use = $args{use} || $args{body}{use} || 'literal';
#warn "RPC READER BODY $use";
        $body = $use eq 'literal'
           ? $self->_reader_body_rpclit_wrapper($procedure, $body)
           : $self->_reader_body_rpcenc_wrapper($procedure, $body);
    }
    elsif($style ne 'document')
    {   error __x"unknown style `{style}'", style => $style;
    }

    # faults are always possible
    push @$body, $self->_reader_fault_reader;

    my @hooks  = @{$self->{hooks} || []};
    push @hooks
      , $self->_reader_hook($self->envType('Header'), $header)
      , $self->_reader_hook($self->envType('Body'),   $body  );

    #
    # Pack everything together in one procedure
    #

    my $envelope = $self->_reader($self->envType('Envelope')
      , %args, hooks => \@hooks);

    # add simplified fault information
    my $faultdec = $self->_reader_faults(\%args, $args{faults});

    sub
    {   (my $xml, $xops) = @_;
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

sub _reader_hook($$)
{   my ($self, $type, $do) = @_;
    my %trans = map +($_->[1] => [ $_->[0], $_->[2] ]), @$do; # we need copies
    my $envns = $self->envelopeNS;

    my $code  = sub
     {  my ($xml, $trans, $path, $label) = @_;
        my %h;
        foreach my $child ($xml->childNodes)
        {   next unless $child->isa('XML::LibXML::Element');
            my $type = type_of_node $child;
            if(my $t = $trans{$type})
            {   my ($label, $code) = @$t;
                my $v = $code->($child) or next;
                   if(!defined $v)        { }
                elsif(!exists $h{$label}) { $h{$label} = $v }
                elsif(ref $h{$label} eq 'ARRAY') { push @{$h{$label}}, $v }
                else { $h{$label} = [ $h{$label}, $v ] }
                next;
            }
            else
            {   $h{$type} = $child;
                trace __x"node {type} not understood, expected are {has}",
                    type => $type, has => [sort keys %trans];
            }

            return ($label => $self->replyMustUnderstandFault($type))
                if $child->getAttributeNS($envns, 'mustUnderstand') || 0;
        }
        ($label => \%h);
     };

   +{ type    => $type
    , replace => $code
    };
 
}

sub _reader_body_rpclit_wrapper($$)
{   my ($self, $procedure, $body) = @_;
    my %trans = map +($_->[1] => [ $_->[0], $_->[2] ]), @$body;

    # this should use key_rewrite, but there is no $wsdl here
    # my $label = $wsdl->prefixed($procedure);
    my $label = (unpack_type $procedure)[1];

    my $code = sub
      { my $xml = shift or return {};
        my %h;
        foreach my $child ($xml->childNodes)
        {   $child->isa('XML::LibXML::Element') or next;
            my $type = type_of_node $child;
            if(my $t = $trans{$type})
                 { $h{$t->[0]} = $t->[1]->($child) }
            else { $h{$type} = $child }
        }
        \%h;
      };

    [ [ $label => $procedure => $code ] ];
}

sub _reader_header($)
{   my ($self, $args) = @_;
    my $header = $args->{header} || [];
    my @rules;

    foreach my $h (@$header)
    {   my $part    = $h->{parts}[0];
        my $label   = $part->{name};
        my $element = $part->{element};
        my $code    = $part->{reader} ||= $self->_reader($element, %$args);
        push @rules, [$label, $element, $code];
    }

    \@rules;
}

sub _reader_body($$)
{   my ($self, $args, $refxops) = @_;
    my $body  = $args->{body};
    my $parts = $body->{parts} || [];
    my @hooks = @{$args->{hooks} || []};
    push @hooks, $self->_reader_xop_hook($refxops);
    local $args->{hooks} = \@hooks;

    my @rules;
    foreach my $part (@$parts)
    {   my $label = $part->{name};

        my ($t, $code);
        if($part->{element})
        {   ($t, $code) = $self->_reader_body_element($args, $part) }
        elsif($part->{type})
        {   ($t, $code) = $self->_reader_body_type($args, $part) }
        else
        {   error __x"part {name} has neither element nor type specified"
              , name => $label;
        }
        push @rules, [ $label, $t, $code ];
    }

#use Data::Dumper;
#warn "RULES=", Dumper \@rules, $parts;
    \@rules;
}

sub _reader_body_element($$)
{   my ($self, $args, $part) = @_;

    my $element = $part->{element};
    my $code    = $part->{reader} || $self->_reader($element, %$args);

    ($element, $code);
}

sub _reader_body_type($$)
{   my ($self, $args, $part) = @_;
    my $name = $part->{name};

    $args->{style} eq 'rpc'
        or error __x"only rpc style messages can use 'type' as used by {part}"
              , part => $name;

    return $part->{reader}
        if $part->{reader};

    my $type = $part->{type};
    my ($ns, $local) = unpack_type $type;

    my $r = $part->{reader} =
        $self->schemas->compileType
          ( READER => $type, %$args
          , element => $name # $args->{body}{procedure}
          );

    ($name, $r);
}

sub _reader_faults($)
{   my ($self, $args) = @_;
    sub { shift };
}

sub _reader_xop_hook($)
{   my ($self, $refxops) = @_;

    my $xop_merge = sub
      { my ($xml, $args, $path, $type, $r) = @_;
        if(my $incls = $xml->getElementsByTagNameNS(XOP10, 'Include'))
        {   my $href = $incls->shift->getAttribute('href') || ''
                or return ($type => $xml);

            $href =~ s/^cid://;
            my $xop  = $$refxops->{$href}
                or return ($type => $xml);

            return ($type => $xop);
        }

        ($type => decode_base64 $xml->textContent);
      };

   +{ type => 'xsd:base64Binary', replace => $xop_merge };
}

sub _reader(@) { shift->schemas->reader(@_) }
sub _writer(@) { shift->schemas->writer(@_) }

#------------------------------------------------

=section Helpers

=section Transcoding

=method roleURI $uri|STRING
Translates actor/role/destination abbreviations into URIs. Various
SOAP protocol versions have different pre-defined STRINGs, which can
be abbreviated for readibility.  Returns the unmodified $uri in
all other cases.

SOAP11 only defines C<NEXT>.  SOAP12 defines C<NEXT>, C<NONE>, and
C<ULTIMATE>.
=cut

sub roleURI($) { panic "not implemented" }

=method roleAbbreviation $uri
Translate a role $uri into a simple string, if predefined.  See
M<roleURI()>.
=cut

sub roleAbbreviation($) { panic "not implemented" }

=method replyMustUnderstandFault $type
Produce an error structure to be returned to the sender.
=cut

sub replyMustUnderstandFault($) { panic "not implemented" }

#----------------------

=chapter DETAILS

=section SOAP introduction

Although the specifications of SOAP1.1 and WSDL1.1 are thin, the number
of special constructs are many. And, of course, all are poorly documented.
SOAP 1.2 has a much better specification, but is not used a lot.  I have
not seen WSDL2 in real life.

WSDL defines two kinds of messages: B<document> style SOAP and B<rpc>
style SOAP.  In document style SOAP, the messages are described in
great detail in the WSDL: the message components are all defined in
Schema's. The worst things you can (will) encounter are C<any> schema
elements which require additional manual processing.

C<RPC Literal> behaves very much the same way as document style soap,
but has one extra wrapper inside the Body of the message.

C<Encoded SOAP-RPC>, however, is a very different ball-game.  It is simple
to use with strongly typed languages, to exchange data when you create both
the client software and the server software.  You can simply autogenerate
the data encoding.  Clients written by third parties have to find the
documentation on how to use the encoded  RPC call in some other way... in
text, if they are lucky; the WSDL file does not contain the prototype
of the procedures, but that doesn't mean that they are free-format.

B<Encoded RPC> messages are shaped to the procedures which are
being called on the server.  The body of the sent message contains the
ordered list of parameters to be passed as 'in' and 'in/out' values to the
remote procedure.  The body of the returned message lists the result value
of the procedure, followed by the ordered 'out' and 'in/out' parameters.

=section Supported servers

Only the commercial hype speaks about SOAP in very positive words.
However, the "industry quality" of these modern "technologies" clearly
demonstrates the lack of education and experience most programmers and
designers have.  This is clearly visible in many, many bugs you will
encounter when working with schemas and WSDLs.

Interoperability of SOAP clients and servers is more "trial and error"
and "manually fixing" than it should be.  For instance, a server may
report internal server errors back to the client... but a WSDL does not
tell you which namespace/schema is used for these errors.  Both BEA and
SharePoint servers produce illegal SOAP responses!  It is a sad story.

To be able to install some fixes, you can specify a server type via
M<XML::Compile::SOAP::Operation::new(server_type)> or
M<XML::Compile::WSDL11::new(server_type)>.
The following server types are currently understood:

=over 4
=item * C<BEA>, Oracle
=item * C<SharePoint>, MicroSoft
=item * C<XML::Compile::Daemon>
=back

Examples:

  my $wsdl = XML::Compile::WSDL11->new($wsdlfn, server_type => 'SharePoint');
  my $op   = XML::Compile::SOAP11::Operation->new(..., server_type => 'BEA');

=section Naming types and elements

XML uses namespaces: URIs which are used as constants, grouping a set
of type and element definitions.  By using name-spaces, you can avoid
name clashes, which have frustrated many projects in the past when they
grew over a certain size... at a certain size, it becomes too hard to
think of good distinguishable names.  In such case, you must be happy
when you can place those names in a context, and use the same naming in
separate contexts without confusion.

That being said: XML supports both namespace- and non-namespace elements
and schema's; and of cause many mixed cases.  It is by far preferred to
use namespace schemas only. In a schema XSD file, look for the
C<targetNamespace> attribute of the C<schema> element: if present, it
uses namespaces.

In XML data, it is seen as a hassle to write the full length of the URI
each time that a namespace is addressed.  For this reason, prefixes are
used as abbreviations for the namespace URI.  In programs, you can simply
assign short variable names to long URIs, so we do not need that trick.

Within your program, you use

  $MYSN = 'long URI of namespace';
  ... $type => "{$MYNS}typename" ...

or nicer

  use XML::Compile::Util qw/pack_type/;
  use constant MYNS => 'some uri';
  ... $type => pack_type(MYNS, 'typename') ...

The M<XML::Compile::Util> module provides a helpful methods and constants,
as does the M<XML::Compile::SOAP::Util>.

=section Client and Server implementations

To learn how to create clients in SOAP, read the DETAILS section in
M<XML::Compile::SOAP::Client>.  The client implementation is platform
independent.

Servers can be created with the external M<XML::Compile::SOAP::Daemon>
distribution. Those servers are based on M<Net::Server>. Can be used
to create a test-server in a few minutes... or production server.

Don't forget to have a look at the examples in the F<examples/> directory
included in the distribution.

=section Use of wildcards (any and anyAttribute)

Start reading about wildcards in M<XML::Compile>. When you receive a
message which contains "ANY" elements, an attempt will be made to decode
it automatically. Sending messages which contain "ANY" fields is
harder... you may try hooks or something more along these lines:

   my $doc = XML::LibXML::Document->new('1.0', 'UTF-8');
   my $type    = pack_type $ns, $local;
   my $node    = $wsdl->writer($type)->($doc, $value);
   my $message = { ..., $type => $node };

   my $call = $wsdl->compileClient('myOpToCall');
   my ($answer, $trace) = $call->(_doc => $doc, message => $message);

Here, C<$type> is the type of the element which needs to be filled in
on a spot where the schema defines an "ANY" element. You need to include
the full typename as key in the HASH (on the right spot) and a fully
prepared C<$node>, an M<XML::LibXML::Element>, as the value.

You see that the C<$doc> which is created to produce the special node
in the message is also passed to the C<$call>. The call produces the
message which is sent and needs to use the same document object as the
node inside it. The chances are that when you forget to pass the C<$doc>
it still works... but you may get into characterset problems and such.

=cut

1;
