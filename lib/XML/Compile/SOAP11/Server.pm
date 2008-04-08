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

sub faultNotImplemented($)
{   my ($thing, $message) = @_;

    { Fault =>
      { faultcode   => pack_type(SOAP11ENV, 'Server.notImplemented')
      , faultstring => $message
      , faultactor  => SOAP11NEXT
      }
    };
}

sub faultValidationFailed($$$)
{   my ($self, $message, $exception) = @_;

    my $strtype = pack_type SCHEMA2001, 'string';
    my $errors  = XML::LibXML::Element->new('error');
    $errors->appendText($exception->message->toString);

    { Fault =>
      { faultcode   => pack_type(SOAP11ENV, 'Server.validationFailed')
      , faultstring => $message
      , faultactor  => $self->role
      , details     => $errors
      }
    };
}

sub faultNoAnswerProduced($)
{   my ($self, $message) = @_;
    { Fault =>
      { faultcode   => pack_type(SOAP11ENV, 'Server.noAnswer')
      , faultstring => $message
      , faultactor  => $self->role
      }
    };
}

sub faultMessageNotRecognized($)
{   my ($thing, $message) = @_;
    { Fault =>
      { faultcode   => pack_type(SOAP11ENV, 'Server.notRecognized')
      , faultstring => $message
      , faultactor  => SOAP11NEXT
      }
    };
}

sub faultTryOtherProtocol($$)
{   my ($thing, $message) = @_;
    { Fault =>
      { faultcode   => pack_type(SOAP11ENV, 'Server.tryUpgrade')
      , faultstring => $message
      , faultactor  => SOAP11NEXT
      }
    };
}

1;
