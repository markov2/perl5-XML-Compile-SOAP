use warnings;
use strict;

package XML::Compile::SOAP::Trace;

use Log::Report 'xml-compile-soap', syntax => 'REPORT';
  # no syntax SHORT, because we have own error()

=chapter NAME
XML::Compile::SOAP::Trace - help displaying trace details.

=chapter SYNOPSIS
 my ($answer, $trace) = $call->(%params);
 #now $trace is a XML::Compile::SOAP::Trace

 my $req = $trace->request;   # HTTP message which was sent
 my $res = $trace->response;  # HTTP message received

 my $start = $trace->date;
 my $dura  = $trace->elapse;

 $trace->printTimings;
 $trace->printRequest;
 $trace->printResponse;

=chapter DESCRIPTION
This help module simplifies user access to the trace data,
as produced by a SOAP call (client side).

=chapter METHODS

=section Constructors
=c_method new OPTIONS
Called by the SOAP call implementation; not for normal users.
=cut

sub new($)
{   my ($class, $data) = @_;
    bless $data, $class;
}

=section Accessors

=method start
Returns the (platform dependent) time value which represent the moment
that the call was initiated.  See M<Time::HiRes> method C<time>.
=cut

sub start() {shift->{start}}

=method date
Returns the date string which represent the moment that the call
was initiated.
=cut

sub date() {scalar localtime shift->start}

=method error
Often contains an error message, when something went wrong.
=cut

sub error() {shift->{error}}

=method elapse [KIND]
Returns the time in seconds (with hires, sub-second detail) of a part of
the SOAP communication. Some values may be C<undef>.  Elapse without
argument will return the total time elapsed.

As KINDs are defined C<encode> (the time required by the translator
build by XML::Compile::Schema to translate Perl into an XML::LibXML
tree), C<transport>, and C<decode> (from XML::LibXML tree into Perl)>.
The transport components are also provided seperately, as C<stringify>
(by XML::LibXML to convert a tree into text), C<connect> (for the network
message exchange by HTTP::Daemon), and C<parse> (parsing answer string
into XML)

See M<printTimings()>.

=example
 print $trace->elapse('decode');
=cut

sub elapse($)
{   my ($self, $kind) = @_;
    defined $kind ? $self->{$kind.'_elapse'} : $self->{elapse};
}

=method request
Returns the M<HTTP::Request> object used for this SOAP call.  This might
be quite useful during debugging, because a lot of the processing is
hidden for the user... but you may want to see or log what is actually
begin send.
=cut

sub request() {shift->{http_request}}

=method response
Returns the M<HTTP::Response> object, returned by the remote server.  In
some erroneous cases, the client library will create an error response
without any message was exchanged.
=cut

sub response() {shift->{http_response}}

=section Printing

=method printTimings
Print an overview on various timings to the selected filehandle.
=cut

sub printTimings()
{   my $self = shift;
    print  "Call initiated at: ",$self->date, "\n";
    print  "SOAP call timing:\n";
    printf "      encoding: %7.2f ms\n", $self->elapse('encode')    *1000;
    printf "     stringify: %7.2f ms\n", $self->elapse('stringify') *1000;
    printf "    connection: %7.2f ms\n", $self->elapse('connect')   *1000;
    printf "       parsing: %7.2f ms\n", $self->elapse('parse')     *1000;

    my $dt = $self->elapse('decode');
    if(defined $dt) { printf "      decoding: %7.2f ms\n", $dt *1000 }
    else            { print  "      decoding:       -    (no xml answer)\n" }

    printf "    total time: %7.2f ms ",  $self->elapse              *1000;
    printf "= %.3f seconds\n\n", $self->elapse;
}

=method printRequest
=cut

sub printRequest(@)
{   my $self = shift;
    my $request = $self->request or return;
    my $req  = $request->as_string;
    $req =~ s/^/  /gm;
    print "Request:\n$req\n";
}

=method printResponse
=cut

sub printResponse(@)
{   my $self = shift;
    my $response = $self->response or return;

    my $resp = $response->as_string;
    $resp =~ s/^/  /gm;
    print "Response:\n$resp\n";
}

1;
