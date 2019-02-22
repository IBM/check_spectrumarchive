# check_spectrumarchive
This script performs checks for different components of Spectrum Archive EE. The components that are checked are:
- status of the software
- nodes
- tape drives
- tapes
- pools
- task

One component can be checked at a time using the appropriate command line option. 

The script is based on Spectrum Archive EE version 1.3 and uses the eeamdmin command


## Installation
Copy the script to each Spectrum Archive EE node that needs to be monitored. Make the script executable. 


### Dependencies
The generates json output using the eeadm command and uses the tool jq to parse the json output. The jq tool needs to be install on all nodes where this tool runs on. The default location where jq is expected is /usr/local/bin. This path can be changed within the script (paramater: $JQ_TOOL).

The script is based on Spectrum Archive EE version 1.3 and relies on the eeadm command. The EE admin command is specified in parameter $EE_ADM_CMD. It has not been tested with the older ltfsee command. 


### Integration with Icinga2
tbd


## Syntax
This script can be invoked with one parameter at a time and performs the appropriate checks. 

	usage: ./check_spectrumarchive.sh [ -s | -n | -t | -d | -p<util> | -a<r|c> -h
	
	syntax:
         -s             --> Verify IBM Spectrum Archive status
         -n             --> Verify node status
         -t             --> Verify tape states
         -d             --> Verify drive states
         -p<util>       --> Check pool utilization threshold to util
         -a<r|c>        --> Check for running or completed tasks
         -h             --> Print This Help Screen
