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
This module defines hooks which are used to implement the SOAP and
WSDL extensions. Hooks are created on critial spots, where additional
standards play tricks with the logic of SOAP and WSDL. There are a
lot of those standards, for instance Web Service Addressing (WSA,
M<XML::Compile::SOAP::WSA>)

=chapter METHODS

=section Constructors

=c_method new %options
=cut

sub new($@) { my $class = shift; (bless {}, $class)->init( {@_} ) }

sub init($)
{   my $self = shift;
    trace "loading extension ".ref $self;
    push @ext, $self;
    $self;
}

#--------
=section WSDL11

=ci_method wsdl11Init $wsdl, $args
Do not use this hook for adding WSDLs or schemas, unless those are
used to interpret $wsdl or SOAP files correctly.
=cut

### For all methods named below: when called on an object, it is the stub
### for the extension. Only when called as class method, it will walk all
### extension objects.

sub wsdl11Init($$)
{   ref shift and return;
    $_->wsdl11Init(@_) for @ext;
}

#--------
=section SOAP11

=ci_method soap11OperationInit $operation, $args
$args is a reference.
=cut

sub soap11OperationInit($$)
{   ref shift and return;
    $_->soap11OperationInit(@_) for @ext;
}

=method soap11ClientWrapper $operation, $call, $args
=cut

sub soap11ClientWrapper($$$)
{   ref shift and return $_[1];
    my ($op, $call, $args) = @_;
    $call = $_->soap11ClientWrapper($op, $call, $args) for @ext;
    $call;
}

=method soap11HandlerWrapper $operation, $callback, $args
Called before the handler is created, to influence the encoder and
decoder. Returned is a wrapped callback, or the same.
=cut

sub soap11HandlerWrapper($$$)
{   my ($thing, $op, $cb, $args) = @_;
    ref $thing and return $cb;
    $cb = $_->soap11HandlerWrapper($op, $cb, $args) for @ext;
    $cb;
}

#--------
=section SOAP12

=ci_method soap12OperationInit $operation, $args
$args is a reference.
=cut

sub soap12OperationInit($$)
{   ref shift and return;
    $_->soap12OperationInit(@_) for @ext;
}

=method soap12ClientWrapper $operation, $call, $args
=cut

sub soap12ClientWrapper($$$)
{   ref shift and return $_[1];
    my ($op, $call, $args) = @_;
    $call = $_->soap12ClientWrapper($op, $call, $args) for @ext;
    $call;
}

=method soap12HandlerWrapper $operation, $callback, $args
Called before the handler is created, to influence the encoder and
decoder. Returned is a wrapped callback, or the same.
=cut

sub soap12HandlerWrapper($$$)
{   my ($thing, $op, $cb, $args) = @_;
    ref $thing and return $cb;
    $cb = $_->soap12HandlerWrapper($op, $cb, $args) for @ext;
    $cb;
}


1;
