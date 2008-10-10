use warnings;
use strict;

package XML::Compile::SOAP;  #!!!

use Log::Report 'xml-compile-soap', syntax => 'SHORT';
use List::Util qw/min first/;
use XML::Compile::Util qw/odd_elements SCHEMA2001 unpack_type/;

=chapter NAME
XML::Compile::SOAP::Encoding - SOAP encoding

=chapter SYNOPSIS
 # see t/13enc11.t in the distribution for complex examples

 my $client = XML::Compile::SOAP11::Client->new();
 $client->startEncoding(...);  # loads this module

 # create: <SOAP-ENC:int>41</SOAP-ENC:int>
 my $xml = $client->enc(int => 41);

 # create: <SOAP-ENC:int id="hhtg">42</SOAP-ENC:int>
 my $xml = $client->enc(int => 42, 'hhtg');

 # create: <code xsi:type="xsd:int">43</code>
 my $int = pack_type SCHEMA2001, 'int';
 my $xml = $client->typed($int, code => 43);

 # create: <ref href="#id-1"/>  (xyz get's id if it hasn't)
 my $xml = $client->href('ref', $xyz);
 my $xml = $client->href('ref', $xyz, 'id-1');  # explicit label
 
 # create: <number>3</number>   (gets validated as well!)
 my $xml = $client->element($int, number => 3);

 # create one-dimensional array of ints
 my $xml = $client->array(undef, $int, \@xml);
 my $xml = $client->array('{myns}mylocal', $int, \@xml);

 # create multi-dimensional array
 my $xml = $client->multidim(undef, $int, $matrix);
 my $xml = $client->multidim('{myns}mylocal', $int, $matrix);

 # decode an incoming encoded structure (as far as possible)
 my $hash = $client->dec($xml);

=chapter DESCRIPTION
This module loads extra functionality into the M<XML::Compile::SOAP>
namespace: all kinds of methods which are used to SOAP-encode data.

The loading is triggered by calling M<startEncoding()>.  In threaded
applications, you may wish to call that method once before the fork(),
such that not each threads or forked process needs to compile the
code again.  Of course, you can also C<use> this package explicitly.

=chapter METHODS

=section Transcoding
SOAP defines encodings, especially for SOAP-RPC.

=subsection Encoding

=method startEncoding OPTIONS
This needs to be called before any encoding routine, because it
initializes the internals.  Each call will reset all compiled
cached translator routines.

When you use the standard RPC-encoded interface, this will be
called for you.

=requires doc XML::LibXML::Document

=option  prefixes HASH|ARRAY
=default prefixes {}
Like M<XML::Compile::Schema::compile(prefixes)>, this can
be a HASH (see example) or an ARRAY with prefix-uri pairs.

=option  namespaces HASH|ARRAY
=default namespaces {}
Pre release 0.74 name for option C<prefixes>.

=example
 my %ns;
 $ns{$MYNS} = {uri => $MYNS, prefix => 'm'};
 $soap->startEncoding(doc => $doc, prefixes => \%ns);

 # or
 $soap->startEncoding(doc => $doc, prefixes => [ m => $MYNS ]);
 
=cut

# startEncoding is always implemented, loading this class
# the {enc} settings are temporary; live shorter than the object.
sub _init_encoding($)
{   my ($self, $args) = @_;
    my $doc = $args->{doc};
    $doc && UNIVERSAL::isa($doc, 'XML::LibXML::Document')
        or error __x"encoding required an XML document to work with";

    my $ns = $args->{prefixes} || $args->{namespaces} || {};
    if(ref $ns eq 'ARRAY')
    {   my @ns = @$ns;
        $ns    = {};
        while(@ns)
        {   my ($prefix, $uri) = (shift @ns, shift @ns);
            $ns->{$uri} = {uri => $uri, prefix => $prefix};
        }
    }

    $args->{prefixes} = $ns;
    $self->{enc} = $args;

    $self->encAddNamespaces
      ( xsd => $self->schemaNS
      , xsi => $self->schemaInstanceNS
      );

    $self;
}

=method encAddNamespaces PAIRS
Add prefix definitions for this one encoding cyclus.  Each time
M<startEncoding()> is called, the table is reset.  The namespace
table is returned.

=method encAddNamespace PAIRS
Convenience alternative for M<encAddNamespaces()>.
=cut

sub encAddNamespaces(@)
{   my $prefs = shift->{enc}{prefixes};
    while(@_)
    {   my ($prefix, $uri) = (shift, shift);
        $prefs->{$uri} = {uri => $uri, prefix => $prefix};
    }
    $prefs;
}

sub encAddNamespace(@) { shift->encAddNamespaces(@_) }

=method prefixed TYPE|(NAMESPACE,LOCAL)
Translate a NAMESPACE-LOCAL combination (which may be represented as
a packed TYPE) into a prefixed notation.

The complication is that the NAMESPACE may not naturally have a prefixed
assigned to it: the produced SOAP message is the result of compilation,
and only the namespaces which are registered to be used during compile-time
are added to the list on the top-level.  See M<compileMessage(prefixes)>.
=cut

sub prefixed($;$)
{   my $self = shift;
    my ($ns, $local) = @_==2 ? @_ : unpack_type $_[0];
    length $ns or return $local;

    my $def  =  $self->{enc}{prefixes}{$ns}
        or error __x"namespace prefix for your {ns} not defined", ns => $ns;

    $def->{prefix}.':'.$local;
}

=method enc LOCAL, VALUE, [ID]
In the SOAP specification, encoding types are defined: elements
which do not have a distinguishable name but use the type of the
data as name.  Yep, ugly!

=example
  my $xml = $soap->enc('int', 43);
  my $xml = $soap->enc(int => 43);
  print $xml->toString;
    # <SOAP-ENC:int>43</SOAP-ENC:int>

  my $xml = $soap->enc('int', 42, id => 'me');
  my $xml = $soap->enc(int => 42, id => 'me');
  print $xml->toString;
    # <SOAP-ENC:int id="me">42</SOAP-ENC:int>
=cut

sub enc($$$)
{   my ($self, $local, $value, $id) = @_;
    my $enc   = $self->{enc};
    my $type  = pack_type $self->encodingNS, $local;

    my $write = $self->{writer}{$type} ||= $self->schemas->compile
      ( WRITER   => $type
      , prefixes => $enc->{prefixes}
      , include_namespaces => 0
      );

    $write->($enc->{doc}, {_ => $value, id => $id} );
}

=method typed TYPE, NAME, VALUE
A "typed" element shows its type explicitly, via the "xsi:type" attribute.
The VALUE will get processed via an auto-generated XML::Compile writer,
so validated.  The processing is cashed.

When VALUE already is an M<XML::LibXML::Element>, then no processing
nor value checking will be performed.  The NAME will be ignored.

If the TYPE is not qualified, then it is interpreted as basic type, as
defined by the selected schema (see M<new(schema_ns)>).  If you explicitly
need a non-namespace typed item, then use an empty namespace.  In any
case, the type must be defined and the value is validated.

=examples

 my $xml = $soap->typed(int => count => 5);
 my $xml = $soap->typed(pack_type(SCHEMA1999, 'int'), count => 5);

 my $xml = $soap->typed(pack_type('', 'mine'), a => 1);
 my $xml = $soap->typed('{}mine'), a => 1); #same

=cut

sub typed($$$)
{   my ($self, $type, $name, $value) = @_;
    my $enc = $self->{enc};
    my $doc = $enc->{doc};

    my $showtype;
    if($type =~ s/^\{\}//)
    {   $showtype = $type;
    }
    else
    {   my ($tns, $tlocal) = unpack_type $type;
        unless(length $tns)
        {   $tns = $self->schemaNS;
            $type = pack_type $tns, $tlocal;
        }
        $showtype = $self->prefixed($tns, $tlocal);
    }

    my $el = $self->element($type, $name, $value);
    my $typedef = $self->prefixed($self->schemaInstanceNS, 'type');
    $el->setAttribute($typedef, $showtype);
    $el;
}

=method struct TYPE, CHILDS
Create a structure, an element with childs.  The CHILDS must be fully
prepared M<XML::LibXML::Element> objects.
=cut

sub struct($@)
{   my ($self, $type, @childs) = @_;
    my $typedef = $self->prefixed($type);
    my $doc     = $self->{enc}{doc};
    my $struct  = $doc->createElement($typedef);
    $struct->addChild($_) for @childs;
    $struct;
}

=method element TYPE, NAME, VALUE
Create an element.  The NAME is for node, where a namespace component
is translated into a prefix.  When you wish for a C<type> attribute,
use M<typed()>.

When the TYPE does not contain a namespace indication, it is taken
in the selected schema namespace.  If the VALUE already is a
M<XML::LibXML::Element>, then that one is used (and the NAME ignored).
=cut

sub element($$$)
{   my ($self, $type, $name, $value) = @_;

    return $value
        if UNIVERSAL::isa($value, 'XML::LibXML::Element');

    my $enc = $self->{enc};
    my $doc = $enc->{doc};

    $type = pack_type $self->schemaNS, $type   # make absolute
        if $type !~ m/^\{/;

    my $el  = $doc->createElement($name);
    my $write = $self->{writer}{$type} ||= $self->schemas->compile
      ( WRITER   => $type
      , prefixes => $enc->{prefixes}
      , include_namespaces => 0
      );

    $value = $write->($doc, $value);
    $el->addChild($value) if defined $value;
    $el;
}

=method href NAME, ELEMENT, [ID]
Create a reference element with NAME to the existing ELEMENT.  When the
ELEMENT does not have an "id" attribute yet, then ID will be used.  In
case not ID was specified, then one is generated.
=cut

my $id_count = 0;
sub href($$$)
{   my ($self, $name, $to, $prefid) = @_;
    my $id  = $to->getAttribute('id');
    unless(defined $id)
    {   $id = defined $prefid ? $prefid : 'id-'.++$id_count;
        $to->setAttribute(id => $id);
    }

    my $ename = $self->prefixed($name);
    my $el  = $self->{enc}{doc}->createElement($ename);
    $el->setAttribute(href => "#$id");
    $el;
}

=method nil [TYPE], NAME
Create an element with NAME which explicitly has the C<xsi:nil> attribute.
If the NAME is full (has a namespace to it), it will be translated into
a QNAME, otherwise, it is considered not namespace qualified.

If a TYPE is given, then an explicit type parameter is added.
=cut

sub nil($;$)
{   my $self = shift;
    my ($type, $name) = @_==2 ? @_ : (undef, $_[0]);
    my ($ns, $local) = unpack_type $name;

    my $doc  = $self->{enc}{doc};
    my $el
      = $ns
      ? $doc->createElementNS($ns, $local)
      : $doc->createElement($local);

    my $xsi = $self->schemaInstanceNS;
    $el->setAttribute($self->prefixed($xsi, 'nil'), 'true');

    $el->setAttribute($self->prefixed($xsi, 'type'), $self->prefixed($type))
       if $type;

    $el;
}

=method array (NAME|undef), ITEM_TYPE, ARRAY-of-ELEMENTS, OPTIONS
Arrays can be a mess: a mixture of anything and nothing.  Therefore,
you have to help the generation more than you may wish for.  This
method produces an one dimensional array, M<multidim()> is used for
multi-dimensional arrays.

The NAME is the packed type of the array itself.  When undef,
the C<< {soap-enc-ns}Array >> will be used (the action soap
encoding namespace will be used).

The ITEM_TYPE specifies the type of each element within the array.
This type is used to create the C<arrayType> attribute, however
doesn't tell enough about the items themselves: they may be
extensions to that type.

Each of the ELEMENTS must be an M<XML::LibXML::Node>, either
self-constructed, or produced by one of the builder methods in
this class, like M<enc()> or M<typed()>.

Returned is the XML::LibXML::Element which represents the
array.

=option  offset INTEGER
=default offset 0
When a partial array is to be transmitted, the number of the base
element.

=option  slice INTEGER
=default slice <all remaining>
When a partial array is to be transmitted, this is the length of
the slice to be sent (the number of elements starting with the C<offset>
element)

=option  id STRING
=default id <undef>
Assign an id to the array.  If not defined, than no id attribute is
added.

=option  array_type STRING
=default array_type <generated>
The arrayType attribute content.  When explicitly set to undef, the
attribute is not created.

=option  nested_array STRING
=default nested_array ''
The ARRAY type should reflect nested array structures if they are
homogeneous.  This is a really silly part of the specs, because there
is no need for it on any other comparible place in the specs... but ala.

For instance: C<< nested_array => '[,]' >>, means that this array
contains two-dimensional arrays.

=cut

sub array($$$@)
{   my ($self, $name, $itemtype, $array, %opts) = @_;

    my $encns   = $self->encodingNS;
    my $enc     = $self->{enc};
    my $doc     = $enc->{doc};

    my $offset  = $opts{offset} || 0;
    my $slice   = $opts{slice};

    my ($min, $size) = ($offset, scalar @$array);
    $min++ while $min <= $size && !defined $array->[$min];

    my $max = defined $slice && $min+$slice-1 < $size ? $min+$slice-1 : $size;
    $max-- while $min <= $max && !defined $array->[$max];

    my $sparse = 0;
    for(my $i = $min; $i < $max; $i++)
    {   next if defined $array->[$i];
        $sparse = 1;
        last;
    }

    my $elname = $self->prefixed(defined $name ? $name : ($encns, 'Array'));
    my $el     = $doc->createElement($elname);
    my $nested = $opts{nested_array} || '';
    my $type   = $self->prefixed($itemtype)."$nested\[$size]";

    $el->setAttribute(id => $opts{id}) if defined $opts{id};
    my $at     = $opts{array_type} ? $opts{arrayType} 
               : $self->prefixed($encns, 'arrayType');
    $el->setAttribute($at, $type) if defined $at;

    if($sparse)
    {   my $placeition = $self->prefixed($encns, 'position');
        for(my $r = $min; $r <= $max; $r++)
        {   my $row  = $array->[$r] or next;
            my $node = $row->cloneNode(1);
            $node->setAttribute($placeition, "[$r]");
            $el->addChild($node);
        }
    }
    else
    {   $el->setAttribute($self->prefixed($encns, 'offset'), "[$min]")
            if $min > 0;
        $el->addChild($array->[$_]) for $min..$max;
    }

    $el;
}

=method multidim (NAME|undef), ITEM_TYPE, ARRAY-of-ELEMENTS, OPTIONS
A multi-dimensional array, less flexible than a single dimensional
array, which can be created with M<array()>.

The array must be square: in each of the dimensions, the length of
each row must be the same.  On the other hand, it may be sparse
(contain undefs).  The size of each dimension is determined by the
length of its first element.

=option  id STRING
=default id C<undef>
=cut

sub multidim($$$@)
{   my ($self, $name, $itemtype, $array, %opts) = @_;
    my $encns   = $self->encodingNS;
    my $enc     = $self->{enc};
    my $doc     = $enc->{doc};

    # determine dimensions
    my @dims;
    for(my $dim = $array; ref $dim eq 'ARRAY'; $dim = $dim->[0])
    {   push @dims, scalar @$dim;
    }

    my $sparse = $self->_check_multidim($array, \@dims, '');
    my $elname = $self->prefixed(defined $name ? $name : ($encns, 'Array'));
    my $el     = $doc->createElement($elname);
    my $type   = $self->prefixed($itemtype) . '['.join(',', @dims).']';

    $el->setAttribute(id => $opts{id}) if defined $opts{id};
    $el->setAttribute($self->prefixed($encns, 'arrayType'), $type);

    my @data   = $self->_flatten_multidim($array, \@dims, '');
    if($sparse)
    {   my $placeition = $self->prefixed($encns, 'position');
        while(@data)
        {   my ($place, $field) = (shift @data, shift @data);
            my $node = $field->cloneNode(1);
            $node->setAttribute($placeition, "[$place]");
            $el->addChild($node);
        }
    }
    else
    {   $el->addChild($_) for odd_elements @data;
    }

    $el;
}

sub _check_multidim($$$)
{   my ($self, $array, $dims, $loc) = @_;
    my @dims = @$dims;

    my $expected = shift @dims;
    @$array <= $expected
       or error __x"dimension at ({location}) is {size}, larger than size {expect} of first row"
           , location => $loc, size => scalar(@$array), expect => $expected;

    my $sparse = 0;
    foreach (my $x = 0; $x < $expected; $x++)
    {   my $el   = $array->[$x];
        my $cell = length $loc ? "$loc,$x" : $x;

        if(!defined $el) { $sparse++ }
        elsif(@dims==0)   # bottom level
        {   UNIVERSAL::isa($el, 'XML::LibXML::Element')
               or error __x"array element at ({location}) shall be a XML element or undef, is {value}"
                    , location => $cell, value => $el;
        }
        elsif(ref $el eq 'ARRAY')
        {   $sparse += $self->_check_multidim($el, \@dims, $cell);
        }
        else
        {   error __x"array at ({location}) expects ARRAY reference, is {value}"
               , location => $cell, value => $el;
        }
    }

    $sparse;
}

sub _flatten_multidim($$$)
{   my ($self, $array, $dims, $loc) = @_;
    my @dims = @$dims;

    my $expected = shift @dims;
    my @data;
    foreach (my $x = 0; $x < $expected; $x++)
    {   my $el = $array->[$x];
        defined $el or next;

        my $cell = length $loc ? "$loc,$x" : $x;
        push @data, @dims==0 ? ($cell, $el)  # deepest dim
         : $self->_flatten_multidim($el, \@dims, $cell);
    }

    @data;
}

#--------------------------------------------------

=subsection Decoding

=method startDecoding OPTIONS
Each call to this method will restart the cache of the decoding
internals.

Currently B<not supported>, is the automatic decoding of elements which
I<inherit> from C<SOAP-ENC:Array>.  If you encounter these, you have to
play with hooks.

=option  reader_opts HASH
=default reader_opts {}
Extend or overrule the default reader options.  Available options
are shown in M<XML::Compile::Schema::compile()>.

=option  simplify BOOLEAN
=default simplify <false>
Call M<decSimplify()> automatically at the end of M<dec()>, so producing
an easily accessible output tree.
=cut

sub _init_decoding($)
{   my ($self, $opts) = @_;

    my %r =  $opts->{reader_opts} ? %{$opts->{reader_opts}} : ();
    $r{anyElement}   ||= 'TAKE_ALL';
    $r{anyAttribute} ||= 'TAKE_ALL';
    $r{permit_href}    = 1;

    push @{$r{hooks}},
     { type    => pack_type($self->encodingNS, 'Array')
     , replace => sub { $self->_dec_array_hook(@_) }
     };

    $self->{dec} =
     { reader_opts => [%r]
     , simplify    => $opts->{simplify}
     };

    $self;
}

=method dec XMLNODES
Decode the XMLNODES (list of M<XML::LibXML::Element> objects).  Use
Data::Dumper to figure-out what the produced output is: it is a guess,
so may not be perfect (do not use RPC but document style soap for
good results).

The decoded data is returned.  When M<startDecoding(simplify)> is true,
then the returned data is compact but may be sloppy.  Otherwise,
a HASH is returned containing as much info as could be extracted from
the tree.
=cut

sub dec(@)
{   my $self  = shift;
    my $data  = $self->_dec( [@_] );
 
    my ($index, $hrefs) = ({}, []);
    $self->_dec_find_ids_hrefs($index, $hrefs, \$data);
    $self->_dec_resolve_hrefs ($index, $hrefs);

    $data = $self->decSimplify($data)
        if $self->{dec}{simplify};

    ref $data eq 'ARRAY'
        or return $data;

    # find the root element(s)
    my $encns = $self->encodingNS;
    my @roots;
    for(my $i = 0; $i < @_ && $i < @$data; $i++)
    {   my $root = $_[$i]->getAttributeNS($encns, 'root');
        next if defined $root && $root==0;
        push @roots, $data->[$i];
    }

    my $answer
      = !@roots        ? $data
      : @$data==@roots ? $data
      : @roots==1      ? $roots[0]
      : \@roots;

    $answer;
}

sub _dec_reader($@)
{   my ($self, $type) = @_;
    return $self->{dec}{$type} if $self->{dec}{$type};

    my ($typens, $typelocal) = unpack_type $type;
    my $schemans  = $self->schemaNS;

    if(   $typens ne $schemans
       && !$self->schemas->namespaces->find(element => $type))
    {   # work-around missing element
        $self->schemas->importDefinitions(<<__FAKE_SCHEMA);
<schema xmlns="$schemans" targetNamespace="$typens" xmlns:d="$typens">
<element name="$typelocal" type="d:$typelocal" />
</schema>
__FAKE_SCHEMA
    }

    $self->{dec}{$type} ||= $self->schemas->compile
      ( READER => $type, @{$self->{dec}{reader_opts}}
      , @_);
}

sub _dec($;$$$)
{   my ($self, $nodes, $basetype, $offset, $dims) = @_;
    my $encns = $self->encodingNS;

    my @res;
    $#res = $offset-1 if defined $offset;

    foreach my $node (@$nodes)
    {   my $ns    = $node->namespaceURI || '';
        my $place;
        if($dims)
        {   my $pos = $node->getAttributeNS($encns, 'position');
            if($pos && $pos =~ m/^\[([\d,]+)\]/ )
            {   my @pos = split /\,/, $1;
                $place  = \$res[shift @pos];
                $place  = \(($$place ||= [])->[shift @pos]) while @pos;
            }
        }

        unless($place)
        {   push @res, undef;
            $place = \$res[-1];
        }

        if(my $href = $node->getAttribute('href') || '')
        {   $$place = { href => $href };
            next;
        }

        if($ns ne $encns)
        {   my $typedef = $node->getAttributeNS($self->schemaInstanceNS,'type');
            if($typedef)
            {   $$place = $self->_dec_typed($node, $typedef);
                next;
            }

            $$place = $self->_dec_other($node, $basetype);
            next;
        }

        my $local = $node->localName;
        if($local eq 'Array')
        {   $$place = $self->_dec_other($node, $basetype);
            next;
        }

        $$place = $self->_dec_soapenc($node, pack_type($ns, $local));
    }

    \@res;
}

sub _dec_typed($$$)
{   my ($self, $node, $type, $index) = @_;

    my ($prefix, $local) = $type =~ m/^(.*?)\:(.*)/ ? ($1, $2) : ('',$type);
    my $ns   = length $prefix ? $node->lookupNamespaceURI($prefix) : '';
    my $full = pack_type $ns, $local;

    my $read = $self->_dec_reader($full)
        or return $node;

    my $child = $read->($node);
    my $data  = ref $child eq 'HASH' ? $child : { _ => $child };
    $data->{_TYPE} = $full;
    $data->{_NAME} = type_of_node $node;

    my $id = $node->getAttribute('id');
    $data->{id} = $id if defined $id;

    { $local => $data };
}

sub _dec_other($$)
{   my ($self, $node, $basetype) = @_;
    my $local = $node->localName;
    my $ns    = $node->namespaceURI || '';
    my $elem  = pack_type $ns, $local;

    my $data;

    my $type  = $basetype || $elem;
    my $read  = try { $self->_dec_reader($type) };
    if($@)
    {    # warn $@->wasFatal->message;  #--> element not found
         # Element not known, so we must autodetect the type
         my @childs = grep {$_->isa('XML::LibXML::Element')} $node->childNodes;
         if(@childs)
         {   my ($childbase, $dims);
             if($type =~ m/(.+?)\s*\[([\d,]+)\]$/)
             {   $childbase = $1;
                 $dims = ($2 =~ tr/,//) + 1;
             }
             my $dec_childs =  $self->_dec(\@childs, $childbase, 0, $dims);
             $local = '_' if $local eq 'Array';  # simplifies better
             $data  = { $local => $dec_childs } if $dec_childs;
         }
         else
         {   $data->{$local} = $node->textContent;
             $data->{_TYPE}  = $basetype if $basetype;
         }
    }
    else
    {    $data = $read->($node);
         $data = { _ => $data } if ref $data ne 'HASH';
         $data->{_TYPE} = $basetype if $basetype;
    }

    $data->{_NAME} = $elem;

    my $id = $node->getAttribute('id');
    $data->{id} = $id if defined $id;

    $data;
}

sub _dec_soapenc($$)
{   my ($self, $node, $type) = @_;
    my $reader = $self->_dec_reader($type)
       or return $node;
    my $data = $reader->($node);
    $data = { _ => $data } if ref $data ne 'HASH';
    $data->{_TYPE} = $type;
    $data;
}

sub _dec_find_ids_hrefs($$$)
{   my ($self, $index, $hrefs, $node) = @_;
    ref $$node or return;

    if(ref $$node eq 'ARRAY')
    {   foreach my $child (@$$node)
        {   $self->_dec_find_ids_hrefs($index, $hrefs, \$child);
        }
    }
    elsif(ref $$node eq 'HASH')
    {   $index->{$$node->{id}} = $$node
            if defined $$node->{id};

        if(my $href = $$node->{href})
        {   push @$hrefs, $href => $node if $href =~ s/^#//;
        }

        foreach my $k (keys %$$node)
        {   $self->_dec_find_ids_hrefs($index, $hrefs, \( $$node->{$k} ));
        }
    }
    elsif(UNIVERSAL::isa($$node, 'XML::LibXML::Element'))
    {   my $search = XML::LibXML::XPathContext->new($$node);
        $index->{$_->value} = $_->getOwnerElement
            for $search->findnodes('.//@id');

        # we cannot restore deep hrefs, so only top level
        if(my $href = $$node->getAttribute('href'))
        {   push @$hrefs, $href => $node if $href =~ s/^#//;
        }
    }
}

sub _dec_resolve_hrefs($$)
{   my ($self, $index, $hrefs) = @_;

    while(@$hrefs)
    {   my ($to, $where) = (shift @$hrefs, shift @$hrefs);
        my $dest = $index->{$to};
        unless($dest)
        {   warning __x"cannot find id for href {name}", name => $to;
            next;
        }
        $$where = $dest;
    }
}

sub _dec_array_hook($$$)
{   my ($self, $node, $args, $where, $local) = @_;

    my $at = $node->getAttributeNS($self->encodingNS, 'arrayType')
        or return $node;

    $at =~ m/^(.*) \s* \[ ([\d,]+) \] $/x
        or return $node;

    my ($preftype, $dims) = ($1, $2);
    my @dims = split /\,/, $dims;
   
    my $basetype;
    if(index($preftype, ':') >= 0)
    {   my ($prefix, $local) = split /\:/, $preftype;
        $basetype = pack_type $node->lookupNamespaceURI($prefix), $local;
    }
    else
    {   $basetype = pack_type '', $preftype;
    }

    return $self->_dec_array_one($node, $basetype, $dims[0])
        if @dims == 1;

     my $first = first {$_->isa('XML::LibXML::Element')} $node->childNodes;

       $first && $first->getAttributeNS($self->encodingNS, 'position')
     ? $self->_dec_array_multisparse($node, $basetype, \@dims)
     : $self->_dec_array_multi($node, $basetype, \@dims);
}

sub _dec_array_one($$$)
{   my ($self, $node, $basetype, $size) = @_;

    my $off    = $node->getAttributeNS($self->encodingNS, 'offset') || '[0]';
    $off =~ m/^\[(\d+)\]$/ or return $node;

    my $offset = $1;
    my @childs = grep {$_->isa('XML::LibXML::Element')} $node->childNodes;
    my $array  = $self->_dec(\@childs, $basetype, $offset, 1);
    $#$array   = $size -1;   # resize array to specified size
    $array;
}

sub _dec_array_multisparse($$$)
{   my ($self, $node, $basetype, $dims) = @_;

    my @childs = grep {$_->isa('XML::LibXML::Element')} $node->childNodes;
    my $array  = $self->_dec(\@childs, $basetype, 0, scalar(@$dims));
    $array;
}

sub _dec_array_multi($$$)
{   my ($self, $node, $basetype, $dims) = @_;

    my @childs = grep {$_->isa('XML::LibXML::Element')} $node->childNodes;
    $self->_dec_array_multi_slice(\@childs, $basetype, $dims);
}

sub _dec_array_multi_slice($$$)
{   my ($self, $childs, $basetype, $dims) = @_;
    if(@$dims==1)
    {   my @col = splice @$childs, 0, $dims->[0];
        return $self->_dec(\@col, $basetype);
    }
    my ($rows, @dims) = @$dims;

    [ map { $self->_dec_array_multi_slice($childs, $basetype, \@dims) }
        1..$rows ]
}

=method decSimplify TREE, OPTIONS
Simplify the TREE of output produced by M<dec()> to contain only
data.  Of course, this will remove useful information.

From each of the HASHes in the tree, the C<_NAME>, C<_TYPE>, C<id>,
and any/anyAttribute fields are removed.  If only a C<_> is left over,
that related value will replace the HASH as a whole.
=cut

sub decSimplify($@)
{   my ($self, $tree, %opts) = @_;
    defined $tree or return ();
    $self->{dec}{_simple_recurse} = {};
    $self->_dec_simple($tree, \%opts);
}

sub _dec_simple($$)
{   my ($self, $tree, $opts) = @_;

    ref $tree
        or return $tree;

    return $tree
        if $self->{dec}{_simple_recurse}{$tree};

    $self->{dec}{_simple_recurse}{$tree}++;

    if(ref $tree eq 'ARRAY')
    {   my @a = map { $self->_dec_simple($_, $opts) } @$tree;
        return $a[0] if @a==1;

        # array of hash with each one element becomes hash
        my %out;
        foreach my $hash (@a)
        {   ref $hash eq 'HASH' && keys %$hash==1
                or return \@a;

            my ($name, $value) = each %$hash;
            if(!exists $out{$name}) { $out{$name} = $value }
            elsif(ref $out{$name} eq 'ARRAY')
            {   $out{$name} = [ $out{$name} ]   # array of array: keep []
                    if ref $out{$name}[0] ne 'ARRAY' && ref $value eq 'ARRAY';
                push @{$out{$name}}, $value;
            }
            else { $out{$name} = [ $out{$name}, $value ] }
        }
        return \%out;
    }

    ref $tree eq 'HASH'
        or return $tree;

    foreach my $k (keys %$tree)
    {   if($k =~ m/^(?:_NAME$|_TYPE$|id$|\{)/) { delete $tree->{$k} }
        elsif(ref $tree->{$k})
        {   $tree->{$k} = $self->_dec_simple($tree->{$k}, $opts);
        }
    }

    delete $self->{dec}{_simple_recurse}{$tree};

    keys(%$tree)==1 && exists $tree->{_} ? $tree->{_} : $tree;
}

1;
