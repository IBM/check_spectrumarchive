# Introduction to check_spectrumarchive.sh
This script performs checks for different components of Spectrum Archive EE. The components that can be checked are:
- status of software
- nodes
- tape drives
- tapes
- pools
- task

The script uses the Spectrum Archive EE admin command (eeadm) to get the details of a specified component in json format. The output of eeadm command is parsed and a decision is derived whether the state of the component is OK, WARNING or ERROR. The output is written to standard out in one line including the status of the components and the return code is in accordance with the detected status. For components that are not OK some further details are printed. 

The script is based on Spectrum Archive EE version 1.3 and uses the eeamdm command. It requires the jq tool to be installed on all Spectrum Archive EE nodes where this tool runs. 


## Syntax
This script can be invoked with one parameter at a time and performs the appropriate checks. 

	usage: ./check_spectrumarchive.sh [ -s | -n | -t | -d | -p<util> | -a<r|c> -h
	
	Options:
         -s             --> Verify IBM Spectrum Archive status
         -n             --> Verify node status
         -t             --> Verify tape states
         -d             --> Verify drive states
         -p<util>       --> Check pool utilization threshold to util
         -a<r|c>        --> Check for running or completed tasks
         -h             --> Print This Help Screen

The script returns OK, WARNING or ERROR including the component and the appropriate return 0, 1 or 2 respectively.
Only one option can be specified at a time. The combination of multiple options in one call of the script does not work. 

Only one option can be used at a time. Thus the combination of multiple options with one command executions is not possible. 

The script can be used standalone or it can be intergrated with a external Icinga or nagios monitoring server. 


## Installation
Install the dependencies and 
Transfer the script to each Spectrum Archive EE node that needs to be monitored. Make the script executable. 

The script can now be used from the command line. 

Optionally integrate the script with an external monitoring tool such as Icinga. 


### Dependencies
The script is based on Spectrum Archive EE version 1.3 and relies on the eeadm command. The EE admin command is specified in parameter $EE_ADM_CMD within the script. It has not been tested with the older ltfsee command. 

The tool jq is used to parse the json output generated by the eeadm command. The jq tool needs to be install on all nodes where this tool runs on (all Spectrum Archive nodes being monitored). The default location where jq is expected is /usr/local/bin. This path can be changed within the script (paramater: $JQ_TOOL).
More information about jq: https://stedolan.github.io/jq/


## Integration with Icinga
Icinga allows to monitor infrastructure and services. The Icinga architecture is client and server based. 


The server is the Icinga server providing the graphical user interface and the option to configure monitored objects such as hostgroups, hosts and services. The hosts to be monitored are the Spectrum Archive nodes. The services are checked with the check_spectrumarchive.sh script. The Icinga server essentially calls the script on the remote Spectrum Archive nodes using NRPE. More information about Icinga: https://Icinga.com/products/


The client is the IBM Spectrum Archive nodes being monitored. The communication between the server and the client can be based on Nagios Remote Plugin Executor (NRPE). This requires to install and configure NRPE on the Spectrum Archive nodes. 
More information about NRPE: https://exchange.nagios.org/directory/Addons/Monitoring-Agents/NRPE--2D-Nagios-Remote-Plugin-Executor/details



### Prepare the client (EE nodes)
In order to monitor the Spectrum Archive nodes using NRPE the NRPE packages and optionally the nagios-plugins have to be installed and configured. These packages need to be installed on all Spectrum Archive to be monitored. 


There are different ways to install NRPE and nagios plugins. Red Hat does not include these packages in the standard installation repository, but they can be downloaded from other sources (e.g. rpmfind). The following packages should be installed: 

	nrpe, nagios-common, nagios-plugin

An alternative way for installing NRPE and nagios-plugins can be found here: https://support.nagios.com/kb/article.php?id=8


After the installation of NRPE has finished, notice some important path and configuration files:
- NRPE configution file (NRPE.cfg), default location is /etc/nagios/NRPE.cfg
- nagios plugins (check_*), default location is /usr/lib64/nagios/plugins


Edit the NRPE configuration file (e.g /etc/nagios/NRPE.cfg) and set the include directory:

	include_dir=/etc/NRPE.d/


The check_spectrumarchive.sh script must be run with root privileges. NRPE however does not run as root but as a user that is defined in the NRPE.cfg file (NRPE_user, NRPE_group). The default user and group name is NRPE. Consequently sudo must be configured on the server to allow the NRPE-user to run the check_spectrumarchive.sh tool. To configure sudo, perform these steps:
1. In the NRPE-configuration file (/etc/nagios/NRPE.cfg) set command prefix to sudo:

		command_prefix=/usr/bin/sudo

2. Add the NRPE-user to the sudoer configuration:

		%NRPE          ALL=(ALL) NOPASSWD: /usr/local/bin/check_spectrumarchive.sh*,/usr/lib64/nagios/plugins/*


Now copy the executable script check_spectrumarchive.sh to /usr/local/bin


Switch to the NRPE-user and test if the script works under the sudo context:

	/usr/bin/sudo check_spectrumarchive.sh -s

Note, if you are not able to switch to the NRPE-user you may have to specify a login shell for the user (temporarily). 


Create the NRPE-configuration for the Spectrum Archive specific checks using this script. Note, the allowed_hosts must include the IP address of your Icinga server. Each check has a name given in [] which executes a particular command, such as /usr/local/bin/check_spectrumarchive.sh -s. Find an example below: 

	allowed_hosts=127.0.0.1,9.155.114.101
	command[check_users]=/usr/local/nagios/libexec/check_users -w 2 -c 5
	command[check_ee_state]=/usr/local/bin/check_spectrumarchive.sh -s
	command[check_ee_nodes]=/usr/local/bin/check_spectrumarchive.sh -n
	command[check_ee_tapes]=/usr/local/bin/check_spectrumarchive.sh -t
	command[check_ee_drives]=/usr/local/bin/check_spectrumarchive.sh -d
	command[check_ee_pools]=/usr/local/bin/check_spectrumarchive.sh -p 80
	command[check_ee_rtasks]=/usr/local/bin/check_spectrumarchive.sh -a r
	command[check_ee_ctasks]=/usr/local/bin/check_spectrumarchive.sh -a c


Now start and enable the NRPE service and check the status:

	# systemctl start NRPE
	# systemctl enable NRPE
	# systemctl status NRPE

Continue with the configuration of the monitored objects on the Icinga server. 



### Configure Icinga server
Assume the Icinga server is installed an configured. The default configuration of the Icinga server is located in /etc/Icinga. The default location for the object definition is in /etc/Icinga/objects.


First check that the Icinga server can communicate with the Spectrum Archive nodes using NRPE. For this purpose the check_NRPE plugin of the server can be used. The default location is: /usr/lib/nagios/plugins/check_NRPE. Find an example below:

	/usr/lib/nagios/plugins/check_NRPE -H <IP of Spectrum Archive node>

This command should return the NRPE version. If this is not the case investigate the problem. 


Likewise you can execute a remote check:

	/usr/lib/nagios/plugins/check_NRPE -H <IP of Spectrum Archive node> -c check_ee_state

This command should also return an appropriate response


If the NRPE communication and remote commands work then allow external commands by opening the Icinga configuration file (/etc/Icinga/Icinga.cfg) and adjust this setting:

	check_external_commands=1


Now configure the objects for the Spectrum Archive nodes. It is recommended to create a new file in directory /etc/Icinga/objects. In the example below two Spectrum Archive host (eenode1 and eenode2) are assigned to a host group (eenodes). For this host group a number of services are defined that within the define service stanza. Each service has a name, a host group where it is executed and a check command. The check command specifies a NRPE check and the name of the check that was configured in the NRPE-configuration of the client. For example the check_command check_NRPE!check_ee_state will execute the command /usr/local/bin/check_spectrumarchive.sh -s on the hosts. 

	define hostgroup {
		hostgroup_name  eenodes
		alias           EE Nodes
		members         eenode1,eenode2
		}

	define host {
		use                     generic-host
		host_name               eenode1
		alias                   EE Node 1
		address                 <ip of ee node 1>
		}

	define host {
		use                     generic-host
		host_name               eenode2
		alias                   EE Node 2
		address                 <ip of ee node 2>
		}

	define service {
		use                     generic-service
		hostgroup_name          eenodes
		service_description     Users logged on to the system
		check_command           check_NRPE!check_users
		}

	define service {
		use                     generic-service
		hostgroup_name          eenodes
		service_description     Check EE software state
		check_command           check_NRPE!check_ee_state
		}

	define service {
		use                     generic-service
		hostgroup_name          eenodes
		service_description     Check EE node state
		check_command           check_NRPE!check_ee_nodes
		}

	define service {
		use                     generic-service
		hostgroup_name          eenodes
		service_description     Check EE drive states
		check_command           check_NRPE!check_ee_drives
		}

	define service {
		use                     generic-service
		hostgroup_name          eenodes
		service_description     Check EE tape states
		check_command           check_NRPE!check_ee_tapes
		}

	define service {
		use                     generic-service
		hostgroup_name          eenodes
		service_description     Check EE pool state 
		check_command           check_NRPE!check_ee_pools
		}

	define service {
		use                     generic-service
		hostgroup_name          eenodes
		service_description     Check EE running tasks
		check_command           check_NRPE!check_ee_rtasks
		}

	define service {
		use                     generic-service
		hostgroup_name          eenodes
		service_description     Check EE completed tasks
		check_command           check_NRPE!check_ee_ctasks
		}


Once the object definition has been done and store in default object location /etc/Icinga/objects restart the Icinga process using systemctl or init.d. 


In the example above we have used the old Icinga 1 syntax to define objects. Icinga 2 comes with a new syntax with a similar semantic. More information about migrating from Icinga 1 syntax to Icinga 2 syntax: https://Icinga.com/docs/Icinga2/latest/doc/23-migrating-from-Icinga-1x/ 


Logon to the Icinga server GUI and check your host groups, hosts and services. The following is an example, how this may look like: 


