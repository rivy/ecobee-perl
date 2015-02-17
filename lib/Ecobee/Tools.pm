#! /usr/bin/perl

package Tools;

use strict;
use warnings;
use List::Util qw(min max);

require Ecobee::API;

# Get ID of the Smart thermostat to interact with
sub Get_Thermostat_Id {
  my ($p_thermostat_name) = @_;

  my %results;
  my $cmd = 'thermostatSummary';
  my %prop = (selection => {
               selectionType => 'registered',
               selectionMatch => ''
              }
             );

  API::Get_Request($cmd, \%prop, \%results);

  my @revisionList = @{$results{revisionList}};
  my $revisionQty = @revisionList;

  my $use_default = ((!defined($p_thermostat_name)) and ($revisionQty == 1));
  my $revision;
  foreach $revision (@revisionList) {
    my @revisionParms = split(':', $revision);
    return ($revisionParms[0]) if (($use_default) or ($p_thermostat_name eq $revisionParms[1]));
  }

  # Thermostat not found!
  return (0);
}

# Get Thermostat Revision to detect if changes applied
sub Get_Thermostat_Revision {
  my ($p_thermostat_id, $p_scalar_ref) = @_;

  my %results;
  my $cmd = 'thermostatSummary';
  my %prop = (selection => {
               selectionType => 'thermostats',
               selectionMatch => $p_thermostat_id
              }
             );

  API::Get_Request($cmd, \%prop, \%results);

  my @revisionList = @{$results{revisionList}};
  my $revisionString  = $revisionList[0];
  my @revisionParms = split(':', $revisionString);

  $$p_scalar_ref = $revisionParms[3];
  return ($revisionParms[2] eq "true");
}

# Convert Farenheit 1/10 of degrees to Celsius degrees
sub F10toC {
  my ($p_f10) = @_;
  return (($p_f10 - 320) / 18.0);
}

# Convert Celsius degrees to Farenheit 1/10 of degrees
sub CtoF10 {
  my ($p_c) = @_;
  return (($p_c * 18.0) + 320);
}

# Convert Farenheit degrees to Celsius degrees
sub FtoC {
  my ($p_f) = @_;
  return (($p_f - 32) / 1.8);
}

# Convert Celsius degrees to Farenheit degrees
sub CtoF {
  my ($p_c) = @_;
  return (($p_c * 1.8) + 32);
}

# Round to next integer
sub round {
  my ($p_float) = @_;
  return (int($p_float + $p_float/abs($p_float*2)));
}

# Round to precision
sub RoundToPrecision {
  my ($p_float, $p_precision) = @_;
  return ($p_precision*round($p_float/$p_precision));
}

# Convert raw humidity value to nearest even number between 30 and 80
sub To_Thermostat_Humidity {
  my ($p_humidity) = @_;
  my $hum = RoundToPrecision($p_humidity, 2);
  return (max(min($hum, 80), 30));
}

# Attempt to emulate thermostat's RH adjustment based on indoor temperature
# Thermostat seems to add .5% humidity for each degree drop
sub Estimate_Ecobee_Humidity {
  my ($p_rh1, $p_t2) = @_;

  my $rh2 = $p_rh1 + (21 - $p_t2)*0.5;
  return ($rh2);
}

1;

