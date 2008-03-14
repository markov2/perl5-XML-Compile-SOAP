use warnings;
use strict;

package XML::Compile::SOAP::Server;

use Log::Report 'xml-compile-soap', syntax => 'SHORT';

=chapter NAME
XML::Compile::SOAP::Server - server-side SOAP message processing

=chapter SYNOPSIS
  # THIS CANNOT BE USED YET: Preparations for new module
  # named XML::Compile::SOAP::Daemon

  my $soap   = XML::Compile::SOAP11::Server->new;
  my $input  = $soap->compileMessage('RECEIVER', ...);
  my $output = $soap->compileMessage('SENDER', ...);

  $soap->compileHandler
    ( name => $name, input => $input, output => $output
    , callback => \$my_handler
    );

  my $daemon = XML::Compile::SOAP::HTTPDaemon->new(...);
  $daemon->addHandler($type => $daemon);

=chapter DESCRIPTION
This class defines methods that each server for the SOAP
message exchange protocols must implement.

=chapter METHODS

=section Instantiation
This object can not be instantiated, but is only used as secundary
base class.  The primary must contain the C<new>.
=cut

sub new(@) { panic __PACKAGE__." only secundary in multiple inheritance" }
sub init($) { shift }

=method compileHandler OPTIONS

=requires name STRING
The identification for this action, for instance used for logging.  When
the action is created via a WSDL, the portname will be used here.

It is a pitty that the portname is not passed in the SOAP message,
because it is not so easy to detect which handler must be called.

=option  action STRING
=default action <undef>
A possible SOAPaction string from the HTTP header.  It might be used
to identify an incoming message (but probably not, because it is against
the official intent of the header field which is routing only).

=option  decode CODE
=default decode <undef>
The CODE reference is used to decode the (parsed) XML input message
into the pure Perl request.  The reference is a READER, created with
M<XML::Compile::Schema::compile()>.  If no input decoder is specified,
then the  callbackhandler will be called with the un-decoded
M<XML::LibXML::Document> node.

=option  encode CODE
=default encode <undef>
The CODE reference is used to encode the Perl answer structure into the
output message.  The reference is a WRITER.  created with
M<XML::Compile::Schema::compile()>.  If no output encoder is specified,
then the callback must return an M<XML::LibXML::Document>, or only
produce error messages.

=option  callback CODE
=default callback <fault: not implemented>
As input, the SERVER object and the translated input message (Perl version)
are passed in.  As output, a suitable output structure must be produced.
If the callback is not set, then a fault message will be returned to the
user.

=cut

sub compileHandler(@)
{   my ($self, %args) = @_;

    my $decode = $args{decode};
    my $encode = $args{encode} || $self->compileMessage('SENDER');
    my $name   = $args{name}
        or error __x"each server handler requires a name";

    # even without callback, we will validate
    my $callback = $args{callback} || $self->faultNotImplemented($name);

    sub
    {   my ($xmlin) = @_;
        my $doc  = XML::LibXML::Document->new('1.0', 'UTF-8');
        my ($data, $answer);

        if($decode)
        {   $data = try { $decode->($xmlin) };
            if($@)
            {   my $exception = $@->wasFatal;
                $exception->throw(reason => 'info');
                $answer = $self->faultValidationFailed($doc, $name,
                    $exception->message->toString);
            }
        }
        else
        {   $data = $xmlin;
        }

        $answer = $callback->($self, $doc, $data) if $data;

        return $answer
            if UNIVERSAL::isa($answer, 'XML::LibXML::Document');

        unless($answer)
        {   warning "handler {name} did not return an answer", name => $name;
            $answer = $self->faultNoAnswerProduced($doc);
        }

        $encode->($doc, $answer);
    };
}

1;
