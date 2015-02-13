#! /usr/bin/perl

use strict;
use warnings;
use List::Util qw(min max);
use lib '/your_path_here';

use constant TZ => -5;

require Ecobee;

# Run in automatic, unattended mode or interact with user (default)
our $set_auto = 0;
our $data_directory = '/your_path_here';

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

  Ecobee::API_Get_Request($cmd, \%prop, \%results);

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

  Ecobee::API_Get_Request($cmd, \%prop, \%results);

  my @revisionList = @{$results{revisionList}};
  my $revisionString  = $revisionList[0];
  my @revisionParms = split(':', $revisionString);

  $$p_scalar_ref = $revisionParms[3];
  return ($revisionParms[2] eq "true");
}

# Request from ecobee servers, thermostat, environmental, sensor and runtime data
sub Get_Thermostat_Data {
  my ($p_thermostat_id, $p_hash_ref) = @_;

  my $request_date;
  my $request_interval;

  # Request thermostat data
  {
    my %results;
    my $cmd = 'thermostat';
    my %prop = (selection => {
                 selectionType => 'thermostats',
                 selectionMatch => $p_thermostat_id,
                 includeSettings => 'true',
                 includeRuntime => 'true',
                 includeWeather => 'true'
               }
              );

    Ecobee::API_Get_Request($cmd, \%prop, \%results);

    my $thermostat_ref = \@{$results{thermostatList}};
    my $settings_ref   = \%{$$thermostat_ref[0]{settings}};
    my $runtime_ref    = \%{$$thermostat_ref[0]{runtime}};
    my $weather_ref    = \%{$$thermostat_ref[0]{weather}};
    my $forecasts_ref  = \@{$$weather_ref{forecasts}};
    my $forecast_ref   = \%{$$forecasts_ref[0]};

    $request_date = $$runtime_ref{runtimeDate};
    $request_interval = $$runtime_ref{runtimeInterval};

    # Settings
    $$p_hash_ref{'hvacMode'}              = $$settings_ref{hvacMode};
    $$p_hash_ref{'hasHeatPump'}           = $$settings_ref{hasHeatPump};
    $$p_hash_ref{'hasHrv'}                = $$settings_ref{hasHrv};
    $$p_hash_ref{'hasDehumidifier'}       = $$settings_ref{hasDehumidifier};
    $$p_hash_ref{'dehumidifierMode'}      = $$settings_ref{dehumidifierMode};
    $$p_hash_ref{'dehumidifierLevel'}     = $$settings_ref{dehumidifierLevel};
    $$p_hash_ref{'dehumidifyWhenHeating'} = $$settings_ref{dehumidifyWhenHeating};
    $$p_hash_ref{'dehumidifierMinRuntimeDelta'} = 2; # not accessible from API
    $$p_hash_ref{'fanMinOnTime'}          = $$settings_ref{fanMinOnTime};

    # Runtime
    $$p_hash_ref{'connected'}         = $$runtime_ref{connected};
    $$p_hash_ref{'actualTemperature'} = F10toC($$runtime_ref{actualTemperature});
    $$p_hash_ref{'actualHumidity'}    = $$runtime_ref{actualHumidity};

    # Forecast
    $$p_hash_ref{'exteriorTemperature'}      = F10toC($$forecast_ref{temperature});
    $$p_hash_ref{'exteriorRelativeHumidity'} = $$forecast_ref{relativeHumidity};
  }

  # Request sensor data
  {
    my %results;
    my $cmd = 'runtimeReport';
    my %prop = (selection => {
                 selectionType => 'thermostats',
                 selectionMatch => $p_thermostat_id,
                 includeRuntimeSensorReport => 'true'
                },
                startDate => $request_date,
                endDate => $request_date,
                startInterval => max(0, $request_interval - 2),
                endInterval => $request_interval,
                includeSensors => 'true'
               );

    Ecobee::API_Get_Request($cmd, \%prop, \%results);

    my $sensorList_ref = \@{$results{sensorList}};
    my $sensors_ref = \@{$$sensorList_ref[0]{sensors}};
    my $columns_ref = \@{$$sensorList_ref[0]{columns}};
    my $data_ref = \@{$$sensorList_ref[0]{data}};

    my $sensor_ref;
    my %data;
    my $sensor_name;
    foreach $sensor_ref (@$sensors_ref) {
      my %sensor = %$sensor_ref;
      undef $sensor_name;
      if (($sensor{sensorType} eq 'temperature') and ($sensor{sensorUsage} eq 'indoor')) {
        $sensor_name = 'sensorIndoor';
      }
      elsif (($sensor{sensorType} eq 'temperature') and ($sensor{sensorUsage} eq 'outdoor')) {
        $sensor_name = 'sensorOutdoor';
      }

      if (defined($sensor_name)) {
        my $i;
        my $nb_columns = @$columns_ref;
        for ($i = 0; $i < $nb_columns; $i++) {
          if ($sensor{sensorId} eq $$columns_ref[$i]) {
            my @dataParms = split(',', $$data_ref[2]);
            $$p_hash_ref{$sensor_name} = FtoC($dataParms[$i]);
          }
        }
      }
    }
  }

  # Request from ecobee servers, runtime data
  {
    # Currently: get dehumidifier run time percentage in last 60 minutes.
    my %results;
    my $cmd = 'runtimeReport';
    my %prop = (selection => {
                 selectionType => 'thermostats',
                 selectionMatch => $p_thermostat_id,
                },
                startDate => $request_date,
                endDate => $request_date,
                startInterval => max(0, $request_interval - 12),
                endInterval => $request_interval,
                columns => 'dehumidifier'
               );

    Ecobee::API_Get_Request($cmd, \%prop, \%results);
  
    my $reportList_ref = \@{$results{reportList}};
    my $rowCount = $$reportList_ref[0]{rowCount};
    if ($rowCount > 0) {
      my $rowList_ref = \@{$$reportList_ref[0]{rowList}};
  
      my $total = 0;
      my $runstr = '';
      my $i;
      for ($i = 0; $i < $rowCount; $i++) {
          my @row = split(',', $$rowList_ref[$i]);
          $total += $row[2];
          $runstr = $runstr . ($row[2] == 0 ? '.' : ($row[2] == 300 ? 'O' : 'o'));
      }

      $$p_hash_ref{'dehumidifierPercentRuntime'} = 100*($total/($rowCount*300));
      $$p_hash_ref{'dehumidifierRunGraph'} = $runstr;
    }
  }
}

# Send to ecobee servers, changes to thermostat programming (if any)
sub Set_Thermostat_Data {
  my ($p_thermostat_id, $p_hum_level, $p_fan_level, $p_data_ref) = @_;

  my %results;
  my $cmd = 'thermostat';
  my %settings;

  my $log = sprintf("Request dehum %.1f%%, fan %s", $p_hum_level, ($p_fan_level > 0 ? 'ON' : 'OFF'));
  Log_Data($log);

  my $dehum_mode;
  my $dehum_level;

  if ($p_hum_level == -1) {
    Log_Data("Do not control dehumidifier");
  }
  elsif ($p_hum_level == 0) {
    # Dehumidifier OFF
    $dehum_mode = 'off';
    $dehum_level = 0;

    if ($$p_data_ref{'dehumidifierMode'} ne $dehum_mode) {
      # Going from ON to OFF, just specify mode
      $settings{'dehumidifierMode'} = $dehum_mode;
    }
  }
  else {
    # Dehumidifier ON
    $dehum_mode = 'on';
    $dehum_level = To_Thermostat_Humidity($p_hum_level);

    if ($$p_data_ref{'dehumidifierMode'} ne $dehum_mode) {
      # Going from OFF to ON, specify both mode and level
      $settings{'dehumidifierMode'} = $dehum_mode;
      $settings{'dehumidifierLevel'} = $dehum_level;
    }
    else {
      # Going to a different dehumidification level, specify just level
      # Only adjust if raw requested level is at least 1.5% different to prevent oscillation effect
      if (($$p_data_ref{'dehumidifierLevel'} != $dehum_level) and
          (abs($p_hum_level - $$p_data_ref{'dehumidifierLevel'}) >= 1.5)) {
        $settings{'dehumidifierLevel'} = $dehum_level;
      }
    }
  }

  # Control furnace fan
  if ($p_fan_level == -1) {
    Log_Data("Do not control furnace fan");
  }
  elsif ($$p_data_ref{'fanMinOnTime'} != $p_fan_level) {
    $settings{'fanMinOnTime'} = $p_fan_level;
  }

  # Any settings to change on thermostat?
  if (keys(%settings) > 0) {
    my %prop = (selection => {
                 selectionType => 'thermostats',
                 selectionMatch => $p_thermostat_id
                },
                thermostat => {
                  settings => \%settings
                }
               );

    Log_Data("Set dehumidifier [$dehum_mode, $dehum_level%], fan [$p_fan_level]");

    my $old_revision;
    if (!Get_Thermostat_Revision($p_thermostat_id, \$old_revision)) {
      Log_Data("Not connected");
      return (0);
    }

    Ecobee::API_Post_Request($cmd, \%prop, \%results);

    # Wait for thermostat revision change. Time out after a minute
    my $new_revision;
    my $i;
    for ($i = 0; $i < 60; $i++) {
      sleep(1);

      if (!Get_Thermostat_Revision($p_thermostat_id, \$new_revision)) {
        Log_Data("Disconnected while waiting for revision change");
        return (0);
      }

      if ($old_revision ne $new_revision) {
        Log_Data("Updated");
        return (1);
      }
    }
    Log_Data("Update timed out");
    return (0);
  }
  else {
    Log_Data("No update needed");
    return (1);
  }
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

# Convert humidity rh1 at temperature t1 to humidity rh2 at temperature t2
sub Calculate_Humidity {
  my ($p_t1, $p_rh1, $p_t2) = @_;

  $p_t1 += 273;
  $p_t2 += 273;
			
  my $p0 = 7.5152E8;
  my $deltaH = 42809;
  my $R = 8.314;
			
  my $sat_p1 = $p0 * exp(-$deltaH/($R*$p_t1));
  my $sat_p2 = $p0 * exp(-$deltaH/($R*$p_t2));
  my $vapor = $sat_p1 * $p_rh1/100;
  my $rh2 = ($vapor/$sat_p2)*100;
# my $dew = -$deltaH/($R*log($vapor/$p0)) - 273;

  return ($rh2);
}

# Figure out ideal indoor humidity based on outdoor temperature
sub Ideal_Indoor_Humidity {
  my ($p_outside_temp) = @_;

  # 2 or more temp/hum pairs are needed
  my @temp_hum = ({temp => -20, hum => 30},
                  {temp => 0, hum => 45},
                  {temp => 20, hum => 60});

  my $arr_size = @temp_hum;
  my $hum;
  my $i;
  my $ratio;

  for ($i = 0; $i < $arr_size; $i++) {
    # Temperature is below range
    if (($i == 0) and ($p_outside_temp < $temp_hum[$i]{temp})) {
      $ratio = ($temp_hum[$i+1]{temp} - $p_outside_temp)/($temp_hum[$i+1]{temp} - $temp_hum[$i]{temp});
      $hum = $temp_hum[$i+1]{hum} - $ratio*($temp_hum[$i+1]{hum} - $temp_hum[$i]{hum});
      last;
    }
    # Temperature is above range
    elsif (($i == $arr_size-1) and ($p_outside_temp > $temp_hum[$i]{temp})) {
      $ratio = ($p_outside_temp - $temp_hum[$i-1]{temp})/($temp_hum[$i]{temp} - $temp_hum[$i-1]{temp});
      $hum = $temp_hum[$i-1]{hum} + $ratio*($temp_hum[$i]{hum} - $temp_hum[$i-1]{hum});
      last;
    }
    # Temperature is within range
    elsif (($p_outside_temp >= $temp_hum[$i]{temp}) and ($p_outside_temp <= $temp_hum[$i+1]{temp})) {
      $ratio = ($p_outside_temp - $temp_hum[$i]{temp})/($temp_hum[$i+1]{temp} - $temp_hum[$i]{temp});
      $hum = $temp_hum[$i]{hum} + $ratio*($temp_hum[$i+1]{hum} - $temp_hum[$i]{hum});
      last;
    }
  }

  # Limit range to 0% .. 100%
  return (max(min($hum, 100), 0));
}

# Log messages to screen or log file in auto mode
sub Log_Data {
  my ($p_data) = @_;

  # In auto mode, write to log file, otherwise to standard out
  if ($set_auto) {
    open(FILE, ">>$data_directory/ecobee_mgr.log") or return;
    my $local_time = time() + (TZ*3600);
    my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = gmtime($local_time);
    my $tstamp = sprintf("%04d-%02d-%02d %02d:%02d:%02d", $year+1900, $mon+1, $mday, $hour, $min, $sec);
    print(FILE "$tstamp $p_data\n");
    close(FILE);
  }
  else {
    print("$p_data\n");
  }
}

# Main routine
sub main {
  my ($p_parm) = @_;
  my %data;
  my $log;
  my $mode;
  my $dehum_level;
  my $fan_level;

  $set_auto = (defined $p_parm ? ($p_parm eq "-auto") : 0);
  Ecobee::Init($data_directory, $set_auto);
  Log_Data("=========ecobee_mgr.pl Start=========");

  # Get thermostat ID for thermostat name (if only 1 thermostat, name not required)
  my $thermostat_id = Get_Thermostat_Id() || die "Thermostat not defined";

  # Get operational and environmental information from ecobee server
  Get_Thermostat_Data($thermostat_id, \%data);

  # Avoid making decisions on stale data
  if ($data{connected} eq "true") {

    # HRV dehumidifier section
    if (($data{hvacMode} eq "heat") and ($data{hasHrv} eq "true") and
        ($data{hasDehumidifier} eq "true")  and ($data{dehumidifyWhenHeating} eq "true")) {
      # Use actual outdoor sensor if available, otherwise from weather forecast
      my $outdoor_temp = (defined($data{sensorOutdoor}) ?
                          $data{sensorOutdoor} :
                          $data{exteriorTemperature});

      # Get indoor temperature from average of all temp sensors
      my $indoor_temp = $data{actualTemperature};

      # Calculate what is the exterior humidity at indoor temperature: after HRV
      my $out_hum_in = Calculate_Humidity($data{exteriorTemperature},
                                          $data{exteriorRelativeHumidity},
                                          $indoor_temp);

      # Calculate what is the actual ideal humidity at current outdoor temperature
      my $ideal_hum_at_21 = Ideal_Indoor_Humidity($outdoor_temp);
      my $ideal_hum = Estimate_Ecobee_Humidity($ideal_hum_at_21, $indoor_temp);

      $log = sprintf("Out: [%d%% @ %.1fC] = [%d%% @ %.1fC] In: %d%% => %.1f%% (%.1fC)",
                     $data{exteriorRelativeHumidity}, $data{exteriorTemperature},
                     $out_hum_in, $indoor_temp, $data{actualHumidity}, $ideal_hum, $outdoor_temp);
      Log_Data($log);

      if (defined($data{dehumidifierPercentRuntime})) {
        $log = sprintf("Dehumidifier [%s, %d%%] run %d%% [%s]",
                       $data{dehumidifierMode}, $data{dehumidifierLevel},
                       $data{dehumidifierPercentRuntime}, $data{dehumidifierRunGraph});
      }
      else {
        $log = sprintf("Dehumidifier [%s, %d%%]", $data{dehumidifierMode}, $data{dehumidifierLevel});
      }
      Log_Data($log);

      # Calculate if we can lower current humidity with outside air
      # Outside air has to be drier by at least 2% to avoid long HRV run times

      # Outside air has higher humidity than current, turn off HRV dehumidifier
      my $humidity_delta = $data{dehumidifierMinRuntimeDelta} + 2;
      if ($out_hum_in >= $data{actualHumidity} - $humidity_delta) {
        $dehum_level = 0;
      }
      # Outside air has higher humidity than ideal but still lower than current
      elsif ($out_hum_in >= $ideal_hum - $humidity_delta) {
        $dehum_level = $out_hum_in + $humidity_delta;
      }
      # Outside is dry enough that we can request ideal humidity level
      else {
        $dehum_level = $ideal_hum;
      }
    }
    else {
      Log_Data("HRV cannot be used as dehumidifier: hvacMode: $data{hvacMode} hasHrv: $data{hasHrv} hasDehumidifier: $data{hasDehumidifier} dehumidifyWhenHeating: $data{dehumidifyWhenHeating}");
      $dehum_level = -1;
    }

    # Temp equalizer section
    if (defined($data{sensorIndoor})) {
      # Start furnace fan when indoor sensors are too different
      # actualTemperature is average of both sensors so we can extrapolate
      # temperature difference by multiplying by 2.
      my $temp_diff = 2*abs($data{sensorIndoor} - $data{actualTemperature});
      if ($temp_diff >= 1) {
        $fan_level = 60;
      }
      else {
        $fan_level = 0;
      }
      $log = sprintf("Temp diff up/avg %.1f/%.1f: %.1fC => fan %d min/hour", 
                     $data{sensorIndoor}, $data{actualTemperature}, $temp_diff, $fan_level);
      Log_Data($log);
    }
    else
    {
      Log_Data("Remote indoor temp sensor does not exist, cannot calculate temp diff");
      $fan_level = -1;
    }

    Set_Thermostat_Data($thermostat_id, $dehum_level, $fan_level, \%data);
  }
  else {
    Log_Data("Thermostat not connected to server, cannot take decisions based on stale data");
  }

  $log = sprintf("Number of API calls: %d", Ecobee::API_Calls());
  Log_Data($log);
  Log_Data("----------ecobee_mgr.pl End----------");
}

main(@ARGV);
