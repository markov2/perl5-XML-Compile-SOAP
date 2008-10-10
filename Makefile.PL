use ExtUtils::MakeMaker;

use 5.008;

warn <<_WARN;

*
**************************** WARNING *****************************
* The SOAP-RPC implementation is currently broken. If you need it,
* do use XML::Compile v0.94 with XML::Compile::SOAP v0.76.
* A major rewrite of the code is in progress, which will hopefully
* fix that soap variant.  Document-style is OK.
********************^^^^^*** WARNING ***^^^^^*********************
*

_WARN
sleep 10;

WriteMakefile
 ( NAME	 	=> 'XML::Compile::SOAP'
 , VERSION	=> '0.78'
 , PREREQ_PM    =>
   { XML::Compile    => 0.96
   , XML::Compile::Tester => 0.04
   , Log::Report     => 0.17
   , LWP             => 5.803
   , Time::HiRes     => 0

   , Test::More      => 0.54
   , Test::Deep      => 0.095
   , Test::Pod       => '1.00'
   }
 , AUTHOR       => 'Mark Overmeer'
 , ABSTRACT     => 'XML over SOAP, client side'
 , LICENSE      => 'perl'
 );

### used by oodist during production of distribution
sub MY::postamble { <<'__POSTAMBLE' }

EXTENDS		= ../XMLCompile:../XMLDaemon:../XMLTester

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
