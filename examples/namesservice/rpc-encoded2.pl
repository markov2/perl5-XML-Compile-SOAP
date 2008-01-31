#!/usr/bin/perl
# Example of RPC-encoded style SOAP, where we ignore the fact that
# there is a schema file.  DO NOT USE THIS, UNLESS YOU HAVE NO CHOICE!
# Same as rpc-encoded.pl, but simplified and without explanation.

# Thanks to Thomas Bayer, for providing this service
#    See http://www.thomas-bayer.com/names-service/

# Author: Mark Overmeer, 27 Nov 2007
# Using:  XML::Compile 0.60
#         XML::Compile::SOAP 0.64
# Copyright by the Author, under the terms of Perl itself.
# Feel invited to contribute your examples!

use warnings;
use strict;

# To make Perl find the modules without the package being installed.
use lib '../../lib'
      , '../../../XMLCompile/lib'   # my home test environment
      , '../../../LogReport/lib';

use XML::Compile::SOAP11::Client;
use XML::Compile::Transport::SOAPHTTP;
use XML::Compile::Util   qw/pack_type/;

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
# Get the Client and Schema definitions
#

my $client = XML::Compile::SOAP11::Client->new;

my $myns    = 'http://namesservice.thomas_bayer.com/';
my $address = 'http://www.thomas-bayer.com:80/names-service/soap';

#
# In RPC-encoded, all messages share the same definition.
#

my $http   = XML::Compile::Transport::SOAPHTTP
               ->new(address => $address)
               ->compileClient;

my $output = $client->compileMessage(SENDER   => style => 'rpc-encoded');
my $input  = $client->compileMessage(RECEIVER => style => 'rpc-encoded');

#
# Pick one of these tests
#

my $answer = '';
while(lc $answer ne 'q')
{
    print <<__SELECTOR;

    Which call do you like to see:
      1) getCountries
      2) getNameInfo
      3) getNamesInCountry
      Q) quit demo

__SELECTOR

    $answer = $term->readline("Pick one of above [1/2/3/Q] ");
    chomp $answer;

       if($answer eq '1') { get_countries() }
    elsif($answer eq '2') { get_name_info()  }
    elsif($answer eq '3') { get_names_in_country() }
    elsif(lc $answer ne 'q' && length $answer)
    {   print "Illegal choice\n";
    }
}

exit 0;

sub create_call($$)
{   my ($name, $handler) = @_;
    $client->compileClient
     ( name   => $name, rpcout => $handler
     , encode => $output, transport => $http, decode => $input
     );
}

#
# Get Countries
#

sub request_get_countries($$$)
{   my ($soap, $doc, $data) = @_;
    $soap->encAddNamespace(ns => $myns);
    my $top = $soap->struct(pack_type($myns, 'getCountries'));
    $top;
}

sub get_countries()
{   
    my $getCountries = create_call getCountries => \&request_countries;
    my $answer = $getCountries->();

    if(my $fault_raw = $answer->{Fault})
    {   my $fault_nice = $answer->{$fault_raw->{_NAME}};
        die "Cannot get list of countries: $fault_nice->{reason}\n";
    }

    my $countries = $answer->{getCountriesResponse}{country};

    print "getCountries() lists ".scalar(@$countries)." countries:\n";
    foreach my $country (sort @$countries)
    {   print "   $country\n";
    }
}

#
# Get Name Info
#

sub request_name_info(@)
{   my ($soap, $doc, $name) = @_;
    $soap->encAddNamespace(ns => $myns);
    my $ni  = $soap->element('string', name => $name);
    $soap->struct(pack_type($myns, 'getNameInfo'), $ni);
}

sub get_name_info()
{
    my $getNameInfo = create_call getNameInfo => \&request_name_info;

    # ask the user for a name
    my $name   = $term->readline("Personal name for info: ");
    chomp $name;
    length $name or return;

    my $answer = $getNameInfo->($name);

    die "Lookup for '$name' failed: $answer->{Fault}{faultstring}\n"
        if $answer->{Fault};

    my $nameinfo  = $answer->{getNameInfoResponse}{nameinfo};

    # answer is untyped, so we have to interpret (and validate) ourselves
    my $is_male   = $nameinfo->{male}   =~ m/^(?:1|true)$/ ? 'yes' : 'no';
    my $is_female = $nameinfo->{female} =~ m/^(?:1|true)$/ ? 'yes' : 'no';

    print "The name '$nameinfo->{name}' is\n";
    print "    male: $is_male\n";
    print "  female: $is_female\n";
    print "  gender: $nameinfo->{gender}\n";
    print "and used in countries:\n";

    $format_list = join ', ', @{$nameinfo->{countries}{country}};
    write;
}

#
# Get Names In Country
#

sub request_names_in_country($$$)
{   my ($soap, $doc, $country) = @_;
    $soap->encAddNamespace(ns => $myns);
    my $c  = $soap->element(string => country => $country);
    $soap->struct(pack_type($myns, 'getNamesInCountry'), $c);
}

sub get_names_in_country()
{   my $getCountries      = create_call getCountries => \&request_countries;
    my $getNamesInCountry = create_call getNamesInCountry =>
        \&request_names_in_country;

    my $answer1 = $getCountries->();
    die "Cannot get countries: $answer1->{Fault}{faultstring}\n"
        if $answer1->{Fault};

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
    my $answer2 = $getNamesInCountry->($name);
    die "Cannot get names in country: $answer2->{Fault}{faultstring}\n"
        if $answer2->{Fault};

    my $names    = $answer2->{getNamesInCountryResponse}{name};
    $names
        or die "No data available for country `$name'\n";

    $format_list = join ', ', @$names;
    write;
}

