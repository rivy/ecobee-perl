ecobee-perl
===========

perl module and script to control ecobee thermostat for dehumidifier and furnace fan

Current implementation includes module Ecobee.pm that takes care of all low-level access with ecobee API version 1.

First thing you need to do is get a developer tab in your ecobee web portal. Then you can create an app in the developer tab to get an API key. Then you need to create an ascii text file where you are going to be running the ecobee_mgr.pl script called api_key.txt. This file needs to contain only your API key (no spaces in front or after, no ending CrLf).

Next, in ecobee_mgr.pl, you need to go modify the "use lib '/your_path_here' " to the proper path where to find the Ecobee.pm module if it's not in a standard perl library directory.

You also need to modify the "our $data_directory = '/your_path_here'; " to where you want to store you data files and where the api_key.txt file will be located.

Next, to get the authentication started, you need to call the ecobee_mgr.pl script from the command line.
This will give you a 4 digit pin from ecobee servers. You need to go to your ecobee web portal, in the settings tab (My Apps item on the left) where you need to enter the pin you just got.

Once you've done this, you need to run the script manually once more and it should function all the way through.
You will see some new files in your directory: authorize.dat and token.dat these are necessary for the script to be able to run automatically each time.

If you want to run this script in an automated fashion, you can call it with an "-auto" parameter so it will log the output to a log file instead and if authentication requires human intervention, it will fail instead.

I think that if you're not already familiar with the ecobee API, now would be a good time to start :-) https://www.ecobee.com/home/developer/api/documentation/v1/index.shtml

Although I am giving this away and will not profit in any way, I feel obligated to also send you this link https://www.ecobee.com/home/developer/api/documentation/v1/licensing-agreement.shtml
as I don't want to get in trouble with ecobee and have my API access privileges revoked because I should have mentioned this to you but didn't...

That out of the way, I hope you enjoy this perl script and module and let me know if you have any questions or comments.

