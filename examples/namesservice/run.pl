#!/usr/bin/perl
# Example of Document SOAP.
# Thanks to Thomas Bayer, for providing this service
#    See http://www.thomas-bayer.com/names-service/

# Author: Mark Overmeer, 6 Nov 2007
# Using:  XML::Compile 0.58
#         XML::Compile::SOAP 0.60
# Copyright by the Author, under the terms of Perl itself.
# Feel invited to contribute your examples!

# Of course, all Perl programs start like this!
use warnings;
use strict;

# To make Perl find the modules without the package being installed.
use lib '../../lib';
use lib '../../../XMLCompile/lib';  # my home test environment

# Configuration
my $debug = 1;

# All the other XML modules should be automatically included.
use XML::Compile::WSDL11;
use XML::Compile::Transport::SOAPHTTP;

# Other usefile modules
use Data::Dumper;          # Data::Dumper is your friend.
$Data::Dumper::Indent = 1;

use List::Util   qw/first/;

my $format_list;
format =
   ^<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<~~
   $format_list
.

# Forward declarations
sub get_countries();
sub get_name_info();
sub get_names_in_country();

#### MAIN

use Term::ReadLine;
my $term = Term::ReadLine->new('namesservice');

#
# Get the WSDL and Schema definitions
#

my $wsdl = XML::Compile::WSDL11->new('namesservice.wsdl');
$wsdl->schemas->importDefinitions('namesservice.xsd');

#
# Pick one of these tests
#

  get_countries();
# get_name_info();
# get_names_in_country();

exit 0;

#
# First example
# This one is explained in most detail
#

sub get_countries()
{
    # first compile a handler which you can call as often as you want.
    # If you do not know the name of the portType, then just put anything
    # here: the error message will list your options.

    my $getCountries
        = $wsdl->prepareClient('getCountries');

    # Actually, above is an abbreviation of
    #   = $wsdl->prepareClient(operation => 'getCountries');
    #   = $wsdl->find(operation => 'getCountries')->prepareClient;
    # You may need to go into more the extended syntaxes if you have multiple
    # services, ports, bindings, or such in you WSDL file.  Is so, the run-time
    # will ask you to do so, offering alternatives.

    #
    # Call the produced method to list the supported countries
    #

    # According to the WSDL, the message has one body part, named 'parameters'
    # When there can be confusion, you have to be more specific at the call
    # of the method.  When multiple header+body parts exist, use should group
    # your data on part name.

    my ($answer, $trace)
    #   = $getCountries->(Body => {parameters => {}});
    #   = $getCountries->(parameters => {});
        = $getCountries->();    # is code-ref, so still needs ->()

    # In above examples, the first explicitly addresses the 'parameters'
    # message part in the Body of the SOAP message.  There is also a Header.
    # The second version can be used when all header and body parts have
    # difference names.  The last version can be used if there is only one
    # body part defined.

    # If you do not need the trace, simply say:
    # my $answer = $getCountries->();

    #
    # Some ways of debugging
    #

    if($debug)
    {
        printf "Call initiated at: $trace->{date}\n";
        print  "SOAP call timing:\n";
        printf "      encoding: %7.2f ms\n", $trace->{encode_elapse}    *1000;
        printf "     transport: %7.2f ms\n", $trace->{transport_elapse} *1000;
        printf "      decoding: %7.2f ms\n", $trace->{decode_elapse}    *1000;
        printf "    total time: %7.2f ms ",  $trace->{elapse}           *1000;
        printf "= %.3f seconds\n\n", $trace->{elapse};

        print  "transport time components:\n";
        printf "     stringify: %7.2f ms\n", $trace->{stringify_elapse} *1000;
        printf "    connection: %7.2f ms\n", $trace->{connect_elapse}   *1000;
        printf "       parsing: %7.2f ms\n", $trace->{parse_elapse}     *1000;

        if(my $request = $trace->{http_request})   # a HTTP::Request object
        {   my $req = $request->as_string;
            $req =~ s/^/  /gm;
            print "\nRequest:\n", $req;
        }

        if(my $response = $trace->{http_response}) # a HTTP::Response object
        {   my $resp = $response->as_string;
            $resp =~ s/^/  /gm;
            print "\nResponse:\n", $resp;
        }
    }

    # And now?  What do I get back?  I love Data::Dumper.
    # warn Dumper $answer;

    #
    # Handling faults
    #

    if(my $fault_raw = $answer->{Fault})
    {   my $fault_nice = $answer->{$fault_raw->{_NAME}};

        # fault_raw points to the fault structure, which contains fields
        # faultcode, faultstring, and unprocessed "detail" information.
        # fault_nice points to the same information, but translated to
        # something what is equivalent in SOAP1.1 and SOAP1.2.

        die "Cannot get list of countries: $fault_nice->{reason}\n";

        # Have a look at Log::Report for cleaner (translatable) die:
        #   error __x"Cannot get list of countries: {reason}",
        #      reason => $fault_nice->{reason};
    }

    #
    # Collecting the country names
    #

    # According to the WSDL, the returned getCountriesResponse message
    # has one part, named 'parameters'.  The contents returned is a
    # getCountriesResponse element of type complexType getCountriesResponse,
    # both defined in the xsd file.
    # The only data field is named 'country', and has a maxCount > 1 so
    # will be translated by XML::Compile into an ARRAY.
    # The received message is validated, so we do not need to check the
    # structure ourselves again.

    my $countries = $answer->{parameters}{country};

    print "getCountries() lists ".scalar(@$countries)." countries:\n";
    foreach my $country (sort @$countries)
    {   print "   $country\n";
    }
}

#
# Second example
#

sub get_name_info()
{
    # ask the user for a name
    my $name = $term->readline("Personal name for info (empty to stop) ");
    chomp $name;

    length $name or return;  # quit

    #
    # Ask information about the specified name
    # (we are not using the country list, received before)
    #

    my $getNameInfo = $wsdl->prepareClient('getNameInfo');

    my ($answer, $trace2) = $getNameInfo->(name => $name);
    #print Dumper $answer, $trace2;

    die "Lookup for '$name' failed: $answer->{Fault}{faultstring}\n"
        if $answer->{Fault};

    my $nameinfo = $answer->{parameters}{nameinfo};
    print "The name '$nameinfo->{name}' is\n";
    print "    male: ", ($nameinfo->{male}   ? 'yes' : 'no'), "\n";
    print "  female: ", ($nameinfo->{female} ? 'yes' : 'no'), "\n";
    print "  gender: $nameinfo->{gender}\n";
    print "and used in countries:\n";

    $format_list = join ', ', @{$nameinfo->{countries}{country}};
    write;
}

#
# Third example
#

sub get_names_in_country()
{   # usually in the top of your script: reusable
    my $getCountries      = $wsdl->prepareClient('getCountries');
    my $getNamesInCountry = $wsdl->prepareClient('getNamesInCountry');

    my $answer1 = $getCountries->();
    die "Cannot get countries: $answer1->{Fault}{faultstring}\n"
        if $answer1->{Fault};

    my $countries = $answer1->{parameters}{country};

    my $country;
    while(1)
    {   $country = $term->readline("Most common names in which country? ");
        chomp $country;
        $country eq '' or last;
        print "  please specify a country name.\n";
    }

    # find the name case-insensitive in the list of available countries
    my $name = first { /^\Q$country\E$/i } @$countries;

    unless($name)
    {   $name = 'other countries';
        print "Cannot find name '$country', defaulting to '$name'\n";
        print "Available countries are:\n";
        $format_list = join ', ', @$countries;
        write;
    }

    print "Most common names in $name:\n";
    my $answer2 = $getNamesInCountry->(country => $name);
    die "Cannot get names in country: $answer2->{Fault}{faultstring}\n"
        if $answer2->{Fault};

    my $names    = $answer2->{parameters}{name};
    $names
        or die "No data available for country `$name'\n";

    $format_list = join ', ', @$names;
    write;
}

