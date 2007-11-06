use warnings;
use strict;

package XML::Compile::SOAP11;
use base 'XML::Compile::SOAP';

use Log::Report 'xml-compile-soap', syntax => 'SHORT';
use XML::Compile::Util       qw/pack_type unpack_type SCHEMA2001/;
use XML::Compile::SOAP::Util qw/:soap11/;

XML::Compile->addSchemaDirs(__FILE__);
XML::Compile->knownNamespace
 ( &SOAP11ENC => 'soap-encoding.xsd'
 , &SOAP11ENV => 'soap-envelope.xsd'
 );

=chapter NAME
XML::Compile::SOAP11 - base class for SOAP1.1 implementation

=chapter SYNOPSIS

=chapter DESCRIPTION
This module handles the SOAP protocol version 1.1.
See F<http://www.w3.org/TR/2000/NOTE-SOAP-20000508/>).
The implementation tries to behave like described in
F<http://www.ws-i.org/Profiles/BasicProfile-1.0.html>

Two extensions are made: the SOAP11 client
M<XML::Compile::SOAP11::Client>.
and server in M<XML::Compile::SOAP11::Server>.

=chapter METHODS

=section Constructors

=method new OPTIONS
To simplify the URIs of the actors, as specified with the C<destination>
option, you may use the STRING C<NEXT>.  It will be replaced by the
right URI.

=default version     'SOAP11'
=default envelope_ns C<http://schemas.xmlsoap.org/soap/envelope/>
=default encoding_ns C<http://schemas.xmlsoap.org/soap/encoding/>
=default schema_ns   C<http://www.w3.org/2001/XMLSchema>
=cut

sub new($@)
{   my $class = shift;
    $class ne __PACKAGE__
        or error __x"only instantiate a SOAP11::Client or ::Server";
    (bless {}, $class)->init( {@_} );
}

sub init($)
{   my ($self, $args) = @_;

    $args->{version}               ||= 'SOAP11';
    $args->{schema_ns}             ||= SCHEMA2001;
    my $env = $args->{envelope_ns} ||= SOAP11ENV;
    my $enc = $args->{encoding_ns} ||= SOAP11ENC;

    $self->SUPER::init($args);

    my $schemas = $self->schemas;
    $schemas->importDefinitions($env);
    $schemas->importDefinitions($enc);
    $self;
}

=section Single messages

=method compileMessage ('SENDER'|'RECEIVER'), OPTIONS

=option  headerfault ENTRIES
=default headerfault []
ARRAY of simple name with element references, for all expected
faults.  There can be unexpected faults, which will not get
decoded automatically.
=cut

sub writerHeaderEnv($$$$)
{   my ($self, $code, $allns, $understand, $actors) = @_;
    $understand || $actors or return $code;

    my $schema = $self->schemas;
    my $envns  = $self->envelopeNS;

    # Cannot precompile everything, because $doc is unknown
    my $ucode;
    if($understand)
    {   my $u_w = $self->{soap11_u_w} ||=
          $schema->compile
            ( WRITER => pack_type($envns, 'mustUnderstand')
            , output_namespaces    => $allns
            , include_namespaces   => 0
            );

        $ucode =
        sub { my $el = $code->(@_) or return ();
              my $un = $u_w->($_[0], 1);
              $el->addChild($un) if $un;
              $el;
            };
    }
    else {$ucode = $code}

    if($actors)
    {   $actors =~ s/\b(\S+)\b/$self->roleURI($1)/ge;

        my $a_w = $self->{soap11_a_w} ||=
          $schema->compile
            ( WRITER => pack_type($envns, 'actor')
            , output_namespaces    => $allns
            , include_namespaces   => 0
            );

        return
        sub { my $el  = $ucode->(@_) or return ();
              my $act = $a_w->($_[0], $actors);
              $el->addChild($act) if $act;
              $el;
            };
    }

    $ucode;
}

sub sender($)
{   my ($self, $args) = @_;
    my $envns = $self->envelopeNS;
    $args->{prefix_table}
     = [ ''         => 'do not use'
       , 'SOAP-ENV' => $envns
       , 'SOAP-ENC' => $self->encodingNS
       , xsd        => 'http://www.w3.org/2001/XMLSchema'
       , xsi        => 'http://www.w3.org/2001/XMLSchema-instance'
       ];

    push @{$args->{body}}
       , Fault => pack_type($envns, 'Fault');

    $self->SUPER::sender($args);
}

sub receiver($)
{   my ($self, $args) = @_;
    my $envns = $self->envelopeNS;

    push @{$args->{body}}, Fault => pack_type($envns, 'Fault');

    $self->SUPER::receiver($args);
}

=section Receiver (internals)

=method readerParseFaults FAULTSDEF
The decoders for the possible "faults" are compiled.  Returned is a code
reference which can handle it.  See fault handler specifics in the
C<DETAILS> chapter below.
=cut

sub readerParseFaults($)
{   my ($self, $faults) = @_;
    my %rules;

    my $schema = $self->schemas;
    my @f      = @$faults;

    while(@f)
    {   my ($label, $element) = splice @f, 0, 2;
        $rules{$element} =  [$label, $schema->compile(READER => $element)];
    }

    sub
    {   my $data   = shift;
        my $faults = $data->{Fault} or return;

        my $reports = $faults->{detail} ||= {};
        my ($label, $details) = (header => undef);
        foreach my $type (sort keys %$reports)
        {   my $report  = $reports->{$type} || [];
            if($rules{$type})
            {   ($label, my $do) = @{$rules{$type}};
                $details = [ map { ($do->($_))[1] } @$report ];
            }
            else
            {   ($label, $details) = (body => $report);
            }
        }

        my ($code_ns, $code_err) = unpack_type $faults->{faultcode};
        my ($err, @sub_err) = split /\./, $code_err;
        $err = 'Receiver' if $err eq 'Server';
        $err = 'Sender'   if $err eq 'Client';

        my %nice =
          ( code   => $faults->{faultcode}
          , class  => [ $code_ns, $err, @sub_err ]
          , reason => $faults->{faultstring}
          );

        $nice{role}   = $self->roleAbbreviation($faults->{faultactor})
            if $faults->{faultactor};

        my @details
           = map { UNIVERSAL::isa($_,'XML::LibXML::Element')
                 ? $_->toString(1)
                 : $_} @$details;

        $nice{detail} = (@details==1 ? $details[0] : \@details)
            if @details;

        $data->{$label}  = \%nice;
        $faults->{_NAME} = $label;
    };
}

sub replyMustUnderstandFault($)
{   my ($self, $type) = @_;

    { Fault =>
        { faultcode   => pack_type($self->envelopeNS, 'MustUnderstand')
        , faultstring => "SOAP mustUnderstand $type"
        }
    };
}

sub roleURI($) { $_[1] && $_[1] eq 'NEXT' ? SOAP11NEXT : $_[1] }

sub roleAbbreviation($) { $_[1] && $_[1] eq SOAP11NEXT ? 'NEXT' : $_[1] }

=chapter DETAILS

=section Receiving faults in SOAP1.1

When faults are received, they will be returned with the C<Faults> key
in the data structure.  So:

  my $answer = $call->($question);
  if($answer->{Faults}) { ... }

As extra service, for each of the fault types, as defined with
M<compileMessage(faults)>, a decoded structure is included.  The name
of that structure can be found like this:

  if(my $faults = $answer->{Faults})
  {   my $name    = $faults->{_NAME};
      my $decoded = $answer->{$name};
      ...
  }

The untranslated C<$faults> HASH looks like this:

 Fault =>
   { faultcode => '{http://schemas.xmlsoap.org/soap/envelope/}Server.first'
   , faultstring => 'my mistake'
   , faultactor => 'http://schemas.xmlsoap.org/soap/actor/next'
   , detail => { '{http://test-types}fault_one' => [ XMLNODES ] }
   , _NAME => 'fault1'
   }

The C<_NAME> originates from the M<compileMessage(faults)> option:

   $soap->compileMessage('RECEIVER', ...
     , faults => [ fault1 => '{http://test-types}fault_one' ] );

Now, automatically the answer will contain the decoded fault
structure as well:

  fault1 =>
    { code => '{http://schemas.xmlsoap.org/soap/envelope/}Server.first'
    , class  => [ 'http://schemas.xmlsoap.org/soap/envelope/'
         , 'Receiver', 'first' ]
    , reason => 'my mistake',
    , role   => 'NEXT'
    , detail => { help => 'please ignore' }
    }

The C<detail> is the decoding of the XMLNODES, which are defined to
be of type C<< {http://test-types}fault_one >>.

The C<class> is an unpacked version of the code.  SOAP1.2 is using the
(better) terms C<Sender> and C<Receiver>.

C<role> is constructed by decoding the C<faultactor> using
M<roleAbbreviation()>.  The names are closer to the SOAP1.2 specification.

If the received fault is of an unpredicted type, then key C<body>
is used, and the C<detail> will list the unparsed XMLNODEs.  When there
are no details, (according to the specs) the error must be caused by
a header problem, so the C<header> key is used.

=cut

1;
