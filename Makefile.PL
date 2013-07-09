use ExtUtils::MakeMaker;

use 5.008;

my $version = '2.37';

WriteMakefile
 ( NAME	 	=> 'XML::Compile::SOAP'
 , VERSION	=> $version
 , PREREQ_PM    =>
   { XML::Compile         => 1.35
   , XML::Compile::Tester => 0.90
   , XML::Compile::Cache  => 0.993
   , Log::Report          => 0.90

   , LWP             => 5.816
   , Time::HiRes     => 0
   , File::Slurp     => 0

   , Test::More      => 0.54
   }
 , AUTHOR       => 'Mark Overmeer'
 , ABSTRACT     => 'SOAP and WSDL, client side'
 , LICENSE      => 'perl'
 );

### used by oodist during production of distribution
sub MY::postamble { <<'__POSTAMBLE' }

EXTENDS		= ../XMLCompile:../XMLDaemon:../XMLTester:../XMLCache:../XMLSOAP12:../SOAPAnyEvent:../XMLWSA

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
