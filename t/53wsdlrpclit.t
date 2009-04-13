#!/usr/bin/perl
# Test SOAP

use warnings;
use strict;

use lib 'lib','t';
use TestTools;
use Test::Deep   qw/cmp_deeply/;

#use Log::Report mode => 3;  # debugging

use Data::Dumper;
$Data::Dumper::Indent = 1;

use XML::Compile::WSDL11;
use XML::Compile::Tester;

use Test::More tests => 24;
use XML::LibXML;
use XML::Compile::SOAP::Util ':soap11';
use XML::Compile::SOAP11;
use XML::Compile::Transport::SOAPHTTP;

my $NS      = 'urn:example:wsdl';
my $NSEXP   = 'urn:sonae:elegibilidade:exp';
my $soapenv = SOAP11ENV;

my $schema = <<_SCHEMA;
<?xml version="1.0" encoding="UTF-8"?>
<wsdl:definitions
 xmlns:wsdl="http://schemas.xmlsoap.org/wsdl/"
 xmlns:http="http://schemas.xmlsoap.org/wsdl/http/"
 xmlns:soap="http://schemas.xmlsoap.org/wsdl/soap/"
 xmlns:xsd="http://www.w3.org/2001/XMLSchema"
 xmlns:exp="$NS"
 targetNamespace="$NS">

 <wsdl:types>
  <xsd:schema targetNamespace="$NS">

   <xsd:complexType name="list_part_type">
    <xsd:all>
     <xsd:element name="list" type="exp:listType" />
    </xsd:all>
   </xsd:complexType>

   <xsd:element name="list" type="exp:listType" />
   <xsd:complexType name="listType">
    <xsd:sequence>
     <xsd:element minOccurs="0" maxOccurs="unbounded" name="item">
      <xsd:complexType>
       <xsd:sequence>
        <xsd:element name="id" type="xsd:int"/>
        <xsd:element name="name" type="xsd:string"/>
       </xsd:sequence>
      </xsd:complexType>
     </xsd:element>
    </xsd:sequence>
   </xsd:complexType>

   <xsd:element name="result" type="xsd:int"/>
  </xsd:schema>
 </wsdl:types>

 <wsdl:message name="request_via_element">
   <wsdl:part name="list" element="exp:list"/>
 </wsdl:message>
 <wsdl:message name="request_via_type">
   <wsdl:part name="list" type="exp:list_part_type"/>
 </wsdl:message>
 <wsdl:message name="answer_via_element">
   <wsdl:part name="result" element="exp:result"/>
 </wsdl:message>
 <wsdl:message name="answer_via_type">
   <wsdl:part name="result" type="xsd:int"/>
 </wsdl:message>

 <wsdl:portType name="query">
   <wsdl:operation name="using_element">
     <wsdl:input message="exp:request_via_element"/>
     <wsdl:output message="exp:answer_via_element"/>
   </wsdl:operation>
   <wsdl:operation name="using_type">
     <wsdl:input message="exp:request_via_type"/>
     <wsdl:output message="exp:answer_via_type"/>
   </wsdl:operation>
 </wsdl:portType>

 <wsdl:binding name="query_SOAPHTTP" type="exp:query">
   <soap:binding style="rpc" transport="http://schemas.xmlsoap.org/soap/http"/>
   <wsdl:operation name="using_element">
     <soap:operation style="rpc"/>
     <wsdl:input>
       <soap:body use="literal" namespace="$NSEXP"/>
     </wsdl:input>
     <wsdl:output>
       <soap:body use="literal" namespace="$NSEXP"/>
     </wsdl:output>
   </wsdl:operation>
   <wsdl:operation name="using_type">
     <soap:operation style="rpc"/>
     <wsdl:input>
       <soap:body use="literal" namespace="$NSEXP"/>
     </wsdl:input>
     <wsdl:output>
       <soap:body use="literal" namespace="$NSEXP"/>
     </wsdl:output>
   </wsdl:operation>
 </wsdl:binding>

 <wsdl:service name="service">
   <wsdl:port binding="exp:query_SOAPHTTP" name="query">
     <soap:address location="http://localhost:3000/ws/exp/soap"/>
   </wsdl:port>
 </wsdl:service>
</wsdl:definitions>
_SCHEMA

### HELPER
my ($server_expects, $server_answers);
sub fake_server($$)
{  my ($request, $trace) = @_;
   my $content = $request->decoded_content;
   compare_xml($content, $server_expects, 'fake server received');
#warn "CONTENT=$content###";

   HTTP::Response->new(200, 'answer manually created'
    , [ 'Content-Type' => 'text/xml' ], $server_answers);
}

#
# Create and interpret a message
#

my $soap = XML::Compile::SOAP11::Client->new;
isa_ok($soap, 'XML::Compile::SOAP11::Client');
isa_ok($soap, 'XML::Compile::SOAP11');

my $wsdl = XML::Compile::WSDL11->new($schema);
ok(defined $wsdl, "created object");
isa_ok($wsdl, 'XML::Compile::WSDL11');

#
# Element part
#

ok(1, "** using element");

my $eop = $wsdl->operation('using_element');
isa_ok($eop, 'XML::Compile::SOAP11::Operation');
is($eop->name, 'using_element');
is($eop->style, 'rpc');

my $er = $eop->compileClient(transport_hook => \&fake_server);
isa_ok($er, 'CODE');

$server_expects = <<_EXPECTS;
<?xml version="1.0" encoding="UTF-8"?>
<SOAP-ENV:Envelope xmlns:SOAP-ENV="$soapenv">
  <SOAP-ENV:Body>
    <using_element>
      <exp:list xmlns:exp="$NS">
        <item><id>1</id><name>aap</name></item>
        <item><id>2</id><name>noot</name></item>
        <item><id>3</id><name>mies</name></item>
      </exp:list>
    </using_element>
  </SOAP-ENV:Body>
</SOAP-ENV:Envelope>
_EXPECTS

$server_answers = <<_ANSWER;
<?xml version="1.0" encoding="UTF-8"?>
<SOAP-ENV:Envelope xmlns:SOAP-ENV="$soapenv">
  <SOAP-ENV:Body>
    <using_element>
      <exp:result xmlns:exp="$NS">3</exp:result>
    </using_element>
  </SOAP-ENV:Body>
</SOAP-ENV:Envelope>
_ANSWER

my %data = ( item =>
   [ { id => 1, name => 'aap'  }
   , { id => 2, name => 'noot' }
   , { id => 3, name => 'mies' } ] );

my $ea = $er->(\%data);
ok(defined $ea, 'got element answer');
isa_ok($ea->{using_element}, 'HASH');
cmp_ok(keys %{$ea->{using_element}}, '==', 1);
is($ea->{using_element}{result}, '3');

#
# Type part
#

ok(1, "** using type");
my $top = $wsdl->operation('using_type');
isa_ok($top, 'XML::Compile::SOAP11::Operation', 'using type');
is($top->name, 'using_type');
is($top->style, 'rpc');

my $tr = $top->compileClient(transport_hook => \&fake_server);
isa_ok($tr, 'CODE');

$server_expects = <<_REQUEST;
<?xml version="1.0" encoding="UTF-8"?>
<SOAP-ENV:Envelope xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/">
 <SOAP-ENV:Body>
  <using_type>
    <list>
      <item><id>1</id><name>aap</name></item>
      <item><id>2</id><name>noot</name></item>
      <item><id>3</id><name>mies</name></item>
    </list>
  </using_type>
 </SOAP-ENV:Body>
</SOAP-ENV:Envelope>
_REQUEST

$server_answers = <<_ANSWER;
<SOAP-ENV:Envelope xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/">
 <SOAP-ENV:Body>
  <using_type>
    <result>5</result>
  </using_type>
 </SOAP-ENV:Body>
</SOAP-ENV:Envelope>
_ANSWER

my $ta = $tr->(list => \%data);
ok(defined $ta, 'got type answer');
isa_ok($ta->{using_type}, 'HASH');
cmp_ok(keys %{$ta->{using_type}}, '==', 1);
is($ta->{using_type}{result}, '5');
