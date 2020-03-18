#!/bin/bash

################################################################################
# The MIT License (MIT)                                                        #
#                                                                              #
# Copyright (c) 2019 Nils Haustein                             				   #
#                                                                              #
# Permission is hereby granted, free of charge, to any person obtaining a copy #
# of this software and associated documentation files (the "Software"), to deal#
# in the Software without restriction, including without limitation the rights #
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell    #
# copies of the Software, and to permit persons to whom the Software is        #
# furnished to do so, subject to the following conditions:                     #
#                                                                              #
# The above copyright notice and this permission notice shall be included in   #
# all copies or substantial portions of the Software.                          #
#                                                                              #
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR   #
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,     #
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE  #
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER       #
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,#
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE#
# SOFTWARE.                                                                    #
################################################################################

################################################################################
# Name:		Check IBM Spectrum Archive EE
#
# Author: 	Nils Haustein - haustein(at)de.ibm.com
#
# Contributor:	Alexander Saupp - asaupp(at)gmail(dot)com
# Contributor:	Achim Christ - achim(dot)christ(at)gmail(dot)com
# Contributor:	Jan-Frode Myklebust - janfrode(at)tanso(dot)net
#
# Version:	1.3.5
#
# Dependencies:	
#   - IBM Spectrum Archive EE running on Spectrum Scale
#   - jq: json parser (https://stedolan.github.io/jq/)
#         EPEL:  https://centos.pkgs.org/7/epel-x86_64/jq-1.5-1.el7.x86_64.rpm.html
#         ppc64: http://ftp.us2.freshrpms.net/linux/RPM/epel/7/ppc64/Packages/j/jq-devel-1.5-1.el7.ppc64.html
#
# Github Repository: 
# https://github.com/nhaustein/check_spectrumarchive
#
#
################################################################################

# This bash script checks various aspects of an IBM Spectrum Archive
# It verifies the state of EE, node state, tape state and pool state. 
# Typically, it would be run on all EE nodes in a cluster.
# 
# The code uses eeadm commands with the --json parameter to generate the output
# in JSON format. In order to parse the json format the jq tool is required. 
# Download jq here: (https://stedolan.github.io/jq/) and place it in /usr/bin.
# Example: jq -r '.payload[] | [.id, .state] | @csv' node.json

# The actual code is managed in the following Git rebository - please use the
# Issue Tracker to ask questions, report problems or request enhancements. The
# repository also contains an extensive README.

# Disclaimer: This sample is provided 'as is', without any warranty or support.
# It is provided solely for demonstrative purposes - the end user must test and
# modify this sample to suit his or her particular environment. This code is
# provided for your convenience, only - though being tested, there's no
# guarantee that it doesn't seriously break things in your environment! If you
# decide to run it, you do so on your own risk!


################################################################################
## change history
################################################################################
# 02/22/19 version 1.0 published on github
# 01/03/19 version 1.1 if the command return code is 0 and $out is empty then give 
#          a warning for nodes, drives, tapes and task checks instead of an error
# 08/03/19 version 1.2 if mmm is not running check if the node is an active control
#          node and if this is not the case then continue with the checks. 
# 06/03/19 version 1.2.1 add full path to mm commands
# 08/02/19 version 1.2.2 fix the absense of reclaim% in pool list output, added function div to for divisions with floating point numbers
# 10/06/19 version 1.2.3 fix division by 0 when calculating reclspace 
# 11/29/19 version 1.3 create functions for each check and add option (-e) to check all
# 11/30/19 version 1.3 send sysmon events if the custom events exist for option -e
# 12/06/19 version 1.3.1 merge with JF pull request
# 12/11/19 version 1.3.2 fix syntax checking to show syntax when parameter does not have - in front
# 01/15/20 version 1.3.3 fix check_task, version earlier than 1.3.0.6 did not support json output for active task, version 1.3.0.6 supports json output for running task. Do not use json output for tasks, just grep
# 02/12/20 version 1.3.4 fix bogus error message mmm is not running - keep the full NODENAME
# 03/05/20 version 1.3.5 correct echo syntax error, use complete path for mmsysmonc ($SYSMON_CMD)
# 03/13/20 version 1.3.5 change event code and labels for GUI events (upper case labels won't work)
# 03/13/20 version 1.3.5 check status for tape and drive instead of states
################################################################################
## Future topics
################################################################################
#
# optionally use REST API
# 
# 

################################################################################
## Variable definition
################################################################################
# define the version number
ver=1.3.5

# debug option: if this 1 then the json output is parsed from a file (e.g. ./node_test.json)
DEBUG=0

# define the custom event IDs as they are defined in the custom.json example
# if the event IDs are changed in the custom.json, it must be adjusted here. 
eventGood=ee_001
eventWarn=ee_002
eventErr=ee_003

# eventEnable is 0 (false) and events are not send for single component checks by default
eventEnabled=0

# path to the custom.json file in Spectrum Scale
customJson="/usr/lpp/mmfs/lib/mmsysmon/custom.json"

# mmsysmonc command
SYSMON_CMD="/usr/lpp/mmfs/bin/mmsysmonc"

# path and file name of the admin command line tool for EE
EE_ADM_CMD="/opt/ibm/ltfsee/bin/eeadm"

# specify the path to the jq tool
JQ_TOOL="/usr/local/bin/jq"

# get hostname
HOSTNAME=$(hostname | sed "s/\..*$//" )
# fix 1.3.4 keep the full node name without cutting of .
NODENAME=$(/usr/lpp/mmfs/bin/mmlsnode -N localhost)

# default threshold that throws a WARMING for pool low space
DEFAULT_LOW_SPACE_THRESHOLD=10

# define node status
NODE_WARNING_STATUS=(disabled)
NODE_ERROR_STATUS=(error)
NODE_GOOD_STATUS=(available)

# define tape status
TAPE_WARNING_STATUS=(info degraded warning)
TAPE_ERROR_STATUS=(error)
TAPE_GOOD_STATUS=(ok)

# define drive status
DRIVE_WARNING_STATUS=(info)
DRIVE_ERROR_STATUS=(error)
DRIVE_GOOD_STATUS=(ok)


################################################################################
## Functions
##
################################################################################
# syntax and usage
#
# prints the syntax
################################################################################
error_usage () {
  ERROR=$1
  HELP="\n
   Check IBM Spectrum Archive EE status version $ver (MIT licence)\n
   \n
   usage: $0 [ -s | -n | -t | -d | -p<util> | -a<r|c> | -e | -h\n
   \n
   syntax:\n
   \t	-s	\t\t--> Verify IBM Spectrum Archive status\n
   \t	-n	\t\t--> Verify node status\n
   \t   -t  \t\t--> Verify tape states\n
   \t   -d  \t\t--> Verify drive states\n
   \t	-p<util>\t--> Check pool utilization threshold to util\n
   \t	-a<r|c>\t--> Check for running or completed tasks\n
   \t	-e  \t\t--> check the Entire systems with all components\n
   \t	-h	\t\t--> Print This Help Screen\n
  "
  echo -e $HELP

  if [ "$ERROR" == "" ]; then
    echo -e "\nYou'll probably execute this script via NRPE remotly"
  else
    echo -e "$0 $* \n"
#    echo -e "\n$ERROR"
  fi
  exit 2
}

################################################################################
## Function: in_array
##
## checks if an element ($1) is included in an array ($2) and returns 0 or 1
################################################################################
function in_array {
  val=$1
  array=$2

  for v in ${array[*]}
  do
    if [[ "$v" == "$val" ]]
    then
      return 0
    fi
  done
  return 1
}

################################################################################
## Function: div
##
## divides two numbers and returns floating point result
##
## Copyright by StackOverflow (captured from this thread:
## https://stackoverflow.com/questions/12147040/division-in-script-and-floating-point/24431665
################################################################################
function div ()  # Arguments: dividend and divisor
{
        if [ $2 -eq 0 ]; then 				  # division by 0 returns 0
		  echo 0 
		  return 0
		fi
        local p=12                            # precision
        local c=${c:-0}                       # precision counter
        local d=.                             # decimal separator
        local r=$(($1/$2)); echo -n $r        # result of division
        local m=$(($r*$2))
        [ $c -eq 0 ] && [ $m -ne $1 ] && echo -n $d
        [ $1 -eq $m ] || [ $c -eq $p ] && return
        local e=$(($1-$m))
        let c=c+1
        div $(($e*10)) $2
}

################################################################################
## Function: check_events
##
## checks if the custom events are installed by:
## - check if /usr/lpp/mmfs/lib/mmsysmon/custom.json exists
## - check if check EE event codes exist in the custom.json
##
## Result: if custom events are installed then eventEnabled is set to 1, otherwise eventEnabled is set to 0
## 
################################################################################
function check_events
{
  out=""
  notExist=0
  # check if custom event file exists
  if [[ -a $customJson ]];
  then
    # now check if the eventCodes are included
	for e in $eventGood $eventWarn $eventErr; 
	do
	  out=""
	  out=$(grep $e $customJson)
	   if [[ -z $out ]]; then notExist=1; break; fi
	done
	if (( $notExist == 0 )); then eventEnabled=1; fi
  fi

  return $eventEnabled	
}


################################################################################
## Function check_status
##
## Check IBM Spectrum Archive status
##
## checks if mmm is running
## check if recalld is running
## check if ltfs is mounted
################################################################################
## Sample output - this is what we're going to parse
# ps -ef | grep mmm
# root     13162 21048  0 14:39 pts/0    00:00:00 grep --color=auto mmm
# root     13683     1  0 Jan11 ?        00:11:19 /opt/ibm/ltfsee/bin/mmm -b -l 0000013100730409
function check_status()
{
  msg=""
  out=""
  found=0
  exitrc=0
  out=$(ps -ef | grep "\/opt\/ibm\/ltfsee/bin\/mmm" | grep -v grep)

  # first check if mmm is running, mmm is only running on the active control node
  # if mmm is not running then check if the node is not an active node and if this is true continue
  if [ -z "$out" ] ; then
    if (( $DEBUG == 0 )) ; then
      out=$($EE_ADM_CMD node list --json |  $JQ_TOOL -r '.payload[] | [.id, .state, .hostname, .enabled, .control_node, .active_control_node] | @csv' 2>&1)
      rc=$?
    else
      # used for debugging different states
      out=$(cat ./node_test.json |  $JQ_TOOL -r '.payload[] | [.id, .state, .hostname, .enabled, .control_node, .active_control_node] | @csv' 2>&1)
      rc=$?
      # echo "DEBUG: $out"
    fi

    if [[ ! -z $out && $rc == 0 ]] ; then
      while read line ; do
        id=$(echo $line | cut -d',' -f1)						# node id
        state1=$(echo $line | cut -d',' -f2 | cut -d'"' -f2)	# state
        state2=$(echo $line | cut -d',' -f3 | cut -d'"' -f2)	# hostname
        state3=$(echo $line | cut -d',' -f4)					# enabled ?
        state4=$(echo $line | cut -d',' -f5)					# control node ?
        state5=$(echo $line | cut -d',' -f6)					# active control node ?

        if [[ $NODENAME == $state2 && $state5 == false ]] ; then
          found=1
          break
        fi
      done <<< "$(echo -e "$out")"
      if (( $found == 0 )) ; then
        msg="ERROR: mmm is not runing on node $NODENAME"
        exitrc=2
      fi
    else
      msg="ERROR: EE is not running and node status not detected."
      exitrc=2
    fi 
  fi
  
  if (( $exitrc > 0 )) ; then
    return $exitrc
  fi
  
  # mmm might be running but recalld not
  out=$(ps -ef | grep "dsmrecalld" | grep -v grep)

  if [ -z "$out" ] ; then
    msg="ERROR: Recall daemons are not running on node $NODENAME"
    return 2
  fi

  # check if /ltfs is mounted
  myarray=$(echo $(df | grep "\/" | awk '{print $6}' ))
  if ( ! in_array "/ltfs" "${myarray[*]}" ) ; then
    msg="ERROR: backend LTFS file system (/ltfs) is not mounted on node $NODENAME"
    return 2
  fi
  
  # if we did not bail out before, all is good
  if (( $found == 0 )) ; then      
     msg="OK: EE is started and running."
  else 
     msg="OK: EE is started and running on inactive control node"
  fi    
  return 0
}

################################################################################
## Function check_nodes
##
## Check IBM Spectrum Archive EE node state
##
## Verify node state for all nodes
##
## Note, does not yet have status field, so we look at the state
################################################################################
# sample 1.3.0.6
#{
#  "id": 2,
#  "ip": "9.155.113.41",
#  "hostname": "ltfsee-1",
#  "port": 7600,
#  "enabled": true,
#  "num_of_drives": 2,
#  "library_id": "0000013100730409",
#  "library_name": "eelib1",
#  "nodegroup_id": "G0@0000013100730409",
#  "nodegroup_name": "G0",
#  "state": "available",
#  "control_node": true,
#  "active_control_node": true},
function check_nodes
{
  msg=""
  out=""
  id=""
  state1=""
  state2=""
  state3=""
  state4=""
  state5=""
  exitrc=0

  if (( $DEBUG == 0 )) ; then
    out=$($EE_ADM_CMD node list --json |  $JQ_TOOL -r '.payload[] | [.id, .state, .hostname, .enabled, .control_node, .active_control_node] | @csv' 2>&1)
    rc=$?
  else
    # used for debugging different states
    out=$(cat ./node_test.json |  $JQ_TOOL -r '.payload[] | [.id, .state, .hostname, .enabled, .control_node, .active_control_node] | @csv' 2>&1)
    rc=$?
    # echo "DEBUG: $out"
  fi

  if [[ ! -z $out && $rc == 0 ]] ; then
    while read line ; do
      id=$(echo $line | cut -d',' -f1)						# node id
      state1=$(echo $line | cut -d',' -f2 | cut -d'"' -f2)	# state
      state2=$(echo $line | cut -d',' -f3 | cut -d'"' -f2)	# hostname
      state3=$(echo $line | cut -d',' -f4)					# enabled ?
      state4=$(echo $line | cut -d',' -f5)					# control node ?
      state5=$(echo $line | cut -d',' -f6)					# active control node ?

      if ( in_array $state1 "${NODE_ERROR_STATUS[*]}" ) ; then
        msg="ERROR: Node ID $id ($state2) is in status=$state1 (control node=$state4, enabled=$state3); "$msg
        exitrc=2
      elif ( in_array $state1 "${NODE_WARNING_STATUS[*]}" ) ; then
        msg=$msg"WARNING: Node ID $id ($state2) is in status=$state1 (control node=$state4, enabled=$state3); "
        if (( $exitrc < 2 )) ; then
          exitrc=1
        fi
      elif ( ! in_array $state1 "${NODE_GOOD_STATUS[*]}" ) ; then
        msg=$msg"WARNING: Unknown node status=$state1 detected for node ID $id (node name=$state2, control node=$state4, enabled=$state3); "
        if (( $exitrc < 2 )) ; then
          exitrc=1
        fi
      fi
    done <<< "$(echo -e "$out")"
  else
    msg="ERROR: node status not detected. EE may be down or not configured!"
    exitrc=2
  fi

  if (( $exitrc == 0 )); then
    msg="OK: Nodes state is GOOD"
    return 0
  else
    return $exitrc
  fi
}

################################################################################
## Function check_tapes
##
## Check IBM Spectrum Archive EE tape state
##
## Verify status for all tapes
################################################################################
## Sample output - this is what we're going to parse
# eeadm tape list --json
#{ "id": "SLE038L6@000001302300_LLC",
#  "barcode": "SLE038L6",
#  "state": "appendable",
#  "status": "ok",
#  "media_type": "L6",
#  "media_generation": "LTO-Gen6",
#  "format_density": "L6",
#  "worm": false,
#  "pool_name": "zf2",
#  "pool_id": "6b57c5002ced40c08ca59e7aecf958d6",
#  "appendable": "yes",
#  "capacity": 2408088338432,
#  "used_space": 83886080,
#  "free_space": 2408004452352,
#  "non_appendable_space": 0,
#  "reclaimable_space": 6452768,
#  "reclaimable%": 0,
#  "active_space": 77433312,
#  "address": "257",
#  "library_name": "eelib2",
#  "library_id": "000001302300_LLC",
#  "drive_id": "1068006885",
#  "task_id": "",
#  "offline_msg": "",
#  "location_type": "drive" }
#
function check_tapes
{
  msg=""
  out=""
  id=""
  state1=""
  state2=""
  state3=""
  state4=""
  state5=""
  exitrc=0

  if (( $DEBUG == 0 )) ; then
    out=$($EE_ADM_CMD tape list --json |  $JQ_TOOL -r '.payload[] | [.barcode, .state, .pool_name, .library_name, .location_type, .status] | @csv' 2>&1)
    rc=$?
  else
    # used for debugging different states
    out=$(cat ./tape_test.json |  $JQ_TOOL -r '.payload[] | [.barcode, .state, .pool_name, .library_name, .location_type, .status] | @csv' 2>&1)
    rc=$?
    # echo "DEBUG: rc=$rc, out=$out"
  fi

  if [[ ! -z $out && $rc == 0  ]] ; then
    while read line ; do
      id=$(echo $line | cut -d',' -f1 | cut -d'"' -f2)		# tape id
      state1=$(echo $line | cut -d',' -f2 | cut -d'"' -f2)	# state
      state2=$(echo $line | cut -d',' -f3  | cut -d'"' -f2)	# pool_name
      state3=$(echo $line | cut -d',' -f4  | cut -d'"' -f2)	# library_name
      state4=$(echo $line | cut -d',' -f5  | cut -d'"' -f2)	# location_type
	  state5=$(echo $line | cut -d',' -f6  | cut -d'"' -f2)	# status

      if ( in_array $state5 "${TAPE_ERROR_STATUS[*]}" ) ; then
        msg="ERROR: Tape $id is in state: $state1 (pool=$state2 - library=$state3, location=$state4); "$msg
        exitrc=2
      elif ( in_array $state5 "${TAPE_WARNING_STATUS[*]}" ) ; then
        msg=$msg"WARNING: Tape $id is in state: $state1 (pool=$state2 - library=$state3 - location=$state4); "
        if (( $exitrc < 2 )) ; then
          exitrc=1
        fi
      elif ( ! in_array $state5 "${TAPE_GOOD_STATUS[*]}" ) ; then
        msg=$msg"WARNING: Unknow tape status=$state5, state=$state1 detected for tape $id (pool=$state2 - library=$state3 - location=$state4); "
        if (( $exitrc < 2 )) ; then
          exitrc=1
        fi
      fi
    done <<< "$(echo -e "$out")"
  else
    msg="ERROR: tape status not detected. EE may be down or tapes are not available!"
    exitrc=2
  fi

  if (( $exitrc == 0 )) ; then
    msg="OK: Tape state is GOOD"
    return 0
  else
    return $exitrc
  fi
}

################################################################################
## Function check_drives
##
## Check IBM Spectrum Archive EE drive state
##
## Verify status for all drives
##
################################################################################
# Sample output 1.3.0.6
#{
# "id": "00078B1153",
#      "status": "ok",
#      "state": "mounted",
#      "type": "LTO6",
#      "role": "mrg",
#      "library_id": "0000013100730409",
#      "library_name": "eelib1",
#      "address": 257,
#      "node_id": 2,
#      "node_hostname": "ltfsee-1",
#      "tape_barcode": "SLE033L6",
#      "nodegroup_name": "G0",
#      "task_id": "",
#      "scsi_vendor_id": "IBM",
#      "scsi_product_id": "ULT3580-TD6",
#      "scsi_firmware_revision": "JAX0",
#      "host_scsi_address": "4.0.0.0",
#      "host_device_name": "/dev/sg1"
# },
function check_drives
{
  msg=""
  out=""
  id=""
  state1=""
  state2=""
  state3=""
  state4=""
  state5=""
  exitrc=0

  if (( $DEBUG == 0 )) ; then
    out=$($EE_ADM_CMD drive list --json |  $JQ_TOOL -r '.payload[] | [.id, .state, .type, .library_name, .node_hostname, .status] | @csv' 2>&1)
    rc=$?
  else
    # used for debugging different states
    out=$(cat ./drive_test.json | $JQ_TOOL -r '.payload[] | [.id, .state, .type, .library_name, .node_hostname, .status] | @csv' )
    rc=$?
    # echo "DEBUG: rc=$rc, out=$out"
  fi

  if [[ ! -z $out && $rc == 0  ]] ; then
    while read line ; do
      id=$(echo $line | cut -d',' -f1 | cut -d'"' -f2)		# drive id
      state1=$(echo $line | cut -d',' -f2 | cut -d'"' -f2)	# state
      state2=$(echo $line | cut -d',' -f3  | cut -d'"' -f2)	# drive type
      state3=$(echo $line | cut -d',' -f4  | cut -d'"' -f2)	# library name
      state4=$(echo $line | cut -d',' -f5  | cut -d'"' -f2)	# hostname
	  state5=$(echo $line | cut -d',' -f6  | cut -d'"' -f2) # status

      if ( in_array $state5 "${DRIVE_ERROR_STATUS[*]}" ) ; then
        msg="ERROR: drive $id is in state: $state1 (type=$state2, library=$state3 - node=$state4); "$msg
        exitrc=2
      elif ( in_array $state5 "${DRIVE_WARNING_STATUS[*]}" ) ; then
        msg=$msg"WARNING: drive $id is in state: $state1 (type=$state2, library=$state3, node=$state4); "
        if (( $exitrc < 2 )) ; then
          exitrc=1
        fi
      elif ( ! in_array $state5 "${DRIVE_GOOD_STATUS[*]}" ) ; then
        msg=$msg"WARNING: Unknown status=$state5 with state=$state1 detected for drive $id (type=$state2 - library=$state3, node=$state4); "
        if (( $exitrc < 2 )) ; then
          exitrc=1
        fi
      fi

    done <<< "$(echo -e "$out")"
  else
    msg="ERROR: drive status not detected. EE may be down or no drives are configured!"
    exitrc=2
  fi

  if (( $exitrc == 0 )) ; then
    msg="OK: Drive state is GOOD"
    return 0
  else
    return $exitrc
  fi
}

################################################################################
## Function check_pools
##
## Check IBM Spectrum Archive EE pool state
##
## Check if free space in pools is below the specified threshold (e.g. 10%)
## Check if reclaimable space above a threshold given with the command
################################################################################
## Sample output - this is what we're going to parse
# eeadm pool list --json
#{"id": "fd7b1115-a093-45c1-ad35-24e01dd3d62b",
#  "name": "swift2",
#  "media_restriction": "^.{8}$",
#  "capacity": 2408088338432,
#  "used_space": 611319808,
#  "free_space": 2407477018624,
#  "reclaimable_space": 611317836,
#  "reclaimable%": 0,
#  "active_space": 1972,
#  "non_appendable_space": 0,
#  "num_of_tapes": 1,
#  "format_class": "default",
#  "library_name": "eelib2",
#  "library_id": "000001302300_LLC",
#  "nodegroup_name": "G0",
#  "device_type": "LTO",
#  "worm": "no",
#  "fill_policy": "Default",
#  "owner": "System",
#  "mount_limit": 0,
#  "low_space_warning_enable": false,
#  "low_space_warning_threshold": 0,
#  "no_space_warning_enable": false,
#  "mode": "normal" }
function check_pools
{
  msg=""
  out=""
  id=""
  state1=""
  state2=0
  state3=0
  state4=0
  exitrc=0

  if (( $DEBUG == 0 )) ; then
    # out=$($EE_ADM_CMD pool list --json |  $JQ_TOOL -r '.payload[] | [.name, .free_space, ."reclaimable%", .low_space_warning_threshold, .capacity] | @csv' 2>&1)

    # fix for absense of reclaim%
    out=$($EE_ADM_CMD pool list --json |  $JQ_TOOL -r '.payload[] | [.name, .free_space, ."reclaimable_space", .low_space_warning_threshold, .capacity] | @csv' 2>&1)
    rc=$?
  else
    # used for debugging
    # out=$(cat ./pool_test.json |  $JQ_TOOL -r '.payload[] | [.name, .free_space, ."reclaimable%", .low_space_warning_threshold, .capacity] | @csv' 2>&1)

    # fix for absense of reclaimable%
    out=$(cat ./pool_test.json |  $JQ_TOOL -r '.payload[] | [.name, .free_space, ."reclaimable_space", .low_space_warning_threshold, .capacity] | @csv' 2>&1)
    rc=$?
  fi

  if [[ ! -z $out && $rc == 0  ]] ; then
    while read line ; do
      id=$(echo $line | cut -d',' -f1 | cut -d'"' -f2)	# pool name
      state1=$(echo $line | cut -d',' -f2)				# free space
      state2=$(echo $line | cut -d',' -f3)				# reclaimable space
      state3=$(echo $line | cut -d',' -f4)				# low space warning threshold
      state4=$(echo $line | cut -d',' -f5)				# capacity

      if (( $state3 == 0 )) ; then
        state3=$DEFAULT_LOW_SPACE_THRESHOLD
      fi


      # if capacity is 0 then do not perform these calculations
	  if (( $state4 == 0 )); then
	    msg=$msg"WARNING: Pool $id has no tapes assigned (capacity=$state4); "
		if (( $exitrc < 2 )); then
		  exitrc=1
		fi
	  else
        # check if free space is below the threshold
        # (( threshold = ($state4 * $state3)/100 ))
        (( r = $state4 * $state3 ))
        threshold=$(div $r 100)
        threshold=$( echo $threshold | cut -d'.' -f1 )
        if (( $state1 <= $threshold )) ; then
          msg="ERROR: Pool $id is full (free space = $state1 - capacity = $state4); "$msg
          exitrc=2
        fi

        # check if reclaim percentage is >= reclamation threshold given with the command
        # reclaim percentage = reclaimable space / capaity * 100)
        # (( reclspace = (($state2/$state4)*100) ))
        (( r = $state2 * 100 ))
        reclspace=$(div $r $state4)
        reclspace=$(echo $reclspace | cut -d'.' -f1)
        if (( $reclspace >= $parm1 )) ; then
          msg=$msg"WARNING: Pool $id has reached reclamation threshold (reclaimable = $reclspace % - threshold = $parm1); "
          if (( $exitrc < 2 )) ; then
            exitrc=1
          fi
        fi
	  fi
    done <<< "$(echo -e "$out")"
  else
    msg="ERROR: No pools detected. EE may be down or no pools are created."
    exitrc=2
  fi

  if (( $exitrc == 0 )) ; then
    msg="OK: Pool state is GOOD"
    return 0
  else
    return $exitrc
  fi
}


################################################################################
## Function check_tasks
##
## Check IBM Spectrum Archive EE task state
##
## Check for running tasks (r)
## Check for failed completed task (c)
##
## Input: parm1 
##        r - show running task
##	      c - show completed task
##
## Note, do not use json output because EE version < 1.3.0.6 did not support 
## json output for eeadm task list, it displayed the json output for -c
################################################################################
## Sample output - this is what we're going to parse
# eeadm task list --json
#{"inuse_tapes": [
#    "SLE027L6"
#  ],
#  "inuse_pools": [
#    "zf1"
#  ],
#  "inuse_node_groups": [
#    "G0"
#  ],
#  "inuse_drives": [
#    "00078B1156"
#  ],
#  "cmd_param": "dsmrecalld",
#  "result": "",
#  "status": "running",
#  "completed_time": "",
#  "started_time": "2019-02-18T20:02:38.492Z",
#  "created_time": "2019-02-18T20:02:38.491Z",
#  "inuse_libs": [
#    "eelib1"
#  ],
#  "type": "transparent_recall",
#  "task_id": 1026,
#  "id": "1026@2019-02-18T20:02:38" }
function check_tasks
{
  msg=""
  out=""
  i=0
  # depending on parm1 set the task type (tt) to be used with the eeadm task list command
  if [[ "$parm1" == "r" ]]; then 
    tt=""
  elif [[ "$parm1" == "c" ]]; then
    tt="-c"
  else
     msg="WARNING: task type not valid or specified (value=$parm1). Internal program error."
	 return 1
  fi
  
  if (( $DEBUG == 0 )) ; then
    # do not generate and parse json because some lower levels of code do not support this for running task
    # out=$($EE_ADM_CMD task list --json | $JQ_TOOL -r '.payload[] | [.task_id, .type, .status, .result] | @csv' 2>&1)
    # instead just capture the output and grep later
	out=$($EE_ADM_CMD task list $tt)
    rc=$?
  else
    # used for debugging different states
    # out=$(cat ./task_test.json | $JQ_TOOL -r '.payload[] | [.task_id, .type, .status, .result] | @csv' 2>&1)
	out=$(cat ./task_test)
    rc=$?
  fi

  if [[ ! -z $out && $rc == 0 ]] ; then
    if [[ $parm1 == "r" ]]; then
      i=$(echo "$out" | grep -E "running|waiting" | wc -l)
      if (( i > 0 )); then
	    msg="OK: $i active task."
	  else 
	    msg="OK: no task running"
	  fi
	  return 0
	elif [[ $parm1 == "c" ]]; then
      i=$(echo "$out" | grep -E "failed|aborted" | wc -l)
      if (( i > 0 )); then
	    msg="WARNING: $i failed or aborted task(s). Consider to clear the history (eeadm task clearhistory)"
		return 1
	  else 
	    msg="OK: No failed or aborted task(s)"
		return 0
	  fi
	fi 
  else
    msg="ERROR: task status not detected. EE may be down or no task have been run."
    return 2
  fi
}


################################################################################
## Main
##
################################################################################

################################################################################
## Check prerequisites
##
## Spectrum Archive installed? jq installed?
################################################################################
if [ ! -f $EE_ADM_CMD ] ; then
  echo "ERROR: No IBM Spectrum Archive Installation detected in $EE_PATH"
  exit 2
fi
if [ ! -f $JQ_TOOL ] ; then
  echo "ERROR: utility jq not found, please download and install it in $JQ_TOOL (https://stedolan.github.io/jq/)"
  exit 2
fi


################################################################################
## Check Args
##
## Ensure valid paramters are given
################################################################################
if (( $# == 0 ));
then
  error_usage "No component to be checked has been specified as parameter."
fi

parm1=""
msg=""
finalrc=0
opt=$1

case "$opt" in
"-s")  check_status
    finalrc=$?;;
"-n")  check_nodes
    finalrc=$?;;
"-t")  check_tapes
    finalrc=$?;;
"-d")  check_drives
    finalrc=$?;;
"-p")  parm1=$2
    if [[ -z $parm1 ]];
	then
	  error_usage "Pool utilization threshold not specified"
	else
	  check_pools
      finalrc=$?
	fi;;
"-a")  parm1=$2
	if [[ -z $parm1 ]];
	then
	  error_usage "Task type not specified (-r=running or -c=completed)"
	elif [[ $parm1 == "r" || $parm1 == "c" ]];
	then
	  check_tasks
  	  finalrc=$?
	else
	  error_usage "Wrong task type ($parm1), must be -r for running or -c for completed tasks"
	fi;;
"-e") # all components are checked
    echo "$(date): check_spectrumarchive.sh version $ver started on node $HOSTNAME"
    echo "------------------------------------------------------------------------------------------------"
	check_events
	for func in check_status check_nodes check_tapes check_drives check_pools check_tasks-r check_tasks-c; 
	do
	  if [[ "$func" == "check_pools" ]];
	  then
	    parm1=80
	  elif [[ "$func" == "check_tasks-r" ]];
	  then
	    parm1="r"
	    func="check_tasks"
	  elif [[ "$func" == "check_tasks-c" ]];
	  then
	     parm1="c"
		 func="check_tasks"
	  fi
	  $func
	  tmprc=$?
	  if (( $tmprc > $finalrc )); then finalrc=$tmprc; fi
	  if [[ -z $cmsg ]]; then cmsg=$msg; else cmsg=$cmsg"\n"$msg; fi
	  # now send event if enabled
	  if (( $eventEnabled == 1 ));
	  then
	    if (( $tmprc == 1 )); 
        then
          $SYSMON_CMD event custom $eventWarn $func,"$msg"
        elif (( $tmprc == 2 ));
        then			
          $SYSMON_CMD event custom $eventErr $func,"$msg"
        fi
      fi		
    done
	msg=$cmsg;;
"-h")  error_usage;;
*)  error_usage "Unknown parameter \"$1\"";;
esac

# print the message
echo -e "$msg"
# if the entire system is checked (-e) and events are enabled and finalrc=0 then send info event
# echo "DEBUG: opt="$1", eventEnabled=$eventEnabled, finalrc=$finalrc"
if [[ $1 == "-e" && $eventEnabled == "1" && $finalrc == "0" ]];
then
  $SYSMON_CMD event custom $eventGood "check_all EE components","No problem found"
fi
exit $finalrc

