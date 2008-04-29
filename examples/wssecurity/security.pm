# This is an exerpt of the script you need you use username/password
# login with the WS-Security specification.
#
# The security schema uses <any> a lot, which makes the use of XML::Compile
# more of a hassle than usually: each <any> component needs to be prepared
# with its own reader or writer.
#
# In some future, WS-Security might be supported by a module.
# Also in a future, the "::Document" creation should disappear.
#
# Contributed by Alan Wind
# Modified by Mark Overmeer, 2008-04-16

use XML::Compile::Util 'pack_type';

use constant MY_PASSWORD => 'replace_with_your_password';
use constant MY_USERNAME => 'replace_with_your_username';

use constant WSS_200401          =>
   'http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss';
use constant WSS_SECEXT_200401   => WSS_200401 . '-wssecurity-secext-1.0.xsd';
use constant WSS_USERNAME_200401 => WSS_200401 . '-username-token-profile-1.0';

# Create the password translator

my $password_element  = pack_type WSS_SECEXT_200401, 'Password';
my $password_writer   = $wsdl->schemas->compile(WRITER => $password_element);

my $password_document = XML::LibXML::Document->new('1.0', 'UTF-8');
my $password_value    = $password_writer->($password_document,
   { _    => MY_PASSWORD
   , Type => WSS_USERNAME_200401 . '#PasswordText'
   }
);

# Map the first any of SecurityHeaderType to UsernameToken, and set
# the password which is any using the above.

my $UsernameToken_element  = pack_type WSS_SECEXT_200401, 'UsernameToken';
my $UsernameToken_writer   =
  $wsdl->schemas->compile(WRITER => $UsernameToken_element);
my $UsernameToken_document = XML::LibXML::Document->new('1.0', 'UTF-8');

my $UsernameToken_value    = $UsernameToken_writer->($UsernameToken_document,
    { Username => { _ => MY_USERNAME }
    , $password_element => $password_value
    }
);

my ($result, $trace) = $call->(
    header => { $UsernameToken_element => $UsernameToken_value },
    # rest of arguments
);    

