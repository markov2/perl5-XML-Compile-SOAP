use warnings;
use strict;

package XML::Compile::SOAP11::Operation;
use base 'XML::Compile::SOAP::Operation';

use Log::Report 'xml-compile-soap', syntax => 'SHORT';
use List::Util  'first';

use XML::Compile::Util       qw/pack_type unpack_type/;
use XML::Compile::SOAP::Util qw/:soap11/;
use XML::Compile::SOAP11::Client;
use XML::Compile::SOAP11::Server;
use XML::Compile::SOAP::Extension;

our $VERSION;         # OODoc adds $VERSION to the script
$VERSION ||= '(devel)';

# client/server object per schema class, because initiation options
# can be different.  Class reference is key.
my (%soap11_client, %soap11_server);

=chapter NAME

XML::Compile::SOAP11::Operation - defines a SOAP11 interaction

=chapter SYNOPSIS
 # object created by XML::Compile::WSDL*
 my $op = $wsdl->operation('GetStockPrices');
 $op->explain($wsdl, PERL => 'INPUT', recurse => 1);

=chapter DESCRIPTION
Objects of this type define one possible SOAP11 interaction, either
client side or server side.

=chapter METHODS

=section Constructors

=c_method new OPTIONS

C<input_def>, C<output_def> and C<fault_def> are HASHes which contain
the input and output message header, body and fault-header definitions
in WSDL1.1 style.

=option  input_def HASH
=default input_def <undef>

=option  output_def HASH
=default output_def <undef>

=option  fault_def HASH
=default fault_def <undef>

=option  style  'document'|'rpc'
=default style  'document'

=cut

sub init($)
{   my ($self, $args) = @_;

    $self->SUPER::init($args);

    $self->{$_}    = $args->{$_} || {}
        for qw/input_def output_def fault_def/;

    $self->{style} = $args->{style} || 'document';

    XML::Compile::SOAP::Extension->soap11OperationInit($self, $args);
    $self;
}

sub _fromWSDL11(@)
{   my ($class, %args) = @_;

    # Extract the SOAP11 specific information from a WSDL11 file.  There are
    # half a zillion parameters.
    my ($p_op, $b_op, $wsdl)
      = @args{ qw/port_op bind_op wsdl/ };

    $args{schemas}   = $wsdl;
    $args{endpoints} = $args{serv_port}{soap_address}{location};

    my $sop = $b_op->{soap_operation}     || {};
    $args{action}  ||= $sop->{soapAction};

    my $sb = $args{binding}{soap_binding} || {};
    $args{transport} = $sb->{transport}   || 'HTTP';
    $args{style}     = $sb->{style}       || 'document';

    $args{input_def} = $class->_msg_parts($wsdl, $args{name}, $args{style}
      , $p_op->{wsdl_input}, $b_op->{wsdl_input});

    $args{output_def} = $class->_msg_parts($wsdl, $args{name}.'Response'
      , $args{style}, $p_op->{wsdl_output}, $b_op->{wsdl_output});

    $args{fault_def}
      = $class->_fault_parts($wsdl, $p_op->{wsdl_fault}, $b_op->{wsdl_fault});

    $class->SUPER::new(%args);
}

sub _msg_parts($$$$$)
{   my ($class, $wsdl, $opname, $style, $port_op, $bind_op) = @_;
    my %parts;

    defined $port_op          # communication not in two directions
        or return ({}, {});

    if(my $body = $bind_op->{soap_body})
    {   my $msgname   = $port_op->{message};
        my @parts     = $class->_select_parts($wsdl, $msgname, $body->{parts});

        my ($ns, $local) = unpack_type $msgname;
        my $rpc_ns    = $body->{namespace};
        $wsdl->addPrefixes(call => $rpc_ns)   # hopefully no-one uses "call"
            if defined $rpc_ns && !$wsdl->prefixFor($rpc_ns);

        my $procedure
            = $style eq 'rpc' ? pack_type($rpc_ns, $opname)
            : @parts==1 && $parts[0]{type} ? $msgname
            : $local; 

        $parts{body}  = {procedure => $procedure, %$port_op, use => 'literal',
           %$body, parts => \@parts};
    }
    elsif($port_op->{message})
    {   # missing <soap:body use="literal"> in <wsdl:input> or :output
        error __x"operation {opname} has a message in its portType but no encoding in the binding", opname => $opname;
    }

    my $bsh = $bind_op->{soap_header} || [];
    foreach my $header (ref $bsh eq 'ARRAY' ? @$bsh : $bsh)
    {   my $msgname  = $header->{message};
        my @parts    = $class->_select_parts($wsdl, $msgname, $header->{part});
         push @{$parts{header}}, { %$header, parts => \@parts };

        foreach my $fault ( @{$header->{headerfault} || []} )
        {   $msgname = $fault->{message};
            my @hf   = $class->_select_parts($wsdl, $msgname, $fault->{part});
            push @{$parts{headerfault}}, { %$fault,  parts => \@hf };
        }
    }
    \%parts;
}

sub _select_parts($$$)
{   my ($class, $wsdl, $msgname, $need_parts) = @_;
    my $msg = $wsdl->findDef(message => $msgname)
        or error __x"cannot find message {name}", name => $msgname;

    my @need
      = ref $need_parts     ? @$need_parts
      : defined $need_parts ? $need_parts
      : ();

    my $parts = $msg->{wsdl_part} || [];
    @need or return @$parts;

    my @sel;
    my %parts = map +($_->{name} => $_), @$parts;
    foreach my $name (@need)
    {   my $part = $parts{$name}
            or error __x"message {msg} does not have a part named {part}"
                  , msg => $msg->{name}, part => $name;

        push @sel, $part;
    }

    @sel;
}

sub _fault_parts($$$)
{   my ($class, $wsdl, $portop, $bind) = @_;

    my $port_faults  = $portop || [];
    my %faults;

    foreach my $fault (@$bind)
    {   $fault or next;
        my $name  = $fault->{name};

        my $port  = first {$_->{name} eq $name} @$port_faults;
        defined $port
            or error __x"cannot find port for fault {name}", name => $name;

        my $msgname = $port->{message}
            or error __x"no fault message name in portOperation";

        my $message = $wsdl->findDef(message => $msgname)
            or error __x"cannot find fault message {name}", name => $msgname;

        @{$message->{wsdl_part} || []}==1
            or error __x"fault message {name} must have one part exactly"
                  , name => $msgname;

        $faults{$name} =
          { part => $message->{wsdl_part}[0]
          , use  => ($fault->{use} || 'literal')
          };
    }

   +{ faults => \%faults };
}

#-------------------------------------------

=section Accessors

=method style
=cut

sub style()     {shift->{style}}
sub version()   { 'SOAP11' }
sub serverClass { 'XML::Compile::SOAP11::Server' }
sub clientClass { 'XML::Compile::SOAP11::Client' }

#-------------------------------------------

=section Modify

Operations are often modified by SOAP extensions.
See M<XML::Compile::SOAP::WSA>, for instance. Also demonstrated in
the FAQ, M<XML::Compile::SOAP::FAQ>.

=method addHeader ('INPUT'|'OUTPUT'|'FAULT'), LABEL, ELEMENT, OPTIONS
Add a header definitions.  Many protocols on top of SOAP, like WSS, add
headers to the operations which are not specified in the WSDL.

[2.31] When you add a header with same LABEL again, it will get silently
ignored unless the ELEMENT type differs. An ELEMENT is either a full
type or a [3.00] prefixed type.

=option  mustUnderstand BOOLEAN
=default mustUnderstand C<undef>
[2.33] adds the mustUnderstand attribute.

=option  destination ROLE
=default destination C<undef>
[2.33] adds the destination attribute,
=cut

sub addHeader($$$%)
{   my ($self, $dir, $label, $el, %opts) = @_;
    my $elem = $self->schemas->findName($el);
    my $defs
      = $dir eq 'INPUT'  ? 'input_def'
      : $dir eq 'OUTPUT' ? 'output_def'
      : $dir eq 'FAULT'  ? 'fault_def'
      : panic "addHeader $dir";
    my $headers = $self->{$defs}{header} ||= [];

    if(my $already = first {$_->{part} eq $label} @$headers)
    {   # the header is already defined, ignore second declaration
        my $other_type = $already->{parts}[0]{element};
        $other_type eq $elem
            or error __x"header {label} already defined with type {type}"
                 , label => $label, type => $other_type;
        return $already;
    }

    my %part =
      ( part  => $label, use => 'literal'
      , parts => [
         { name => $label, element => $elem
         , mustUnderstand => $opts{mustUnderstand}
         , destination    => $opts{destination}
         } ]);

    push @$headers, \%part;
    \%part;
}

#-------------------------------------------

=section Handlers

=method compileHandler OPTIONS
Prepare the routines which will decode the request and encode the answer,
as will be run on the server. The M<XML::Compile::SOAP::Server> will
connect these. All OPTIONS will get passed to
M<XML::Compile::SOAP11::Server::compileHandler()>

=requires callback CODE

=option  selector CODE
=default selector <from input def>
Determines whether the handler belongs to a received message.
=cut

sub compileHandler(@)
{   my ($self, %args) = @_;

    my $soap = $soap11_server{$self->{schemas}}
      ||= XML::Compile::SOAP11::Server->new(schemas => $self->{schemas});
    my $style = $args{style} ||= $self->style;

    my @ro    = (%{$self->{input_def}},  %{$self->{fault_def}});
    my @so    = (%{$self->{output_def}}, %{$self->{fault_def}});

    $args{encode}   ||= $soap->_sender(@so, %args);
    $args{decode}   ||= $soap->_receiver(@ro, %args);
    $args{selector} ||= $soap->compileFilter(%{$self->{input_def}});
    $args{kind}     ||= $self->kind;
    $args{name}       = $self->name;

    $args{callback} = XML::Compile::SOAP::Extension
      ->soap11HandlerWrapper($self, $args{callback}, \%args);

    $soap->compileHandler(%args);
}

=method compileClient OPTIONS
Returns one CODE reference which handles the processing for this
operation. Options C<transporter>, C<transport_hook>, and
C<endpoint> are passed to M<compileTransporter()>.

You pass that CODE reference an input message of the correct
type, as pure Perl HASH structure.  An 'request-response' operation
will return then answer, or C<undef> in case of failure.  An 'one-way'
operation with return C<undef> in case of failure, and a true value
when successfull.

You B<cannot> pass options for M<XML::Compile::Schema::compile()>, like
C<<sloppy_integers => 0>>, hooks or typemaps this way. Provide these to
the C<::WSDL> or other C<::Cache> object which defines the types, via
C<new> option C<opts_rw> and friends.

=cut

sub compileClient(@)
{   my ($self, %args) = @_;

    my $soap = $soap11_client{$self->{schemas}}
      ||= XML::Compile::SOAP11::Client->new(schemas => $self->{schemas});
    my $style = $args{style} ||= $self->style;
    my $kind  = $args{kind}  ||= $self->kind;

    my @so   = (%{$self->{input_def}},  %{$self->{fault_def}});
    my @ro   = (%{$self->{output_def}}, %{$self->{fault_def}});

    my $call = $soap->compileClient
      ( name         => $self->name
      , kind         => $kind
      , encode       => $soap->_sender(@so, %args)
      , decode       => $soap->_receiver(@ro, %args)
      , transport    => $self->compileTransporter(%args)
      , async        => $args{async}
      );

    XML::Compile::SOAP::Extension->soap11ClientWrapper($self, $call, \%args);
}

#--------------------------

=section Helpers

=method explain WSDL, FORMAT, DIRECTION, OPTIONS
[since 2.13]

Dump an annotated structure showing how the operation works, helping
developers to understand the schema. FORMAT is C<PERL>.
(C<XML> is not yet supported)

The DIRECTION is C<INPUT>, it will return the message which the client
sends to the server (input for the server). The C<OUTPUT> message is
sent as response by the server.

All OPTIONS besides those described here are passed to
M<XML::Compile::Schema::template()>, when C<recurse> is enabled.

=option  skip_header BOOLEAN
=default skip_header <false>

=option  recurse BOOLEAN
=default recurse <false>
Append the templates of all the part structures.
=cut

my $sep = '#--------------------------------------------------------------';

sub explain($$$@)
{   my ($self, $schema, $format, $dir, %args) = @_;

    # $schema has to be passed as argument, because we do not want operation
    # objects to be glued to a schema object after compile time.

    UNIVERSAL::isa($schema, 'XML::Compile::Schema')
        or error __x"explain() requires first element to be a schema";

    $format eq 'PERL'
        or error __x"only PERL template supported for the moment, not {got}"
            , got => $format;

    my $style       = $self->style;
    my $opname      = $self->name;
    my $skip_header = delete $args{skip_header} || 0;
    my $recurse     = delete $args{recurse}     || 0;

    my $def    = $dir eq 'INPUT' ? $self->{input_def} : $self->{output_def};
    my $faults = $self->{fault_def}{faults};

    my (@struct, @postproc, @attach);
    my @main = $recurse
       ? "# The details of the types and elements are attached below."
       : "# To explore the HASHes for each part, use recurse option.";

  HEAD_PART:
    foreach my $header (@{$def->{header} || []})
    {   foreach my $part ( @{$header->{parts} || []} )
        {   my $name = $part->{name};
            my ($kind, $value) = $part->{type} ? (type => $part->{type})
              : (element => $part->{element});
    
            my $type = $schema->prefixed($value) || $value;
            push @main, ''
              , "# Header part '$name' is $kind $type"
              , ($kind eq 'type' && $recurse ? "# See fake element '$name'" : ())
              , "my \$$name = {};";
            push @struct, "    $name => \$$name,";
    
            $recurse or next HEAD_PART;
    
            my $elem = $value;
            if($kind eq 'type')
            {   # generate element with part name, because template requires elem
                $schema->compileType(READER => $value, element => $name);
                $elem = $name;
            }
    
            push @attach, '', $sep, "\$$name ="
              , $schema->template(PERL => $elem, skip_header => 1, %args), ';';
        }
    }

  BODY_PART:
    foreach my $part ( @{$def->{body}{parts} || []} )
    {   my $name = $part->{name};
        my ($kind, $value) = $part->{type} ? (type => $part->{type})
          : (element => $part->{element});

        my $type = $schema->prefixed($value) || $value;
        push @main, ''
          , "# Body part '$name' is $kind $type"
          , ($kind eq 'type' && $recurse ? "# See fake element '$name'" : ())
          , "my \$$name = {};";
        push @struct, "    $name => \$$name,";

        $recurse or next BODY_PART;

        my $elem = $value;
        if($kind eq 'type')
        {   # generate element with part name, because template requires elem
            $schema->compileType(READER => $value, element => $name);
            $elem = $name;
        }

        push @attach, '', $sep, "\$$name ="
          , $schema->template(PERL => $elem, skip_header => 1, %args), ';';
    }

    foreach my $fault (sort keys %$faults)
    {   my $part = $faults->{$fault}{part};  # fault msgs have only one part
        my ($kind, $value) = $part->{type} ? (type => $part->{type})
          : (element => $part->{element});

        my $type = $schema->prefixFor($value)
          ? $schema->prefixed($value) : $value;

        if($dir eq 'OUTPUT')
        {   push @main, ''
              , "# ... or fault $fault is $kind"
              , "my \$$fault = {}; # $type"
              , ($kind eq 'type' && $recurse ? "# See fake element '$fault'" : ())
              , "my \$fault ="
              , "  { code   => pack_type(\$myns, 'Open.NoSuchFile')"
              , "  , reason => 'because I can'"
              , "  , detail => \$$fault"
              , '  };';
            push @struct, "    $fault => \$fault,";
        }
        else
        {   my $nice = $schema->prefixed($type) || $type;
            push @postproc
              , "    elsif(\$errname eq '$fault')"
              , "    {   # \$details is a $nice"
              , "    }";
        }

        $recurse or next;

        my $elem = $value;
        if($kind eq 'type')
        {   # generate element with part name, because template requires elem
            $schema->compileType(READER => $value, element => $fault);
            $elem = $fault;
        }

        push @attach, '', $sep, "# FAULT", "\$$fault ="
          , $schema->template(PERL => $elem, skip_header => 1, %args), ';';
    }

    if($dir eq 'INPUT')
    {   push @main, ''
         , '# Call with the combination of parts.'
         , 'my @params = (', @struct, ');'
         , 'my ($answer, $trace) = $call->(@params);', ''
         , '# @params will become %$data_in in the server handler.'
         , '# $answer is a HASH, an operation OUTPUT or Fault.'
         , '# $trace is an XML::Compile::SOAP::Trace object.';

        unshift @postproc, ''
          , '# You may get an error back from the server'
          , 'if(my $f = $answer->{Fault})'
          , '{   my $errname = $f->{_NAME};'
          , '    my $error   = $answer->{$errname};'
          , '    print "$error->{code}\n";', ''
          , '    my $details = $error->{detail};'
          , '    if(not $details)'
          , '    {   # system error, no $details'
          , '    }';
    
        push @postproc
          , '    exit 1;'
          , '}';
    }
    elsif($dir eq 'OUTPUT')
    {   s/^/   / for @main, @struct;
        unshift @main, ''
         , "sub handle_$opname(\$)"
         , '{  my ($server, $data_in) = @_;'
         , '   # process $data_in, structured as INPUT message.'
         , '   # Hint: use "print Dumper $data_in"';

        push @main, ''
         , '   # This will end-up as $answer at client-side'
         , '   return    # optional keyword'
         , "   +{", @struct, "    };", "}";
    }
    else
    {   error __x"template for direction INPUT or OUTPUT, not {got}"
          , got => $dir;
    }

    my @header;
    if(my $how = $def->{body})
    {   my $use  = $how->{use} || 'literal';
        push @header
          , "# Operation $how->{procedure}"
          , "#           $dir, $style $use";
    }
    else
    {   push @header,
          , "# Operation $opname has no $dir";
    }

    foreach my $fault (sort keys %$faults)
    {   my $usage = $faults->{$fault};
        push @header
      , "#           FAULT $fault, $style $usage->{use}" # $style?
    }

    push @header
      , "# Produced  by ".__PACKAGE__." version $VERSION"
      , "#           on ".localtime()
      , "#"
      , "# The output below is only an example: it cannot be used"
      , "# without interpretation, although very close to real code."
      , ""
        unless $args{skip_header};

    if($dir eq 'INPUT')
    {   push @header
          , '# Compile only once in your code, usually during initiation:'
          , "my \$call = \$wsdl->compileClient('$opname');"
          , '# ... then call it as often as you need.';
    }
    else #OUTPUT
    {   push @header
          , '# As part of the initiation phase of your server:'
          , 'my $daemon = XML::Compile::SOAP::HTTPDaemon->new;'
          , '$deamon->operationsFromWSDL'
          , '  ( $wsdl'
          , '  , callbacks =>'
          , "     { $opname => \\&handle_$opname}"
          , '  );'
    }

    join "\n", @header, @main, @postproc, @attach, '';
}

=method parsedWSDL
[2.29] For some purposes, it is useful to get access to the parsed WSDL
structure.

B<Be aware> that the structure returned is consided "internal"
and strongly influenced by behavior of M<XML::Compile>; backwards
compatibility will not be maintained at all cost.

You can use M<XML::Compile::Schema::template()> format C<TREE> to get
more details about the element types mentioned in this structure.

=example
  use Data::Dumper;
  $Data::Dumper::Indent    = 1;
  $Data::Dumper::Quotekeys = 0;

  print Dumper $op->parsedWSDL;
=cut

sub parsedWSDL()
{   my $self = shift;
      +{ input  => $self->{input_def}{body}
       , output => $self->{output_def}{body}
       , faults => $self->{fault_def}{faults}
       , style  => $self->style
       };
}

1;
