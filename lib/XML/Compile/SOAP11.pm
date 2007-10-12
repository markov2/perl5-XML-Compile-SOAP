use warnings;
use strict;

package XML::Compile::SOAP11;
use base 'XML::Compile::SOAP';

use Log::Report 'xml-compile-soap', syntax => 'SHORT';
use XML::Compile::Util  qw/pack_type unpack_type/;

my $base       = 'http://schemas.xmlsoap.org/soap';
my $actor_next = "$base/actor/next";
my $soap11_env = "$base/envelope/";
my $soap12_env = 'http://www.w3c.org/2003/05/soap-envelope';

XML::Compile->addSchemaDirs(__FILE__);
XML::Compile->knownNamespace
 ( "$base/encoding/" => 'soap-encoding.xsd'
 , $soap11_env       => 'soap-envelope.xsd'
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
    my $env = $args->{envelope_ns} ||= "$base/envelope/";
    my $enc = $args->{encoding_ns} ||= "$base/encoding/";
    $self->SUPER::init($args);

    my $schemas = $self->schemas;
    $schemas->importDefinitions($env);
    $schemas->importDefinitions($enc);
    $self;
}

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
    {   $actors =~ s/\b(\S+)\b/$self->roleAbbreviation($1)/ge;

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
    $args->{prefix_table}
     = [ ''         => 'do not use'
       , 'SOAP-ENV' => $self->envelopeNS
       , 'SOAP-ENC' => $self->encodingNS
       , xsd        => 'http://www.w3.org/2001/XMLSchema'
       , xsi        => 'http://www.w3.org/2001/XMLSchema-instance'
       ];

    $self->SUPER::sender($args);
}

sub writerConvertFault($$)
{   my ($self, $faultname, $data) = @_;
    my %copy = %$data;

    my $code = delete $copy{Code};
    $copy{faultcode} ||= $self->convertCodeToFaultcode($faultname, $code);

    my $reasons = delete $copy{Reason};
    $copy{faultstring} = $reasons->[0]
        if ! $copy{faultstring} && ref $reasons eq 'ARRAY';

    delete $copy{Node};
    my $role  = delete $copy{Role};
    my $actor = delete $copy{faultactor} || $role;
    $copy{faultactor} = $self->roleAbbreviation($actor) if $actor;
}

sub convertCodeToFaultcode($$)
{   my ($self, $faultname, $code) = @_;

    my $value = $code->{Value}
        or error __x"SOAP1.2 Fault {name} Code requires Value"
              , name => $faultname;

    my ($ns, $class) = unpack_type $value;
    $ns eq $soap12_env
        or error __x"SOAP1.2 Fault {name} Code Value {value} not in {ns}"
              , name => $faultname, value => $value, ns => $soap12_env;

    my $faultcode
      = $class eq 'Sender'   ? 'Client'
      : $class eq 'Receiver' ? 'Server'
      :                        $class;  # unchanged
      # DataEncodingUnknown MustUnderstand VersionMismatch

    for(my $sub = $code->{Subcode}; defined $sub; $sub = $sub->{Subcode})
    {   my $subval = $sub->{Value}
           or error __x"SOAP1.2 Fault {name} subcode requires Value"
              , name => $faultname;
        my ($subns, $sublocal) = unpack_type $subval;
        $faultcode .= '.' . $sublocal;
    }

    pack_type $soap11_env, $faultcode;
}

=method roleAbbreviation STRING
Translates actor abbreviations into URIs.  The only one defined for
SOAP1.1 is C<NEXT>.  Returns the unmodified STRING in all other cases.
=cut

sub roleAbbreviation($) { $_[1] eq 'NEXT' ? $actor_next : $_[1] }

1;
