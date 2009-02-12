use warnings;
use strict;

package XML::Compile::SOAP11::Server;
use base 'XML::Compile::SOAP11', 'XML::Compile::SOAP::Server';

use Log::Report 'xml-compile-soap', syntax => 'SHORT';
use XML::Compile::SOAP::Util qw/SOAP11ENV SOAP11NEXT/;
use XML::Compile::Util  qw/pack_type unpack_type SCHEMA2001/;

=chapter NAME
XML::Compile::SOAP11::Server - SOAP1.1 server needs

=chapter SYNOPSIS

=chapter DESCRIPTION
This module does not implement an actual soap server, but the
needs to create the server side.  The server daemon is implemented
by M<XML::Compile::SOAP::Daemon>

=chapter METHODS
=cut

sub init($)
{   my ($self, $args) = @_;
    $self->XML::Compile::SOAP11::init($args);
    $self->XML::Compile::SOAP::Server::init($args);
    $self;
}

sub makeError()
{   my $self = shift;
    $self->faultWriter->(Fault => { @_ } );
}

sub faultNotImplemented($)
{   my ($self, $name) = @_;

    my $message =
      __x"procedure {name} for {version} is not yet implemented"
        , name => $name, version => 'SOAP11';

    $self->makeError
      ( faultcode   => pack_type(SOAP11ENV, 'Server.notImplemented')
      , faultstring => $message
      , faultactor  => SOAP11NEXT
      );
}

sub faultNoAnswerProduced()
{   my ($self) = @_;
    
    my $message;
    $self->makeError
      ( faultcode   => pack_type(SOAP11ENV, 'Server.noAnswer')
      , faultstring => $message
      , faultactor  => $self->role
      );
}

sub faultMessageNotRecognized($$)
{   my ($self, $name, $handlers) = @_;

    my $message;
    if($handlers && @$handlers)
    {   $message =
       __x "{version} body element {name} not recognized, available are {def}"
        , version => 'SOAP11', name => $name, def => $handlers;
    }
    else
    {   $message =
          __x "{version} there are no handlers available, so also not {name}"
            , version => 'SOAP11', name => $name;
    }

    $self->makeError
      ( faultcode   => pack_type(SOAP11ENV, 'Server.notRecognized')
      , faultstring => $message
      , faultactor  => SOAP11NEXT
      );
}

sub faultTryOtherProtocol($$)
{   my ($self, $name, $other) = @_;

    my $message =
      __x"body element {name} not available in {version}, try {other}"
        , name => $name, version => 'SOAP11', other => $other;

    $self->makeError
      ( faultcode   => pack_type(SOAP11ENV, 'Server.tryUpgrade')
      , faultstring => $message
      , faultactor  => SOAP11NEXT
      );
}

1;
