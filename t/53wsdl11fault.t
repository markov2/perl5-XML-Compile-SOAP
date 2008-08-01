#!/usr/bin/perl
# Test interpretation of WSDL faults.

use warnings;
use strict;

use lib 'lib','t';
use TestTools;

use Data::Dumper;
$Data::Dumper::Indent = 1;

use XML::Compile::WSDL11;
use XML::Compile::Transport::SOAPHTTP;
use XML::Compile::Util       qw/SCHEMA2001/;
use XML::Compile::SOAP::Util qw/WSDL11 WSDL11SOAP SOAP11HTTP/;
use XML::Compile::Tester;

use Test::More tests => 12;
use Test::Deep;

my $testNS     = 'http://any-ns';
my $schema2001 = SCHEMA2001;
my $wsdl11     = WSDL11;
my $wsdl11soap = WSDL11SOAP;
my $soap11http = SOAP11HTTP;

my $xml_wsdl = <<"__WSDL";
<?xml version="1.0"?>
<definitions name="two-way-test"
   targetNamespace="$testNS"
   xmlns:tns="$testNS"
   xmlns:soap="$wsdl11soap"
   xmlns="$wsdl11">

   <types>
     <schema targetNamespace="$testNS" xmlns:tns="$testNS"
       xmlns="$schema2001" elementFormDefault="qualified">
       <element name="Send" type="int" />
       <element name="Response" type="int" />
       <element name="Broken" type="tns:Broken" />
       <complexType name="Broken">
         <sequence>
           <element name="message" type="string" minOccurs="0" />
         </sequence>
       </complexType>
     </schema>
   </types>

   <message name="SendInput">
     <part name="body" element="tns:Send"/>
   </message>

   <message name="SendResponse">
     <part name="body" element="tns:Response"/>
   </message>

   <message name="WentWrong">
     <part name="fault" element="tns:Broken"/>
   </message>

   <portType name="ProcessorPort">
     <operation name="doSend">
       <input message="tns:SendInput"/>
       <output message="tns:SendResponse"/>
       <fault message="tns:WentWrong" name="WentWrong"/>
     </operation>
   </portType>

   <binding name="ProcessorBinding" type="tns:ProcessorPort">
     <soap:binding style="document" transport="$soap11http"/>
     <operation name="doSend">
        <soap:operation soapAction="http://any-action" />
        <input><soap:body use="literal"/></input>
        <output><soap:body use="literal"/></output>
        <fault name="WentWrong"><soap:fault name="WentWrong" use="literal"/></fault>
     </operation>
   </binding>

   <service name="MyService">
     <documentation>My two-way service</documentation>
     <port name="pleaseProcess" binding="tns:ProcessorBinding">
       <soap:address location="fake-location"/>
     </port>
   </service>
</definitions>
__WSDL

###
### BEGIN OF TESTS
###

my $wsdl = XML::Compile::WSDL11->new($xml_wsdl);

ok(defined $wsdl, "created object");
isa_ok($wsdl, 'XML::Compile::WSDL11');
is($wsdl->wsdlNamespace, WSDL11);

my $op = eval { $wsdl->operation('doSend') };
my $err = $@ || '';
ok(defined $op, 'existing operation');
is($@, '', 'no errors');
isa_ok($op, 'XML::Compile::WSDL11::Operation');
is($op->kind, 'request-response');

my $client = $op->compileClient(transport_hook => \&fake_server);
ok(defined $client, 'compiled client');
isa_ok($client, 'CODE');

my ($answer, $trace) = $client->(body => 999);

ok(defined $answer, 'got answer');
is($answer->{Fault}->{faultstring}, 'any-ns.WentWrong', 'got fault string');
is($answer->{WentWrong}->{detail}->{message}, 'Oh noes', 'parsed response XML');

sub fake_server($$)
{  my ($request, $trace) = @_;
   my $content = $request->decoded_content;

   if($content =~ m!<x0:Send>999</x0:Send>!) {
      return HTTP::Response->new(500, 'Internal Server Error'
      , [ 'Content-Type' => 'text/xml;charset=utf-8' ], <<__RESPONSE);
<?xml version="1.0" encoding="UTF-8"?>
<env:Envelope xmlns:env="http://schemas.xmlsoap.org/soap/envelope/"
              xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
              xmlns:ns0="$testNS"
              >
  <env:Body>
    <env:Fault xsi:type="env:Fault">
      <faultcode>env:Server</faultcode>
      <faultstring>any-ns.WentWrong</faultstring>
      <detail><ns0:Broken><ns0:message>Oh noes</ns0:message></ns0:Broken></detail>
    </env:Fault>
  </env:Body>
</env:Envelope>
__RESPONSE
   } else {
      return HTTP::Response->new(202, 'accepted'
      , [ 'Content-Type' => 'text/plain' ], 'there is no body');
   }
}
