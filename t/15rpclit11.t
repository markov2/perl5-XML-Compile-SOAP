#!/usr/bin/perl
# Test SOAP RPC literal.  This looks very much like the document SOAP,
# but the content is not known when the message gets compiled, but is
# added in a later stage.

use warnings;
use strict;

use lib 'lib','t';
use TestTools;
use Test::Deep   qw/cmp_deeply/;

use Data::Dumper;
$Data::Dumper::Indent = 1;

use XML::Compile::Util qw/pack_type/;
use XML::Compile::SOAP11::Client;
use XML::Compile::Tester;

use Test::More tests => 12;
use XML::LibXML;
use Log::Report;

my $schema = <<__HELPERS;
<schema targetNamespace="$TestNS"
  elementFormDefault="qualified"
  xmlns="$SchemaNS">

# mimic types of SOAP1.1 section 1.3 example 1
<element name="GetLastTradePrice">
  <complexType>
     <all>
       <element name="symbol" type="string"/>
     </all>
  </complexType>
</element>

<element name="GetLastTradePriceResponse">
  <complexType>
     <all>
        <element name="price" type="float"/>
     </all>
  </complexType>
</element>

<element name="Transaction" type="int"/>
</schema>
__HELPERS

#
# Create and interpret a message
#

my $client = XML::Compile::SOAP11::Client->new;
isa_ok($client, 'XML::Compile::SOAP11::Client');
isa_ok($client, 'XML::Compile::SOAP11');

$client->schemas->importDefinitions($schema);

# Sender
# produce message

my $output = $client->compileMessage
 ( 'SENDER'
 , header => [ transaction => "{$TestNS}Transaction" ]
 , style  => 'rpc-literal'
 , mustUnderstand => 'transaction'
 , destination    => [ transaction => 'NEXT http://actor' ]
 );
is(ref $output, 'CODE', 'got writer');

# no RPC defined yet: error

my $xml1 = try { $output->() };
ok($@, 'no wrapper');
like($@->wasFatal->message, qr/^rpc style requires/);
ok(!defined $xml1);

# Receiver

my $input = $client->compileMessage
 ('RECEIVER'
 , style => 'rpc-literal'
 );
is(ref $input, 'CODE', 'compiled a server');

# Transporter

sub fake_server(@)
{   my ($request, $trace) = @_;

    # Check the request

    isa_ok($request, 'HTTP::Request');

    compare_xml($request->decoded_content, <<__XML, 'request content');
<?xml version="1.0" encoding="UTF-8"?>
<SOAP-ENV:Envelope
   xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/"
   xmlns:x0="http://test-types">
  <SOAP-ENV:Header>
    <x0:Transaction
      mustUnderstand="1"
      actor="http://schemas.xmlsoap.org/soap/actor/next http://actor">
        5
    </x0:Transaction>
  </SOAP-ENV:Header>
  <SOAP-ENV:Body>
    <x0:GetLastTradePrice xmlns:x0="http://test-types">
      <x0:symbol>IBM</x0:symbol>
    </x0:GetLastTradePrice>
  </SOAP-ENV:Body>
</SOAP-ENV:Envelope>
__XML

    # Produce answer

    my $response = HTTP::Response->new
      ( 200
      , 'standard response'
      , [ 'Content-Type' => 'text/xml' ]
      , <<__XML);
<?xml version="1.0" encoding="UTF-8"?>
<SOAP-ENV:Envelope
   xmlns:x0="http://test-types"
   xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/">
  <SOAP-ENV:Body>
    <x0:GetLastTradePriceResponse xmlns:x0="http://test-types">
      <x0:price>3.14</x0:price>
    </x0:GetLastTradePriceResponse>
  </SOAP-ENV:Body>
</SOAP-ENV:Envelope>
__XML

   $response;
}

use XML::Compile::Transport::SOAPHTTP;
my $transport = XML::Compile::Transport::SOAPHTTP->new;
my $http = $transport->compileClient(hook => \&fake_server);

# define first RPC

my $trade_price = $client->compileClient
 ( # the general part
   name      => 'trade price'
 , encode    => $output
 , decode    => $input
 , transport => $http

   # the RPC specific part
 , rpcout => pack_type($TestNS, 'GetLastTradePrice')
 , rpcin  => pack_type($TestNS, 'GetLastTradePriceResponse')
 );

is(ref $trade_price, 'CODE', 'rpc trade_price');

my $answer = $trade_price->({symbol => 'IBM'}, transaction => 5);

isa_ok($answer, 'HASH', 'answer received');
cmp_deeply($answer, {GetLastTradePriceResponse => {price => 3.14}} );
