#! /usr/bin/perl

use strict;
use warnings;
use lib '/your_path_here/lib';

use Date::Calc qw(Day_of_Week Add_Delta_DHMS);
require Ecobee::API;
require Ecobee::Tools;

use constant RUN_FREQ => 0.5; # Script is called every 30 minutes

# Run in automatic, unattended mode or interact with user (default)
our $set_auto = 0;
our $data_directory = '/your_path_here/data';

# Request from ecobee servers, thermostat, environmental, sensor and runtime data
sub Get_Thermostat_Data
{
  my ($p_thermostat_id, $p_hash_ref) = @_;

  my $request_date;
  my $request_interval;

  # Request thermostat data
  {
    my %results;
    my $cmd = 'thermostat';
    my %prop = (selection =>
                {
                  selectionType => 'thermostats',
                  selectionMatch => $p_thermostat_id,
                  includeSettings => 'true',
                  includeRuntime => 'true',
                  includeProgram => 'true',
                  includeEvents => 'true',
                  includeEquipmentStatus => 'true',
                  includeLocation => 'true',
                  includeWeather => 'true'
                }
               );

    API::Get_Request($cmd, \%prop, \%results);

    my $thermostat_ref = \@{$results{thermostatList}};

    my $settings_ref   = \%{$$thermostat_ref[0]{settings}};

    my $runtime_ref    = \%{$$thermostat_ref[0]{runtime}};
    $request_date = $$runtime_ref{runtimeDate};
    $request_interval = $$runtime_ref{runtimeInterval};

    my $weather_ref    = \%{$$thermostat_ref[0]{weather}};
    my $forecasts_ref  = \@{$$weather_ref{forecasts}};
    my $forecast_ref   = \%{$$forecasts_ref[0]};

    my $program_ref    = \%{$$thermostat_ref[0]{program}};
    my $schedule_ref   = \@{$$program_ref{schedule}};
    my $climates_ref   = \@{$$program_ref{climates}};

    my $stat_time_ref = \$$thermostat_ref[0]{thermostatTime};
    my $eqp_stat_ref  = \$$thermostat_ref[0]{equipmentStatus};

    my $location_ref  = \%{$$thermostat_ref[0]{location}};

    my $events_ref = \@{$$thermostat_ref[0]{events}};

    # Thermostat
    $$p_hash_ref{'thermostatTime'}    = $$stat_time_ref;
    $$p_hash_ref{'equipmentStatus'}   = $$eqp_stat_ref;

    # Settings
    $$p_hash_ref{'hvacMode'}          = $$settings_ref{hvacMode};
    $$p_hash_ref{'disablePreHeating'} = $$settings_ref{disablePreHeating};
    $$p_hash_ref{'heatStages'}        = $$settings_ref{heatStages};
    $$p_hash_ref{'heatingDifferential'} = Tools::F10toC_diff($$settings_ref{stage1HeatingDifferentialTemp});
    $$p_hash_ref{'auxMaxOutdoorTemp'} = Tools::F10toC($$settings_ref{auxMaxOutdoorTemp});

    # Runtime
    $$p_hash_ref{'connected'}         = $$runtime_ref{connected};
    $$p_hash_ref{'runtimeDate'}       = $$runtime_ref{runtimeDate};
    $$p_hash_ref{'runtimeInterval'}   = $$runtime_ref{runtimeInterval};
    $$p_hash_ref{'actualTemperature'} = Tools::F10toC($$runtime_ref{actualTemperature});
    $$p_hash_ref{'desiredHeat'}       = Tools::F10toC($$runtime_ref{desiredHeat});

    # Forecast
    $$p_hash_ref{'exteriorTemperature'} = Tools::F10toC($$forecast_ref{temperature});

    # Program
    $$p_hash_ref{'currentClimateRef'} = $$program_ref{currentClimateRef};
    $$p_hash_ref{'climates_ref'} = \@{$$program_ref{climates}};
    $$p_hash_ref{'schedule_ref'} = \@{$$program_ref{schedule}};

    # Location
    $$p_hash_ref{'timeZoneOffsetMinutes'} = $$location_ref{timeZoneOffsetMinutes};
    $$p_hash_ref{'isDaylightSaving'}      = $$location_ref{isDaylightSaving};

    # Events
    $$p_hash_ref{'events_ref'} = $events_ref;
  }

  # Request sensor data
  {
    my %results;
    my $cmd = 'runtimeReport';
    my %prop = (selection =>
                {
                  selectionType => 'thermostats',
                  selectionMatch => $p_thermostat_id,
                  includeRuntimeSensorReport => 'true'
                },
                startDate => $request_date,
                endDate => $request_date,
                startInterval => Tools::max(0, $request_interval - 2),
                endInterval => $request_interval,
                includeSensors => 'true'
               );

    API::Get_Request($cmd, \%prop, \%results);

    my $sensorList_ref = \@{$results{sensorList}};
    my $sensors_ref = \@{$$sensorList_ref[0]{sensors}};
    my $columns_ref = \@{$$sensorList_ref[0]{columns}};
    my $data_ref = \@{$$sensorList_ref[0]{data}};

    my $sensor_ref;
    my %data;
    my $sensor_name;
    foreach $sensor_ref (@$sensors_ref)
    {
      my %sensor = %$sensor_ref;
      undef $sensor_name;
      if (($sensor{sensorType} eq 'temperature') and ($sensor{sensorUsage} eq 'outdoor'))
      {
        $sensor_name = 'sensorOutdoor';
      }

      if (defined($sensor_name))
      {
        my $i;
        my $nb_columns = @$columns_ref;
        for ($i = 0; $i < $nb_columns; $i++)
        {
          if ($sensor{sensorId} eq $$columns_ref[$i])
          {
            my @dataParms = split(',', $$data_ref[2]);
            $$p_hash_ref{$sensor_name} = Tools::FtoC($dataParms[$i]);
          }
        }
      }
    }
  }
}

# Get day of week from date/time format "YYYY-MM-DD HH:MM:SS"
# Where Monday=0 and Sunday=6
sub Get_Day_of_Week
{
  my ($p_tstat_time) = @_;

  my ($year, $mon, $mday, $hour, $min, $sec) = ($p_tstat_time =~ /(\d+)-(\d+)-(\d+) (\d+):(\d+):(\d+)/);
  my $wday = Date::Calc::Day_of_Week($year, $mon, $mday); # Mon=1
  return ($wday-1); # Mon=0
}

# Add a float number of hours to a date/time format "YYYY-MM-DD HH:MM:SS"
# Returning an array of date and time strings
sub Add_Hours_to_DateTime
{
  my ($p_tstat_time, $p_hours) = @_;

  my ($year, $mon, $mday, $hour, $min, $sec) = ($p_tstat_time =~ /(\d+)-(\d+)-(\d+) (\d+):(\d+):(\d+)/);

  my ($year2, $mon2, $mday2, $hour2, $min2, $sec2) =
       Date::Calc::Add_Delta_DHMS($year, $mon, $mday, $hour, $min, $sec, 0, $p_hours, 0, 0);

  my $date_str = sprintf("%04d-%02d-%02d", $year2, $mon2, $mday2);
  my $time_str = sprintf("%02d:%02d:%02d", $hour2, $min2, $sec2);

  return ($date_str, $time_str);
}

# Get name of next climate, in how many hours will it occur and the heating set temp
sub Get_Next_Climate
{
  my ($p_sched_aref, $p_clim_aref, $p_tstat_time, $p_curr_clim) = @_;

  my $sched_day_idx = Get_Day_of_Week($p_tstat_time);
  my ($year, $mon, $mday, $hour, $min, $sec) = ($p_tstat_time =~ /(\d+)-(\d+)-(\d+) (\d+):(\d+):(\d+)/);
  my $sched_30min_idx = ($hour*2) + int($min/30) + 1; # Get next time block
  my $min_to_next_clim = 30 - ($min % 30);

  my $day_idx = $sched_day_idx;
  my $min_idx = $sched_30min_idx;
  my $found = 0;
  my $next_climate = '';
  my $next_climate_hrs = 0;
  my $next_climate_temp = 0;

  while (($day_idx < $sched_day_idx+7) and not $found)
  {
    while (($min_idx < 48) and not $found)
    {
      if ($$p_sched_aref[$day_idx%7][$min_idx] ne $p_curr_clim)
      {
        $next_climate = $$p_sched_aref[$day_idx%7][$min_idx];
        $found = 1;
      }
      else
      {
        $min_to_next_clim += 30;
      }
      $min_idx++;
    }
    $min_idx = 0;
    $day_idx++;
  }

  if ($found)
  {
    $next_climate_hrs = $min_to_next_clim/60;

    $found = 0;
    my $climate_ref;
    foreach $climate_ref (@$p_clim_aref)
    {
      my %climate = %$climate_ref;
      if ($climate{climateRef} eq $next_climate)
      {
        $next_climate_temp = Tools::F10toC($climate{heatTemp});
        $found = 1;
        last;
      }
    }
  }

  return ($found, $next_climate, $next_climate_hrs, $next_climate_temp);
}

sub Get_Furnace_Heating_Capacity
{
  my ($p_outside_temp) = @_;

  # 2 or more temp/cap pairs are needed
  # cap = heating capacity in degrees/hour
  my @temp_cap = ({temp => -20, cap => 1.70},
                  {temp => -3, cap => 2.25});

  my $arr_size = @temp_cap;
  my $cap;
  my $i;
  my $ratio;

  for ($i = 0; $i < $arr_size; $i++)
  {
    # Temperature is below range
    if (($i == 0) and ($p_outside_temp < $temp_cap[$i]{temp}))
    {
      $ratio = ($temp_cap[$i+1]{temp} - $p_outside_temp)/($temp_cap[$i+1]{temp} - $temp_cap[$i]{temp});
      $cap = $temp_cap[$i+1]{cap} - $ratio*($temp_cap[$i+1]{cap} - $temp_cap[$i]{cap});
      last;
    }
    # Temperature is above range
    elsif (($i == $arr_size-1) and ($p_outside_temp > $temp_cap[$i]{temp}))
    {
      $ratio = ($p_outside_temp - $temp_cap[$i-1]{temp})/($temp_cap[$i]{temp} - $temp_cap[$i-1]{temp});
      $cap = $temp_cap[$i-1]{cap} + $ratio*($temp_cap[$i]{cap} - $temp_cap[$i-1]{cap});
      last;
    }
    # Temperature is within range
    elsif (($p_outside_temp >= $temp_cap[$i]{temp}) and ($p_outside_temp <= $temp_cap[$i+1]{temp}))
    {
      $ratio = ($p_outside_temp - $temp_cap[$i]{temp})/($temp_cap[$i+1]{temp} - $temp_cap[$i]{temp});
      $cap = $temp_cap[$i]{cap} + $ratio*($temp_cap[$i+1]{cap} - $temp_cap[$i]{cap});
      last;
    }
  }

  # Limit range to 0.5 .. 3 deg/hr
  return (Tools::range($cap, 0.5, 3));
}

# Compare current thermostat time with latest runtime interval to calculate
# how old is the thermostat data (in hours)
sub Thermostat_Data_Age
{
  my ($p_tstat_time, $p_runtime_interval, $p_timezone_offset, $p_isdst) = @_;

  my ($year, $mon, $mday, $hour, $min, $sec) = ($p_tstat_time =~ /(\d+)-(\d+)-(\d+) (\d+):(\d+):(\d+)/);
  my $rmin = (($p_runtime_interval*5) + $p_timezone_offset + ($p_isdst eq 'true' ? 60 : 0)) % (24*60);
  my $lhr = (($hour*60 + $min) - $rmin - 5)/60;
  $lhr += 24 if ($lhr < 0); # correct rollover problems
  return ($lhr);
}

# Determine if thermostat is running an event (set by watchdog or not)
sub Running_Thermostat_Event
{
  my ($p_events_aref, $p_tstat_time) = @_;

  my $is_running_event = 0;
  my $event_href;
  foreach $event_href (@$p_events_aref)
  {
    my %event = %$event_href;

    if (($event{running} eq 'true') and ($event{type} eq 'hold'))
    {
      my $start = sprintf("%s %s", $event{startDate}, $event{startTime});
      my $end   = sprintf("%s %s", $event{endDate}, $event{endTime});

      if (($p_tstat_time ge $start) and ($p_tstat_time le $end))
      {
        $is_running_event = 1;
        last;
      }
    }
  }
  return ($is_running_event);
}

# Send to ecobee servers, changes to thermostat programming (if any)
sub Set_Climate_Event
{
  my ($p_thermostat_id, $p_climate, $p_tstat_time, $p_delay) = @_;

  my %results;
  my $cmd = 'thermostat';

  my %params;
  $params{'holdClimateRef'} = $p_climate;
  $params{'holdType'} = 'nextTransition';
  if ($p_tstat_time and $p_delay)
  {
    my ($new_date, $new_time) = Add_Hours_to_DateTime($p_tstat_time, $p_delay);
    $params{'startDate'} = $new_date;
    $params{'startTime'} = $new_time;
    Log_Data("Hold start date $new_date, start time $new_time");
  }

  my %prop = (selection =>
              {
                selectionType => 'thermostats',
                selectionMatch => $p_thermostat_id
              },
              functions =>
               [{
                  type => 'setHold',
                  params => \%params
                }]
             );

  Log_Data("Set hold event for $p_climate climate");

  my $old_revision;
  if (!Tools::Get_Thermostat_Revision($p_thermostat_id, \$old_revision))
  {
    Log_Data("Not connected");
    return (0);
  }

  API::Post_Request($cmd, \%prop, \%results);

  # Wait for thermostat revision change. Time out after a minute
  my $new_revision;
  my $i;
  for ($i = 0; $i < 60; $i++)
  {
    sleep(1);

    if (!Tools::Get_Thermostat_Revision($p_thermostat_id, \$new_revision))
    {
      Log_Data("Disconnected while waiting for revision change");
      return (0);
    }

    if ($old_revision ne $new_revision)
    {
      Log_Data("Updated");
      return (1);
    }
  }
  Log_Data("Update timed out");
  return (0);
}

# Log messages to screen or log file in auto mode
sub Log_Data
{
  my ($p_data) = @_;

  # In auto mode, write to log file, otherwise to standard out
  if ($set_auto)
  {
    open(FILE, ">>$data_directory/ecobee_wdog.log") or return;
    my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime();
    my $tstamp = sprintf("%04d-%02d-%02d %02d:%02d:%02d", $year+1900, $mon+1, $mday, $hour, $min, $sec);
    print(FILE "$tstamp $p_data\n");
    close(FILE);
  }
  else
  {
    print("$p_data\n");
  }
}

# Main routine
sub main
{
  my ($p_parm) = @_;
  my %data;
  my $log;

  $set_auto = (defined($p_parm) ? ($p_parm eq "-auto") : 0);
  API::Init($data_directory, $set_auto);

  # Get thermostat ID for thermostat name (if only 1 thermostat, name not required)
  my $thermostat_id = Tools::Get_Thermostat_Id() || die "Thermostat not defined";

  # Get operational and environmental information from ecobee server
  Get_Thermostat_Data($thermostat_id, \%data);

  # Avoid making decisions on stale data
  if ($data{connected} eq 'true')
  {
    # Use actual outdoor sensor if available, otherwise from weather forecast
    my $outdoor_temp = (defined($data{sensorOutdoor}) ? $data{sensorOutdoor}
                                                      : $data{exteriorTemperature});

    # System is in heating mode and Smart Recovery is enabled and Aux heat can be used
    if (($data{hvacMode} eq 'heat') and ($data{disablePreHeating} eq 'false') and
        ($outdoor_temp < $data{auxMaxOutdoorTemp}))
    {
      # If system is not running an event
      if (not Running_Thermostat_Event($data{events_ref}, $data{thermostatTime}))
      {
        # Determine maximum heat stage and running equipment
        my $max_heat_stage = sprintf('auxHeat%d', $data{heatStages});
        my $max_heat_on = (index($data{equipmentStatus}, $max_heat_stage) >= 0);
        my $heatpump_on = (index($data{equipmentStatus}, 'heatPump') >= 0);

        # Is system already in some form of smart recovery?
        my $max_heat_recovery = 0;
        my $heatpump_recovery = 0;
        if ($data{actualTemperature} > $data{desiredHeat})
        {
          $max_heat_recovery = $max_heat_on;
          $heatpump_recovery = $heatpump_on;
        }

        # If system is not already in max heat smart recovery
        if (not $max_heat_recovery)
        {
          my ($found, $next_climate, $next_climate_hrs, $next_temp) =
               Get_Next_Climate(\@{$data{schedule_ref}}, \@{$data{climates_ref}},
                                $data{thermostatTime}, $data{currentClimateRef});
          if ($found)
          {
            my $temp_delta = $next_temp - $data{actualTemperature};

            # Take into account age of data in determining if we will not get Smart Recovery in time
            my $data_age = Thermostat_Data_Age($data{thermostatTime}, $data{runtimeInterval},
                                               $data{timeZoneOffsetMinutes}, $data{isDaylightSaving});

            if (($data_age >= 0) and ($data_age < RUN_FREQ))
            {
              if (($next_temp > $data{desiredHeat}) and ($next_climate_hrs > $data_age) and
                  ($temp_delta > $data{heatingDifferential}))
              {
                # Thermostat data is several minutes old, take it into account when calculating
                # heating times
                $next_climate_hrs += $data_age;

                my $deg_per_hour = Get_Furnace_Heating_Capacity($outdoor_temp);

                $log = sprintf("Temperature needs to increase by %.2f degrees in %.2f hours (%.2f d/h)",
                               $temp_delta, $next_climate_hrs, $temp_delta/$next_climate_hrs);
                Log_Data($log);
                $log = sprintf("At %.1fC degree, furnace can increase %.2f degrees per hour",
                               $outdoor_temp, $deg_per_hour);
                Log_Data($log);

                # How many hours to wait before firing up max heat
                my $wait_hrs = $next_climate_hrs - ($temp_delta/$deg_per_hour);

                # We will be called again before time is up so do nothing now
                if ($wait_hrs >= RUN_FREQ)
                {
                  $log = sprintf("Wait another %.2f hours before increasing temps", $wait_hrs);
                  Log_Data($log);
                }
                # Time to increase temps will happen before we are called again
                elsif ($wait_hrs > 0)
                {
                  # At this point, if max heat is running, it's probably Smart Recovery...
                  if ($max_heat_on)
                  {   
                    Log_Data("Max Heat is already on, this may be early Smart Recovery, let's wait to see at the next cycle");
                  }   
                  # we're already in heatpump smart recovery so we can schedule a max heat up event now
                  elsif ($heatpump_recovery)
                  {
                    $log = sprintf("Heatpump smart recovery already running and script will not be run in time so schedule heat increase in %.2f hours", $wait_hrs);
                    Log_Data($log);
                    Set_Climate_Event($thermostat_id, $next_climate, $data{thermostatTime}, $wait_hrs);
                  }
                  else
                  {
                    $log = sprintf("Not sure what to do so wait another %.2f hours before increasing temps", $wait_hrs);
                    Log_Data($log);
                  }
                }
                # Time to increase temps is now or in the past
                else
                {
                  # We're already past the heat start time, do it now unless max heat is already on
                  # and hope this is smart recovery
                  if (not $max_heat_on)
                  {
                    $log = sprintf("Target heat will not be reached in time, start furnace now but target will be late by %.2f hours",
                                   -$wait_hrs);
                    Log_Data($log);
   
                    Set_Climate_Event($thermostat_id, $next_climate, $data{thermostatTime}, 0);
                  }
                }
              }
              else
              {
                if ($next_temp <= $data{desiredHeat})
                {
                  Log_Data("Next climate will not be increasing temps");
                }
                else
                {
                  Log_Data("Not enough time left to make changes") if ($next_climate_hrs <= $data_age);
                  Log_Data("Temperature increase too small") if ($temp_delta <= $data{heatingDifferential});
                }
              }
            }
            else
            {
              Log_Data("There's a gap in reporting, do nothing");
            }
            $log = sprintf("Data is %d minutes old", $data_age*60);
            Log_Data($log);
          }
        }
        else
        {
          Log_Data("Already in $max_heat_stage Smart Recovery");
        }
      }
      else
      {
        Log_Data("Already in a hold");
      }
    }
    else
    {
      Log_Data("Not in Smart Recovery Heat mode or outside temp too high");
    }
  }
  else
  {
    Log_Data("Thermostat not connected to server, cannot make decisions based on stale data");
  }

#  $log = sprintf("Number of API calls: %d", API::API_Calls());
#  Log_Data($log);
}

# Run main routine
main(@ARGV);

