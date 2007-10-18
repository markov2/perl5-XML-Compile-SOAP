#!/usr/bin/perl
# Test SOAP mustUnderstand

use warnings;
use strict;

use lib 'lib','t';
use TestTools;
use Test::Deep   qw/cmp_deeply/;

use Data::Dumper;
$Data::Dumper::Indent = 1;

use XML::Compile::SOAP11::Client;

use Test::More tests => 19;
use XML::LibXML;

# elementFormDefault="qualified">
my $schema = <<__HELPERS;
<schema targetNamespace="$TestNS"
  xmlns="$SchemaNS">

  <element name="good" type="int"/>

</schema>
__HELPERS

#
# Create and interpret a message
#

my $soap = XML::Compile::SOAP11::Client->new;
$soap->schemas->importDefinitions($schema);

my @msg_struct = 
  ( header => [ count => "{$TestNS}good"  ]
  , mustUnderstand => 'count'
  );

my $sender   = $soap->compileMessage(SENDER => @msg_struct);
is(ref $sender, 'CODE', 'compiled a sender');

my $receiver = $soap->compileMessage(RECEIVER => @msg_struct);
is(ref $receiver, 'CODE', 'compiled a receiver');

#
# First, the data is present
#

my $msg1_soap = <<__MSG1;
<SOAP-ENV:Envelope xmlns:x0="$TestNS"
   xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/">
  <SOAP-ENV:Header>
    <x0:good mustUnderstand="1">
      3
    </x0:good>
  </SOAP-ENV:Header>
  <SOAP-ENV:Body/>
</SOAP-ENV:Envelope>
__MSG1

# sender

my $xml1a = $sender->(count => 3);
isa_ok($xml1a, 'XML::LibXML::Node', 'produced XML');
compare_xml($xml1a, $msg1_soap);

my $xml1b = $sender->( {count => 3} );
isa_ok($xml1b, 'XML::LibXML::Node', 'produced XML');
compare_xml($xml1b, $msg1_soap);

# receiver

my $hash1 = $receiver->($msg1_soap);
is(ref $hash1, 'HASH', 'produced HASH');

cmp_deeply($hash1, {count => 3}, "server parsed input");

###
### Now, the receiver does not understand the count header
###

my $receiver2 = $soap->compileMessage('RECEIVER');
is(ref $receiver2, 'CODE', 'compiled unknowing receiver');

my $hash2 = $receiver2->($msg1_soap);
ok(defined $hash2, 'received2 works');
is(ref $hash2, 'HASH', 'produced HASH');

ok(defined $hash2->{Fault});
ok(defined $hash2->{Fault}{faultcode});
ok(defined $hash2->{Fault}{faultstring});
ok(defined $hash2->{header});

#
# any sender must accept faults
#

my $msg2_soap = <<__FAULT;
<SOAP-ENV:Envelope xmlns:x0="http://test-types"
   xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/">
   <SOAP-ENV:Body>
     <SOAP-ENV:Fault>
       <SOAP-ENV:faultcode>SOAP-ENV:MustUnderstand</SOAP-ENV:faultcode>
       <SOAP-ENV:faultstring>
          SOAP mustUnderstand {http://test-types}good
       </SOAP-ENV:faultstring>
       <SOAP-ENV:detail/>
     </SOAP-ENV:Fault>
   </SOAP-ENV:Body>
</SOAP-ENV:Envelope>
__FAULT

# remove fault decoding extras
delete $hash2->{header};
delete $hash2->{Fault}{_NAME};

my $xml2 = $sender->($hash2);
isa_ok($xml2, 'XML::LibXML::Node', 'produced XML fault');
compare_xml($xml2, $msg2_soap, 'correct structure');

#
# and any receiver can decode them
#

# See XML::Compile README.todo: initial prefix problem: we need to
# stringify and reparse the XML structure.

my $hash3 = $receiver->($xml2->toString);
ok(defined $hash3, 'received decodes fault');
is(ref $hash3, 'HASH');
