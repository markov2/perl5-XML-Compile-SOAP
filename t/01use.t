#!/usr/bin/perl

use warnings;
use strict;

use lib 'lib', 't';
use Test::More tests => 13;
use TestTools;

# The versions of the following packages are reported to help understanding
# the environment in which the tests are run.  This is certainly not a
# full list of all installed modules.
my @show_versions =
 qw/Test::More
    Test::Deep
    XML::Compile
    XML::LibXML
    Math::BigInt
   /;

foreach my $package (@show_versions)
{   eval "require $package";

    my $report
      = !$@                    ? "version ". ($package->VERSION || 'unknown')
      : $@ =~ m/^Can't locate/ ? "not installed"
      : "reports error";

    warn "$package $report\n";
}

warn "libxml2 ".XML::LibXML::LIBXML_DOTTED_VERSION()."\n";

require_ok('XML::Compile::SOAP');
require_ok('XML::Compile::SOAP11');
require_ok('XML::Compile::SOAP11::Client');
require_ok('XML::Compile::SOAP11::Server');
require_ok('XML::Compile::SOAP12');
require_ok('XML::Compile::SOAP12::Client');
require_ok('XML::Compile::SOAP12::Server');
require_ok('XML::Compile::SOAP::Client');
require_ok('XML::Compile::SOAP::HTTPClient');
require_ok('XML::Compile::SOAP::Server');
require_ok('XML::Compile::SOAP::Tester');
require_ok('XML::Compile::WSDL11');
require_ok('XML::Compile::WSDL11::Operation');
