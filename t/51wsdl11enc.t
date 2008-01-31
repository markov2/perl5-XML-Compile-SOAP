#!/usr/bin/perl
# Test interpretation of WSDL with RPC/encoded.
# Example from http://www.developerfusion.co.uk/show/4694/3/

use warnings;
use strict;

use lib 'lib','t';
use TestTools;

use Data::Dumper;
$Data::Dumper::Indent = 1;

use XML::Compile::WSDL11;
use XML::Compile::Transport::SOAPHTTP;
use XML::Compile::SOAP::Util qw/WSDL11/;
use XML::Compile::Util       qw/SCHEMA2001 pack_type/;

use Test::More tests => 13;
use Test::Deep;

my $wsdlns   = WSDL11;

my $service = <<'__WSDL';
<?xml version="1.0" encoding="UTF-8"?>
<wsdl:definitions
   targetNamespace="http://cyclic.test"
   xmlns:impl="http://cyclic.test"
   xmlns:intf="http://cyclic.test"
   xmlns:soapenc="http://schemas.xmlsoap.org/soap/encoding/"
   xmlns:wsdl="http://schemas.xmlsoap.org/wsdl/"
   xmlns:wsdlsoap="http://schemas.xmlsoap.org/wsdl/soap/"
   xmlns:xsd="http://www.w3.org/2001/XMLSchema">

  <wsdl:types>
    <schema targetNamespace="http://cyclic.test"
       xmlns="http://www.w3.org/2001/XMLSchema" xmlns:impl="http://cyclic.test"
       xmlns:intf="http://cyclic.test"
       xmlns:soapenc="http://schemas.xmlsoap.org/soap/encoding/"
       xmlns:wsdl="http://schemas.xmlsoap.org/wsdl/"
       xmlns:xsd="http://www.w3.org/2001/XMLSchema">
      <import namespace="http://schemas.xmlsoap.org/soap/encoding/"/>
      <complexType name="Person">
        <sequence>
          <element name="name" nillable="true" type="xsd:string"/>
          <element name="friend" nillable="true" type="impl:Person"/>
        </sequence>
      </complexType>
      <element name="Person" nillable="true" type="impl:Person"/>
    </schema>
  </wsdl:types>

  <wsdl:message name="makeFriendResponse">
    <wsdl:part name="makeFriendReturn" type="intf:Person"/>
  </wsdl:message>

  <wsdl:message name="makeFriendRequest">
    <wsdl:part name="A" type="intf:Person"/>
    <wsdl:part name="B" type="intf:Person"/>
  </wsdl:message>

  <wsdl:portType name="MakeFriends">
    <wsdl:operation name="makeFriend" parameterOrder="A B">
      <wsdl:input message="intf:makeFriendRequest"   name="makeFriendRequest"/>
      <wsdl:output message="intf:makeFriendResponse" name="makeFriendResponse"/>
    </wsdl:operation>
  </wsdl:portType>

  <wsdl:binding name="MakeFriendsSoapBinding" type="intf:MakeFriends">
    <wsdlsoap:binding style="rpc"
       transport="http://schemas.xmlsoap.org/soap/http"/>
    <wsdl:operation name="makeFriend">
      <wsdlsoap:operation soapAction=""/>
      <wsdl:input name="makeFriendRequest">
        <wsdlsoap:body
           encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"
           namespace="http://cyclic.test" use="encoded"/>
      </wsdl:input>
      <wsdl:output name="makeFriendResponse">
        <wsdlsoap:body
           encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"
           namespace="http://cyclic.test" use="encoded"/>
      </wsdl:output>
    </wsdl:operation>
  </wsdl:binding>

  <wsdl:service name="MakeFriendsService">
    <wsdl:port binding="intf:MakeFriendsSoapBinding" name="MakeFriends">
      <wsdlsoap:address
location="http://localhost:9080/CyclicTestEJBClient/services/MakeFriends"/>
    </wsdl:port>
  </wsdl:service>
</wsdl:definitions>
__WSDL

my $websphere_answer = <<'__WEBSPHERE';
  <soapenv:Body
    soapenv:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"
    xmlns:soapenc="http://schemas.xmlsoap.org/soap/encoding/">
    <makeFriendResponse xmlns="http://cyclic.test">
      <makeFriendReturn href="#id0" xmlns=""/>
    </makeFriendResponse>
    <multiRef  id="id0" soapenc:root="0"
      soapenv:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"
      xsi:type="ns-520570027:Person"
      xmlns:ns-520570027="http://cyclic.test"
      xmlns="">
     <name xsi:type="xsd:string">John</name>
     <friend href="#id1"/>
    </multiRef>
    <multiRef  id="id1" soapenc:root="0"
       soapenv:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"
       xsi:type="ns-520570027:Person"
       xmlns:ns-520570027="http://cyclic.test"
       xmlns="">
      <name xsi:type="xsd:string">Jason</name>
      <friend href="#id0"/>
    </multiRef>
  </soapenv:Body>
__WEBSPHERE

my $dotnet_answer = <<'__DOTNET';
  <soapenv:Body
    soapenv:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"
    xmlns:tns="http://cyclic.test"
    xmlns:types="http://cyclic.test">
   <tns:makeFriendsResponse>
     <makeFriendsResult href="#id1" />
   </tns:makeFriendsResponse>
   <types:Person id="id1" xsi:type="types:Person">
     <name xsi:type="xsd:string">John</name>
     <friend href="#id2" />
   </types:Person>
   <types:Person id="id2" xsi:type="types:Person">
     <name xsi:type="xsd:string">Jason</name>
     <friend href="#id1" />
   </types:Person>
  </soapenv:Body >
__DOTNET

my $TestNS = 'http://cyclic.test';

###
### BEGIN OF TESTS
###

my $wsdl = XML::Compile::WSDL11->new($service);
ok(defined $wsdl, "created object");
isa_ok($wsdl, 'XML::Compile::WSDL11');
is($wsdl->wsdlNamespace, $wsdlns);

my @services = $wsdl->find('service');
cmp_ok(scalar(@services), '==', 1, 'find service list context');
is($services[0]->{name}, 'MakeFriendsService');

#
# Encode the data from user-level
#

sub make_friend_request($$$)
{   my ($soap, $doc, $data) = @_;
    ref $data eq 'ARRAY'
        or die "ARRAY of two names is required";

    my @names = @$data;
    @$data==2
        or die "requires two names";

    $soap->encAddNamespaces(p => $TestNS);

    my $person_type = pack_type $TestNS, 'Person';
    my @people;
    foreach my $name (@names)
    {   my $n = $soap->typed(string => name => $name);
        my $f = $soap->nil('friend');
        push @people, $soap->struct($person_type, $n, $f);
    }

    $soap->struct(pack_type($TestNS, 'makeFriends') => @people);
}

my $prepared_answer;
sub fake_server($$)
{   my ($request, $trace) = @_;
    isa_ok($request, 'HTTP::Request', 'constucted request');
    compare_xml($request->decoded_content, <<__XML);
<?xml version="1.0" encoding="UTF-8"?>
<SOAP-ENV:Envelope
   xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/">
  <SOAP-ENV:Body>
    <p:makeFriends
       xmlns:p="http://cyclic.test"
       xmlns:xsd="http://www.w3.org/2001/XMLSchema"
       xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
       SOAP-ENV:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
      <p:Person>
        <name xsi:type="xsd:string">John</name>
        <friend xsi:nil="true"/>
      </p:Person>
      <p:Person>
        <name xsi:type="xsd:string">Jason</name>
        <friend xsi:nil="true"/>
      </p:Person>
    </p:makeFriends>
  </SOAP-ENV:Body>
</SOAP-ENV:Envelope>
__XML

    my $answer = <<__ANSWER;
<soapenv:Envelope
  xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/"
  xmlns:xsd="http://www.w3.org/2001/XMLSchema"
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
$prepared_answer
</soapenv:Envelope>
__ANSWER

    HTTP::Response->new(200, 'OK', ['Content-Type' => 'text/xml']
     , $answer
     );
}

my $call = $wsdl->compileClient('makeFriend'
  , rpcout => \&make_friend_request 
  , transport_hook => \&fake_server
  );
isa_ok($call, 'CODE', 'compiled client');

### websphere example output

$prepared_answer = $websphere_answer;
my ($ret, $trace) = $call->(['John', 'Jason']);
ok(!defined $trace->{error}, 'no error');
#warn "WEBSPHERE: ",Dumper $ret;

my $jason = { name => 'Jason' };
my $john  = { name => 'John', friend => $jason };
$jason->{friend} = $john;

cmp_deeply($ret, { makeFriendResponse => $john });

### dotnet example output

$prepared_answer = $dotnet_answer;
($ret, $trace) = $call->(['John', 'Jason']);
#warn "DOTNET", Dumper $ret;

cmp_deeply($ret, [ $john, $jason, { makeFriendsResponse => $john } ]);
