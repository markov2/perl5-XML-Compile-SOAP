use warnings;
use strict;

package XML::Compile::SOAP;  #!!!

use Log::Report 'xml-compile-soap', syntax => 'SHORT';
use List::Util qw/min first/;
use XML::Compile::Util qw/odd_elements/;

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
 my $xml = $client->typed(code => $int, 43);

 # create: <ref href="#id-1"/>  (xyz get's id if it hasn't)
 my $xml = $client->href('ref', $xyz);
 my $xml = $client->href('ref', $xyz, 'id-1');  # explicit label
 
 # create: <number>3</number>   (gets validated as well!)
 my $xml = $client->element(number => $int, 3);

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
SOAP defines encodings, especially for XML-RPC.

=subsection Encoding

=method startEncoding OPTIONS
This needs to be called before any encoding routine, because it
initializes the internals.  Each call will reset all compiled
cached translator routines.
=requires doc XML::LibXML::Document
=requires namespaces HASH
=cut

# startEncoding is always implemented, loading this class
# the {enc} settings are temporary; live shorter than the object.
sub _init_encoding($)
{   my ($self, $args) = @_;
    my $doc = $args->{doc};
    $doc && UNIVERSAL::isa($doc, 'XML::LibXML::Document')
        or error __x"encoding required an XML document to work with";

    my $allns = $args->{namespaces}
        or error __x"encoding requires prepared namespace table";

    $self->{enc} = $args;
    $self;
}

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

    my $def  =  $self->{enc}{namespaces}{$ns}
        or error __x"namespace prefix for your {ns} not defined", ns => $ns;

    # not used at compile-time, but now we see we needed it.
    $def->{used}
      or warning __x"explicitly pass namespace {ns} in compileMessage(prefixes)"
            , ns => $ns;

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
      ( WRITER => $type
      , output_namespaces  => $enc->{namespaces}
      , elements_qualified => 1
      , include_namespaces => 0
      );

    $write->($enc->{doc}, {_ => $value, id => $id} );
}

=method typed NAME, TYPE, VALUE
A "typed" element shows its type explicitly, via the "xsi:type" attribute.
The VALUE will get processed via an auto-generated XML::Compile writer,
so validated.  The processing is cashed.  When VALUE already is an
M<XML::LibXML::Element>, then no processing nor value checking will be
performed.
=cut

sub typed($$$)
{   my ($self, $name, $type, $value) = @_;
    my $enc = $self->{enc};
    my $el  = $enc->{doc}->createElement($name);

    my $typedef = $self->prefixed($self->schemaInstanceNS,'type');
    $el->setAttribute($typedef, $self->prefixed($type));

    unless(UNIVERSAL::isa($value, 'XML::LibXML::Element'))
    {   my $write = $self->{writer}{$type} ||= $self->schemas->compile
         ( WRITER => $type
         , output_namespaces  => $enc->{namespaces}
         , include_namespaces => 0
         );
        $value = $write->($enc->{doc}, $value);
    }

    $el->addChild($value);
    $el;
}

=method element NAME, TYPE, VALUE
Create an element.  The NAME is for node, where a namespace component
is translated into a prefix.
=cut

sub element($$$)
{   my ($self, $name, $type, $value) = @_;
    my $enc = $self->{enc};
    my $el  = $enc->{doc}->createElement($name);

    unless(UNIVERSAL::isa($value, 'XML::LibXML::Element'))
    {   my $write = $self->{writer}{$type} ||= $self->schemas->compile
         ( WRITER => $type
         , output_namespaces  => $enc->{namespaces}
         , include_namespaces => 0
         );
        $value = $write->($enc->{doc}, $value);
    }

    $el->addChild($value);
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
=default id undef
Assign an id to the array.

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
    $el->setAttribute($self->prefixed($encns, 'arrayType'), $type);

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

    my $r = $opts->{reader_opts} || {};
    $r->{anyElement}   ||= 'TAKE_ALL';
    $r->{anyAttribute} ||= 'TAKE_ALL';

    push @{$r->{hooks}},
      { type    => pack_type($self->encodingNS, 'Array')
      , replace => sub { $self->_dec_array_hook(@_) }
      };

    $self->{dec} = {reader_opts => [%$r], simplify => $opts->{simplify}};
    $self;
}

=method dec XMLNODES
Decode the XMLNODES (list of M<XML::LibXML::Element> objects).  Use
Data::Dumper to figure-out what the produced output is: it is a guess,
so may not be perfect (do not use XML-RPC but document style soap for
good results).

In LIST context, the decoded data is returned and a HASH with the
C<id> index are returned.  In SCALAR context, only the decoded data is
returned.  When M<startDecoding(simplify)> is true, then the returned
data is concise but may be sloppy.  Otherwise, a HASH is returned
containing as much info as could be extracted from the tree.
=cut

sub dec(@)
{   my $self  = shift;
    $self->{dec}{href}  = [];
    $self->{dec}{index} = {};
    my $data  = $self->_dec(\@_);

    my $index = $self->{dec}{index};
    $self->_dec_resolve_hrefs($index);

    $data = $self->decSimplify($data)
        if $self->{dec}{simplify};

    wantarray ? ($data, $index) : $data;
}

sub _dec_reader($@)
{   my ($self, $type) = @_;
    $self->{dec}{$type} ||= $self->schemas->compile
      (READER => $type, @{$self->{dec}{reader_opts}}, @_);
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

        my $href = $node->getAttribute('href') || '';
        if($href =~ s/^#//)
        {   $$place = undef;
            $self->_dec_href($node, $href, $place);
            next;
        }

        if($ns ne $encns)
        {   my $typedef = $node->getAttributeNS($self->schemaInstanceNS,'type');
            $typedef  ||= $basetype;
            if($typedef)
            {   $$place = $self->_dec_typed($node, $typedef);
                next;
            }

            $$place = $self->_dec_other($node);
            next;
        }

        my $local = $node->localName;
        if($local eq 'Array')
        {   $$place = $self->_dec_other($node);
            next;
        }

        $$place = $self->_dec_soapenc($node, pack_type($ns, $local));
    }

    $self->_dec_index($_->{id} => $_)
        for grep {ref $_ eq 'HASH' && defined $_->{id}} @res;

    \@res;
}

sub _dec_index($$) { $_[0]->{dec}{index}{$_[1]} = $_[2] }

sub _dec_typed($$$)
{   my ($self, $node, $type, $index) = @_;

    my ($prefix, $local) = $type =~ m/(.*?)\:(.*)/ ? ($1, $2) : ('', $type);
    my $ns   = length $prefix ? $node->lookupNamespaceURI($prefix) : '';
    my $full = pack_type $ns, $local;

    my $read = $self->_dec_reader($full)
        or return $node;

    my $data = $read->($node);
    $data = { _ => $data } if ref $data ne 'HASH';
    $data->{_TYPE} = $full;
    $data;
}

sub _dec_other($)
{   my ($self, $node) = @_;
    my $ns    = $node->namespaceURI || '';
    my $local = $node->localName;

    my $type = pack_type $ns, $local;
    my $read = $self->_dec_reader($type)
        or return $node;

    my $data = $read->($node);
    $data = { _ => $data } if ref $data ne 'HASH';
    $data->{_NAME} = $type;

    if(my $id = $node->getAttribute('id'))
    {   $self->_dec_index($id => $data);
        $data->{id} = $id;
    }
    $data;
}

sub _dec_soapenc($$)
{   my ($self, $node, $type) = @_;
    my $read = $self->_dec_reader($type)
       or return $node;
    my $data = ($read->($node))[1];
    $data = { _ => $data } if ref $data ne 'HASH';
    $data->{_TYPE} = $type;
    $data;
}

sub _dec_href($$$)
{   my ($self, $node, $to, $where) = @_;
    my $data;
    push @{$self->{dec}{href}}, $to => $where;
}

sub _dec_resolve_hrefs($)
{   my ($self, $index) = @_;
    my $hrefs = $self->{dec}{href};

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

    my ($basetype, $dims) = ($1, $2);
    my @dims = split /\,/, $dims;

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
    $self->_dec_simple($tree, \%opts);
}

sub _dec_simple($$)
{   my ($self, $tree, $opts) = @_;

    ref $tree
        or return $tree;

    if(ref $tree eq 'ARRAY')
    {   my @a = map { $self->_dec_simple($_, $opts) } @$tree;
        return @a==1 ? $a[0] : \@a;
    }

    ref $tree eq 'HASH'
        or return $tree;

    my %h;
    while(my ($k, $v) = each %$tree)
    {   next if $k =~ m/^(?:_NAME$|_TYPE$|id$|\{)/;
        $h{$k} = ref $v ? $self->_dec_simple($v, $opts) : $v;
    }
    keys(%h)==1 && exists $h{_} ? $h{_} : \%h;
}

1;
