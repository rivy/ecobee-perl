ecobee-perl
===========

perl modules and script to control ecobee thermostat for dehumidifier and furnace fan

Current implementation includes module Ecobee::API.pm that takes care of all low-level access with ecobee API version 1
and module Ecobee::Tools.pm that includes certain often-used tools used with the API.

A perl script ecobee_mgr.pl takes care of controlling a heat recovery ventilator wired as a dehumidifier. Obviously this only makes sense in winter when the outside air is cold and dry enough to dehumidify inside the house. New functionality has recently been added to control the furnace fan to equalize the temperature between the first floor (internal thermostat temperature sensor) and a remote sensor located on the second floor. This has only been used and tested with an ecobee Smart thermostat with a wired remote sensor.

In order to get things under way, the first thing you need to do is get a developer tab in your ecobee web portal. Then you can create an app in the developer tab to get an API key. Next, you need to create an ascii text file where you are going to be running the ecobee_mgr.pl script called api_key.txt. This file needs to contain only your API key (no spaces in front or after, no ending CrLf).

Next, in ecobee_mgr.pl, you need to go modify the "use lib '/your_path_here/lib' " to the proper path where to find the Ecobee/*.pm modules if it's not in a standard perl library directory.

You also need to modify the "our $data_directory = '/your_path_here/data'; " to where you want to store your data files and where the api_key.txt file will be located.

Next, to get the authentication started, you need to call the ecobee_mgr.pl script from the command line.
This will give you a 4 digit pin from ecobee servers. You need to go to your ecobee web portal, in the settings tab (My Apps item on the left) where you need to enter the pin you just got.

Once you've done this, you need to run the script manually once more and it should function all the way through.
You will see some new files in your directory: authorize.dat and token.dat these are necessary for the script to be able to run automatically each time.

If you want to run this script in an automated fashion, you can call it with an "-auto" parameter so it will send the output to a log file instead of the screen and if authentication requires human intervention, it will fail instead.

If you're not already familiar with the ecobee API, now would be a good time to start :-) https://www.ecobee.com/home/developer/api/documentation/v1/index.shtml

I recommend that anyone using this module and script should go read https://www.ecobee.com/home/developer/api/documentation/v1/licensing-agreement.shtml
as I think it is important to be aware of ecobee requirements for use of their API.

I hope you enjoy this perl script and modules. Let me know if you have any questions, suggestions or comments.

