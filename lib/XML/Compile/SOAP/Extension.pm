use warnings;
use strict;

package XML::Compile::SOAP::Extension;
use Log::Report 'xml-compile-soap';

my @ext;

=chapter NAME
XML::Compile::SOAP::Extension - plugins for standards

=chapter SYNOPSYS
 # only as base-class

=chapter DESCRIPTION
This module defines hooks which are used to implement the SOAP and WSDL
extensions.  Where SOAP does lack a lot of useful features, many
working-groups have added components on various spots in the XML
messages.

=chapter METHODS

=section Constructors

=c_method new OPTIONS
=cut

sub new($@) { my $class = shift; (bless {}, $class)->init( {@_} ) }

sub init($)
{   my $self = shift;
    trace "loading extension ".ref $self;
    push @ext, $self;
    $self;
}

=section WSDL11

=method wsdl11Init WSDL, ARGS

=cut

sub wsdl11Init($$)
{   ref shift and return;
    $_->wsdl11Init(@_) for @ext;
}

=section SOAP11

=ci_method soap11OperationInit OPERATION, OPTIONS
=cut

sub soap11OperationInit($@)
{   ref shift and return;
    $_->soap11OperationInit(@_) for @ext;
}

=method soap11ClientWrapper OPERATION, CALL, OPTIONS
=cut

sub soap11ClientWrapper($$@)
{   ref shift and return $_[1];
    my ($op, $call) = (shift, shift);
    $call = $_->soap11ClientWrapper($op, $call, @_) for @ext;
    $call;
}

1;
