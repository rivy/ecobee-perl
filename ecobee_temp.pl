#! /usr/bin/perl

use strict;
use warnings;
use lib '/your_path_here/lib';

require Ecobee::API;
require Ecobee::Tools;

our $data_directory = '/your_path_here/data';

# Request from ecobee servers, thermostat data
sub Get_Thermostat_Data
{
  my ($p_thermostat_id, $p_hash_ref) = @_;

  # Request thermostat data
  {
    my %results;
    my $cmd = 'thermostat';
    my %prop = (selection => {
                 selectionType => 'thermostats',
                 selectionMatch => $p_thermostat_id,
                 includeRuntime => 'true',
               }
              );

    API::Get_Request($cmd, \%prop, \%results);

    my $thermostat_ref = \@{$results{thermostatList}};
    my $runtime_ref    = \%{$$thermostat_ref[0]{runtime}};

    # Runtime
    $$p_hash_ref{'actualTemperature'} = $$runtime_ref{actualTemperature}/10;
    $$p_hash_ref{'actualHumidity'}    = $$runtime_ref{actualHumidity};
  }
}

# Main routine
sub main
{
  my %data;

  API::Init($data_directory, 0);

  # Get thermostat ID for thermostat name (if only 1 thermostat, name not required)
  my $thermostat_id = Tools::Get_Thermostat_Id() || die "Thermostat not defined";

  # Get operational and environmental information from ecobee server
  Get_Thermostat_Data($thermostat_id, \%data);

  printf("%.1f\n", $data{actualTemperature});
}

main(@ARGV);

