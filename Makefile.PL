use ExtUtils::MakeMaker;

use 5.8.0;

WriteMakefile
 ( NAME	 	=> 'XML::Compile::SOAP'
 , VERSION	=> 0.55
 , PREREQ_PM    =>
   { XML::Compile    => 0.55
   , Log::Report     => 0.09
   , LWP             => 5.803
   , Time::HiRes     => 0

   , Test::More      => 0.54
   , Test::Deep      => 0.095
   , Test::Pod       => 1.00
   }
 , AUTHOR       => 'Mark Overmeer'
 , ABSTRACT     => 'XML over SOAP'
 , LICENSE      => 'perl'
 );

### used by oodist during production of distribution
sub MY::postamble { <<'__POSTAMBLE' }

# for DIST
RAWDIR          = ../public_html/xml-compile-soap/raw
DISTDIR         = ../public_html/xml-compile-soap/source
LICENSE         = artistic

# for POD
FIRST_YEAR      = 2007
EMAIL           = perl@overmeer.net
WEBSITE         = http://perl.overmeer.net/xml-compile/
__POSTAMBLE
