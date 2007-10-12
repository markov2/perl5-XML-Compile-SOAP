use warnings;
use strict;

package XML::Compile::SOAP::Tester;

use XML::Compile::SOAP::Client ();

use Log::Report 'xml-compile-soap', syntax => 'SHORT';
use Time::HiRes   qw/time/;

=chapter NAME
XML::Compile::SOAP::Tester - test SOAP without daemon

=chapter SYNOPSIS
 # Do this BEFORE the client SOAP handlers are compiled!
 use XML::Compile::SOAP::Tester ();
 my $tester = XML::Compile::SOAP::Tester->new(@options);

 my $action = pack_type $my_ns, 'GetStockPrice';
 sub get_stock_price(@) {...}

 #
 # with WSDL
 #

 use XML::Compile::WSDL11 ();
 my $wsdl    = XML::Compile::WSDL11->new('my_wsdl.xml');
 my $call    = $wsdl->prepareClient($action);
 $tester->fromWSDL($wsdl);
 $tester->addCallback($action, \&get_stock_price);

 my $answer  = $call->($query);

 #
 # without WSDL
 #

 use XML::Compile::Util   'pack_type';
 use XML::Compile::SOAP11::Client ();
 use XML::Compile::SOAP11::Server ();

 my $client = XML::Compile::SOAP11::Client->new;
 my $call   = $client->compileRequest(...);

 my $server = XML::Compile::SOAP11::Server->new;
 my $answer = $server->compileAnswer(  ... \&get_stock_price);
 $tester->actionCallback($my_action, $answer, $server);

 my $answer = $call->($query);

=chapter DESCRIPTION
Once you have instantiated this object, all compiled client calls
will get re-routed to methods within the object.  This is useful
for debugging and regression tests.

If you install the XML-Compile-SOAP-Server distribution, you will
have an M<XML::Compile::SOAP::HTTPTester> implementation, which
simulates a remote server in a much more realistic way.

=chapter METHODS

=c_method new OPTIONS

=option  callbacks HASH | ARRAY
=default callbacks {}
The HASH contains pairs of action-uri to code reference.  Each pair
is used to call M<actionCallback()>.  The ARRAY contains two elements:
a string C<SOAP11>, C<SOAP12>, or M<XML::Compile::SOAP> object as
first, and the HASH as second.  To be precise: when only a HASH is
passed, it is the same as an ARRAY with C<ANY> and that HASH.
=cut

sub new(@)
{   my $class = shift;
    (bless {}, $class)->init( {@_} );
}

sub init()
{   my ($self, $args) = @_;

    # just like XML::Compile::SOAP::Server is doing it
    if(my $cb = delete $args->{callbacks})
    {   my ($version, $data) = ref $cb eq 'ARRAY' ? @$cb : (ANY => $cb);
        while(my ($action, $code) = each %$data)
        {   $self->actionCallback($action, $code, $version);
        }
    }

    XML::Compile::SOAP::Client->fakeServer($self);
}

#------------------------------------------------

=section Attributes

=method actionCallback ACTION, CODE, ['SOAP11'|'SOAP12'|SOAP|'ANY']
Change the callback of an ACTION to the CODE reference.  By default,
all known (ANY) soap versions will be affected.  Callback changes to
undefined actions are ignored.
=cut

# code equivalent to method in XML::Compile::SOAP::Server
sub actionCallback($$;$)
{   my ($self, $action, $code, $soap) = @_;
    my $version = !defined $soap ? undef : ref $soap ? $soap->version : $soap;
    undef $version if $version eq 'ANY';
    foreach my $v ('SOAP11', 'SOAP12')
    {   next if defined $version && $version ne $v;
        $self->{actions}{$v}{$action}{callback} = $code
           if exists $self->{actions}{$v}{$action};
    }
}

#------------------------------------------------

=section Run the server

=method request OPTIONS
Fake a request to a remote server.  Which information is passed as
the OPTIONS depends partially on the protocol.
=cut

sub request(@)
{   my ($self,%trace) = @_;
    my $action  = $trace{action};
    my $version = $trace{soap_version};
    my $cb      = $self->{actions}{$version}{$action};

    unless($cb)
    {   notice __x"cannot find action {action} for {soap}"
          , action => $action, soap => $version;
        return (undef, \%trace);
    }

    my $answer  = $cb->($trace{message});
    ($answer, \%trace);
}

1;
