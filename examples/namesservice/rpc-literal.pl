#!/usr/bin/perl
# Example of RPC-literal style SOAP, where the WSDL does not
# tell the structure of the messages: there's only one.
# Thanks to Thomas Bayer, for providing this service
#    See http://www.thomas-bayer.com/names-service/

# Author: Mark Overmeer, 26 Nov 2007
# Using:  XML::Compile 0.60
#         XML::Compile::SOAP 0.64
# Copyright by the Author, under the terms of Perl itself.
# Feel invited to contribute your examples!

# Of course, all Perl programs start like this!
use warnings;
use strict;

# To make Perl find the modules without the package being installed.
use lib '../../lib';
use lib '../../../XMLCompile/lib'   # my home test environment
      , '../../../LogReport/lib';

use XML::Compile::SOAP11::Client;
use XML::Compile::Transport::SOAPHTTP;
use XML::Compile::Util   qw/pack_type/;

# Other useful modules
use Data::Dumper;          # Data::Dumper is your friend.
$Data::Dumper::Indent = 1;

use List::Util   qw/first/;

my $format_list;
format =
   ^<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<~~
   $format_list
.

# Forward declarations
sub get_countries($);
sub get_name_info();
sub get_names_in_country();

#### MAIN

use Term::ReadLine;
my $term = Term::ReadLine->new('namesservice');

#
# Get the Client and Schema definitions
#

my $client = XML::Compile::SOAP11::Client->new;
$client->schemas->importDefinitions('namesservice.xsd');

my $myns    = 'http://namesservice.thomas_bayer.com/';
my $address = 'http://www.thomas-bayer.com:80/names-service/soap';

#
# In RPC-literal, all messages share the same definition.
#

my $http   = XML::Compile::Transport::SOAPHTTP
               ->new(address => $address)
               ->compileClient;

my $output = $client->compileMessage(SENDER   => style => 'rpc-literal');
my $input  = $client->compileMessage(RECEIVER => style => 'rpc-literal');

#
# Pick one of these tests
#

my $answer = '';
while(lc $answer ne 'q')
{
    print <<__SELECTOR;

    Which call do you like to see:
      1) getCountries
      2) getCountries with trace output
      3) getNameInfo
      4) getNamesInCountry
      Q) quit demo

__SELECTOR

    $answer = $term->readline("Pick one of above [1/2/3/4/Q] ");
    chomp $answer;

       if($answer eq '1') { get_countries(0) }
    elsif($answer eq '2') { get_countries(1) }
    elsif($answer eq '3') { get_name_info()  }
    elsif($answer eq '4') { get_names_in_country() }
    elsif(lc $answer ne 'q' && length $answer)
    {   print "Illegal choice\n";
    }
}

exit 0;

sub create_get_countries
{
    my $getCountries = $client->compileClient
     ( name      => 'getCountries'

       # shared information
     , encode    => $output
     , transport => $http
     , decode    => $input

       # the RPC intelligence wrapper
     , rpcout    => pack_type($myns, 'getCountries')
     , rpcin     => pack_type($myns, 'getCountriesResponse')
     );

    $getCountries;    # return the code reference
}

sub get_countries($)
{   my $show_trace = shift;

    # first compile a handler which you can call as often as you want.

    my $getCountries = create_get_countries;

    # the calling features are a little different, because the message
    # content has no clear name.  The message requires an empty sequence,
    # so we need to specify the empty HASH: {}

    my ($answer, $trace) = $getCountries->({});

    # If you do not need the trace, simply say:
    # my $answer = $getCountries->({});

    #
    # Some ways of debugging
    #

    if($show_trace)
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
        die "Cannot get list of countries: $fault_nice->{reason}\n";
    }

    #
    # Collecting the country names
    #

    my $countries = $answer->{getCountriesResponse}{country};

    print "getCountries() lists ".scalar(@$countries)." countries:\n";
    foreach my $country (sort @$countries)
    {   print "   $country\n";
    }
}

#
# Second example
#

sub create_get_name_info()
{
    $client->compileClient
      ( encode => $output, transport => $http, decode => $input
      , rpcout => pack_type($myns, 'getNameInfo')

# the default name is the local name of rpcout
#     , name => 'getNameInfo'

# the default is rpcout.'Response'
#     , rpcin  => pack_type($myns, 'getNameInfoResponse')
      );
}

# As you see, we start repeating ourselves a little.  It might
# therefore, be convinient to define a "macro" like wrapper:
#   sub newRPC($@)
#   {   my $local = shift;
#       $client->compileClient
#         ( encode => $output, transport => $http, decode => $input
#         , rpcout => pack_type($myns, $local)
#         , @_     # additional options
#         );
#   }
#   my $get_name_info = newRpc('getNameInfo');
#
# or
#   my $newRpc = sub
#     { my $local = shift;
#       $client->compileClient
#         ( encode => $output, transport => $http, decode => $input
#         , rpcout => pack_type($myns, $local)
#         , @_     # additional options
#         );
#     };
#   my $get_name_info = $newRpc->('getNameInfo');
#
# The $output, $http, and $input are needed only once, so this whole
# creation process could be hidden in a single sub-routine.

sub get_name_info()
{
    my $getNameInfo = create_get_name_info;

    #
    ## From here on, just like the WSDL version
    #

    # ask the user for a name
    my $name = $term->readline("Personal name for info: ");
    chomp $name;
    length $name or return;

    my ($answer, $trace2) = $getNameInfo->( {name => $name} );
    #print Dumper $answer, $trace2;

    die "Lookup for '$name' failed: $answer->{Fault}{faultstring}\n"
        if $answer->{Fault};

    my $nameinfo = $answer->{getNameInfoResponse}{nameinfo};
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
    my $getCountries      = create_get_countries;

    # creating calls is quite simple, so let's in-line this time.
    my $getNamesInCountry = $client->compileClient
      ( encode => $output, transport => $http, decode => $input
      , rpcout => pack_type($myns, 'getNamesInCountry')
      );

    #
    ## From here on the same as the WSDL version
    #

    my $answer1 = $getCountries->( {} );
    die "Cannot get countries: $answer1->{Fault}{faultstring}\n"
        if $answer1->{Fault};

    #print Dumper $answer1;

    my $countries = $answer1->{getCountriesResponse}{country};

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
    my $answer2 = $getNamesInCountry->( {country => $name} );
    die "Cannot get names in country: $answer2->{Fault}{faultstring}\n"
        if $answer2->{Fault};

    #print Dumper $answer2;

    my $names    = $answer2->{getNamesInCountryResponse}{name};
    $names
        or die "No data available for country `$name'\n";

    $format_list = join ', ', @$names;
    write;
}

