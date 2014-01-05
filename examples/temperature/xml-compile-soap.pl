#!/usr/bin/env perl
use warnings;
use strict;

use XML::Compile::WSDL11;
use XML::Compile::SOAP11;
use XML::Compile::SOAP12;
use XML::Compile::Transport::SOAPHTTP;

# XML::Compile does not like dynamic things.  WSDL collected with
#    wget http://www.webservicex.net/ConvertTemperature.asmx?WSDL
my $wsdlfn = 'convert.wsdl';
my $wsdl = XML::Compile::WSDL11->new($wsdlfn);

my $request =
  { Temperature => 12
  , FromUnit    => 'degreeCelsius'
  , ToUnit      => 'degreeCelsius'
  };

my ($answer, $trace);

if(0)
{   ### eiter compile explicitly
    my $convert = $wsdl->compileClient
     ( 'ConvertTemp'
     , port => 'ConvertTemperatureSoap'
     );

    ($answer, $trace) = $convert->($request);
}
else
{   ### or compile/use implictly

#   $wsdl->compileCalls(port => 'ConvertTemperatureSoap');
    $wsdl->compileCalls;
    ($answer, $trace) = $wsdl->call(ConvertTemp => $request);
}


### in either case, you can call the operations many times, with
#   different $request

use Data::Dumper;
warn Dumper $answer;

# $trace->printTimings;
# $trace->printRequest(pretty_print => 1);
# $trace->printResponse(pretty_print => 1);
