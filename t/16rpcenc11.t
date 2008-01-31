#!/usr/bin/perl
# Test RPC message generation
# example from http://www.soapware.org/bdg

use warnings;
use strict;

use lib 'lib','t';
use TestTools;
use Test::Deep qw/cmp_deeply/;

use Data::Dumper;
$Data::Dumper::Indent = 1;

use XML::Compile::SOAP11::Client;
use XML::Compile::SOAP::Util qw/:soap11/;
use XML::Compile::Util       qw/SCHEMA1999 pack_type unpack_type/;

use Math::BigFloat;

use Test::More tests => 8;
use XML::LibXML;
use TestTools qw/compare_xml/;

my $TestNS = 'http://test-ns';

my $client = XML::Compile::SOAP11::Client->new(schema_ns => SCHEMA1999);
ok(defined $client, 'created client');
isa_ok($client, 'XML::Compile::SOAP11::Client');

my $int     = pack_type SCHEMA1999, 'int';
my $MYNS    = 'http://www.soapware.org/';

my $output = $client->compileMessage('SENDER', style  => 'rpc-encoded');
is(ref $output, 'CODE', 'got writer');

my $input = $client->compileMessage('RECEIVER', style => 'rpc-encoded');
is(ref $input, 'CODE', 'compiled a server');

sub fake_server(@)
{   my ($request, $trace) = @_;

    # Check the request

    isa_ok($request, 'HTTP::Request');
    compare_xml($request->decoded_content, <<__XML, 'request content');
<?xml version="1.0" encoding="UTF-8"?>
<SOAP-ENV:Envelope
   xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/">
  <SOAP-ENV:Body>
    <m:getStateName
       xmlns:m="http://www.soapware.org/"
       xmlns:xsd="http://www.w3.org/1999/XMLSchema"
       xmlns:xsi="http://www.w3.org/1999/XMLSchema-instance"
       SOAP-ENV:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
      <statenum xsi:type="xsd:int">41</statenum>
    </m:getStateName>
    <dummy xsi:type="xsd:int">0</dummy>
  </SOAP-ENV:Body>
</SOAP-ENV:Envelope>
__XML

    # Produce answer

    HTTP::Response->new
      ( 200
      , 'standard response'
      , [ 'Content-Type' => 'text/xml' ]
      , <<__XML);
<?xml version="1.0" encoding="UTF-8"?>
<SOAP-ENV:Envelope
   SOAP-ENV:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"
   xmlns:SOAP-ENC="http://schemas.xmlsoap.org/soap/encoding/"
   xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/"
   xmlns:xsd="http://www.w3.org/1999/XMLSchema"
   xmlns:xsi="http://www.w3.org/1999/XMLSchema-instance"
>
   <SOAP-ENV:Body>
      <m:getStateNameResponse xmlns:m="http://www.soapware.org/">
         <Result xsi:type="xsd:string">South Dakota</Result>
      </m:getStateNameResponse>
   </SOAP-ENV:Body>
</SOAP-ENV:Envelope>
__XML
}

use XML::Compile::Transport::SOAPHTTP;
my $transport = XML::Compile::Transport::SOAPHTTP->new;
my $http = $transport->compileClient(hook => \&fake_server);

# define the output RPC message

sub rpc_outgoing($$$)
{   my ($soap, $doc, $data) = @_;
    $soap->encAddNamespaces(m => $MYNS);

    my $num  = $soap->typed($int, statenum => 41);
    my $body = $soap->struct(pack_type($MYNS, 'getStateName'), $num);

    # just to test that it is possible to return multiple body elements.
    my $dummy = $soap->typed($int, dummy => 0);

    ($body, $dummy);
}

my $get_state = $client->compileClient
  ( # the general part
    name   => 'state name'
  , encode => $output,  decode => $input, transport => $http
  , rpcout => \&rpc_outgoing
  # default rpcin
  );

my $answer = $get_state->();
ok(defined $answer, 'call success');

cmp_deeply($answer, {getStateNameResponse => 'South Dakota'});
