use ExtUtils::MakeMaker;

use 5.008;

WriteMakefile
 ( NAME	 	=> 'XML::Compile::SOAP'
 , VERSION	=> '2.04'
 , PREREQ_PM    =>
   { XML::Compile         => 1.01
   , XML::Compile::Tester => 0.05
   , XML::Compile::Cache  => 0.91
   , Log::Report     => 0.17
   , LWP             => 5.825
   , Time::HiRes     => 0

   , Test::More      => 0.54
   , Test::Deep      => 0.095
   , Test::Pod       => '1.00'
   }
 , AUTHOR       => 'Mark Overmeer'
 , ABSTRACT     => 'SOAP and WSDL, client side'
 , LICENSE      => 'perl'
 );

### used by oodist during production of distribution
sub MY::postamble { <<'__POSTAMBLE' }

EXTENDS		= ../XMLCompile:../XMLDaemon:../XMLTester:../XMLCache:../XMLSOAP12

# for DIST
RAWDIR          = ../public_html/xml-compile-soap/raw
DISTDIR         = ../public_html/xml-compile-soap/source
LICENSE         = artistic
SKIP_LINKS	= XML::LibXML

# for POD
FIRST_YEAR      = 2007
EMAIL           = perl@overmeer.net
WEBSITE         = http://perl.overmeer.net/xml-compile/
PODTAIL		= ../XML-shared-podtail
__POSTAMBLE
