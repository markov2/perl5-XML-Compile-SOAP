use warnings;
use strict;

package XML::Compile::SOAP::Server;

use Log::Report 'xml-compile-soap', syntax => 'SHORT';

use XML::Compile::SOAP::Util qw/:soap11/;
use HTTP::Status qw/RC_OK RC_NOT_ACCEPTABLE RC_INTERNAL_SERVER_ERROR/;

=chapter NAME
XML::Compile::SOAP::Server - server-side SOAP message processing

=chapter SYNOPSIS
  # used by distribution XML::Compile::SOAP::Daemon

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

=c_method new OPTIONS

=option  role URI
=default role 'NEXT'
In SOAP1.1, the term is 'actor', but SOAP1.2 has renamed this into
'role': the role [this daemon] plays in the transport protocol.

Please use the role abbreviations as provided by the protocol
implementations when possible: they will be translated into the
right URI on time.  See M<XML::Compile::SOAP::roleAbbreviation()>
and the constants defined in M<XML::Compile::SOAP::Util>

=cut

sub new(@) { panic __PACKAGE__." only secundary in multiple inheritance" }

sub init($)
{  my ($self, $args) = @_;
   $self->{role} = $self->roleAbbreviation($args->{role} || 'NEXT');
   $self;
}

#---------------------------------

=section Accessors

=method role
Returns the URI of the role (actor) of this server.
=cut

sub role() {shift->{role}}

#---------------------------------

=section Actions

=method compileHandler OPTIONS
Returns an HTTP status code and an M<XML::LibXML::Document> pair.

=requires name STRING
The identification for this action, for instance used for logging.  When
the action is created via a WSDL, the portname will be used here.

It is a pitty that the portname is not passed in the SOAP message,
because it is not so easy to detect which handler must be called.

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

=option  selector CODE
=default selector sub {0}
One way or the other, you have to figure-out whether a message addresses
a certain process.  The callback will only be used if the CODE reference
specified here returns a true value.

The CODE reference will be called with the XML version of the message,
and a HASH which contains the information about the XML collected with
M<XML::Compile::SOAP::messageStructure()> plus the C<soap_version> entry.
=cut

sub compileHandler(@)
{   my ($self, %args) = @_;

    my $decode = $args{decode};
    my $encode = $args{encode}     || $self->compileMessage('SENDER');
    my $name   = $args{name}
        or error __x"each server handler requires a name";
    my $selector = $args{selector} || sub {0};

    # even without callback, we will validate
    my $callback = $args{callback};

    sub
    {   my ($name, $xmlin, $info) = @_;
        $selector->($xmlin, $info) or return;
        trace __x"procedure {name} selected", name => $name;

        my ($data, $answer);

        if($decode)
        {   $data = try { $decode->($xmlin) };
            return ( RC_NOT_ACCEPTABLE, 'input validation failed'
                   , $self->faultValidationFailed($name, $@->wasFatal))
                if $@;
        }
        else
        {   $data = $xmlin;
        }

        $answer = $callback->($self, $data);

        defined $answer
            or return ( RC_INTERNAL_SERVER_ERROR, 'no answer produced'
                      , $self->faultNoAnswerProduced($name));

        !ref $answer || ref $answer eq 'HASH'
            or return $answer;   # something ready or half ready

        my $xmlout = try { $encode->($answer) };
        $@ or return (RC_OK, 'Answer included', $xmlout);

        ( RC_INTERNAL_SERVER_ERROR, 'created response not valid'
        , $self->faultResponseInvalid($name, $@->wasFatal)
        );
    };
}

=method compileFilter OPTIONS
This routine returns a CODE reference which can be used for
M<compileHandler(selector)>; so see whether a certain message has arrived.
On the moment, only the first C<body> element is used to determine that.

=option  body ARRAY-of-TYPES
=default body []

=option  header ARRAY-of-TYPES
=default header <undef>

=option  fault ARRAY-of-TYPES
=default fault <undef>
=cut

sub compileFilter(@)
{   my ($self, %args) = @_;
    my $nodetype;
    if(my $first    = $args{body}{parts}[0])
    {   $nodetype = $first->{element}
#           or panic "cannot handle type parameter in server filter";
            || $args{body}{procedure};  # rpc-literal "type"
    }

    # called with (XML, INFO)
      defined $nodetype
    ? sub { my $f =  $_[1]->{body}[0]; defined $f && $f eq $nodetype }
    : sub { !defined $_[1]->{body}[0] };  # empty body
}

=c_method faultWriter
Returns a CODE reference which can be used to produce faults.
=cut

sub faultWriter()
{   my $thing = shift;
    my $self  = ref $thing ? $thing : $thing->new;
    $self->{fault_writer} ||= $self->compileMessage('SENDER');
}

1;
