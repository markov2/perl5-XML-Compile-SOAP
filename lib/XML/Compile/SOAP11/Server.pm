use warnings;
use strict;

package XML::Compile::SOAP11::Server;
use base 'XML::Compile::SOAP11', 'XML::Compile::SOAP::Server';

use Log::Report 'xml-compile-soap', syntax => 'SHORT';
use XML::Compile::SOAP::Util qw/SOAP11ENV/;
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

# Compile-time
sub faultNotImplemented($)
{   my ($self, $name) = @_;

    sub
    {   my ($soap, $doc, $data) = @_;
        +{ Fault =>
           { faultcode   => pack_type(SOAP11ENV, 'Server.notImplemented')
           , faultstring => "soap11 operation $name not implemented"
           , faultactor  => $soap->role
           }
        }
    };
}

sub faultValidationFailed($$$)
{   my ($self, $doc, $name, $string) = @_;
    my $strtype = pack_type SCHEMA2001, 'string';
    my $errors  = $doc->createElement('error');
    $errors->appendText($string);

    +{ Fault =>
         { faultcode   => pack_type(SOAP11ENV, 'Server.validationFailed')
         , faultstring => "soap11 operation $name called with invalid data"
         , faultactor  => $self->role
         , details     => $errors
         }
     };
}

sub faultUnsupportedSoapVersion($$)
{   my ($self, $doc, $envns) = @_;
    +{ Fault =>
         { faultcode   => pack_type(SOAP11ENV, 'Server.versionNotSupported')
         , faultstring => "server does not support version $envns"
         , faultactor  => $self->role
         }
     };
}

sub faultNotSoapMessage($)
{   my ($self, $doc, $nodetype) = @_;
    +{ Fault =>
         { faultcode   => pack_type(SOAP11ENV, 'Server.notSoapMessage')
         , faultstring => "the message is not SOAP envelope but $nodetype"
         , faultactor  => $self->role
         }
     };
}

sub faultMessageNotRecognized($$)
{   my ($self, $doc, $name) = @_;
   +{ Fault =>
       { faultcode   => pack_type(SOAP11ENV, 'Server.notRecognized')
       , faultstring => "soap11 message $name not recognized"
       , faultactor  => $self->role
       }
    };
}

sub faultTryOtherProtocol($$)
{   my ($self, $doc, $version) = @_;
    +{ Fault =>
        { faultcode   => pack_type(SOAP11ENV, 'Server.tryUpgrade')
        , faultstring => "message not found in soap11, try other soap version"
        , faultactor  => $self->role
        }
     };
}

1;
