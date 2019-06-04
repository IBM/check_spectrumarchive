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
# Author: 	Nils Haustein - haustein(at)de.ibm.com
# Contributor:	Alexander Saupp - asaupp(at)gmail(dot)com
# Contributor:	Achim Christ - achim(dot)christ(at)gmail(dot)com
# Version:	1.2.1
# Dependencies:	
#   - IBM Spectrum Archive EE running on Spectrum Scale
#   - jq: json parser (https://stedolan.github.io/jq/)
# Repository: https://github.ibm.com/nils-haustein/check_spectrumarchive
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
#

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
# debug option: if this 1 then the json output is parsed from a file (e.g. ./node_test.json)
DEBUG=0

# path and file name of the admin command line tool for EE
EE_ADM_CMD="/opt/ibm/ltfsee/bin/eeadm"

# specify the path to the jq tool
JQ_TOOL="/usr/local/bin/jq"

# get hostname
HOSTNAME=$(hostname | sed "s/\..*$//" )
NODENAME=$(/usr/lpp/mmfs/bin/mmlsnode -N localhost | cut -d'.' -f1)

# default threshold that throws a WARMING for pool low space
DEFAULT_LOW_SPACE_THRESHOLD=10

# define node states
NODE_WARNING_STATES=(down)
NODE_ERROR_STATES=(error)
NODE_GOOD_STATES=(available)

# define tape states
TAPE_WARNING_STATES=(append_fenced data_full exported offline recall_only need_replace require_replace check_tape_library require_validate check_key_server)
TAPE_ERROR_STATES=(check_hba inaccessible non_supported duplicated missing disconnected unformatted label_mismatch need_unlock)
TAPE_GOOD_STATES=(appendable unassigned full)

# define drive states
DRIVE_WARNING_STATES=(disconnected unassigned not_installed)
DRIVE_ERROR_STATES=(error standby)
DRIVE_GOOD_STATES=(in_use locked mounted mounting not_mounted unmounting)

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
   Check IBM Spectrum Archive EE status (MIT licence)\n
   \n
   usage: $0 [ -s | -n | -t | -d | -p<util> | -a<r|c> -h\n
   \n
   syntax:\n
   \t	-s	\t\t--> Verify IBM Spectrum Archive status\n
   \t	-n	\t\t--> Verify node status\n
   \t   -t  \t\t--> Verify tape states\n
   \t   -d  \t\t--> Verify drive states\n
   \t	-p<util>\t--> Check pool utilization threshold to util\n
   \t	-a<r|c>\t--> Check for running or completed tasks\n
   \t	-h	\t\t--> Print This Help Screen\n
  "
  echo -e $HELP

  if [ "$ERROR" == "" ]; then
    echo -e "\nYou'll probably execute this script via NRPE remotly"
  else
    echo -e "$0 $*"
    echo -e "\n$ERROR"
  fi
  exit 1
}

################################################################################
## Function: in_array
##
## checks if an element ($1) is included in an array ($2) and returns 0 or 1
################################################################################
# checks if an element ($1) is contained in an array ($2)
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
## Main
##
################################################################################

################################################################################
## Check prereqss
##
## Spectrum Archive installed? bc installed?
################################################################################
if [ ! -f $EE_ADM_CMD ] ; then
  echo "ERROR: No IBM Spectrum Archive Installation detected in $EE_PATH"
  exit 1
fi
if [ ! -f $JQ_TOOL ] ; then
  echo "ERROR: utility jq not found, please download and install it in $JQ_TOOL (https://stedolan.github.io/jq/)"
  exit 1
fi


################################################################################
## Check Args
##
## Ensure valid paramters are given
################################################################################
CHECK=""
parm1=""

while getopts 'sntdhp:a:' OPT; do
  case $OPT in
    s)  CHECK="s";;
    n)  CHECK="n";;
    t)  CHECK="t";;
    d)  CHECK="d";;
    p)  CHECK="p"; parm1=$OPTARG;;	# parm1 is utilization threshold
    a)  CHECK="a"; parm1=$OPTARG;;	# parm1 is (r)unning or (c) completed
    h)  error_usage;;
    *)  error_usage "Unknown parameter \"$OPT\"";;
  esac
done

check_ok=0
# Check number of commandline options
if [ $# -eq 0 ] ; then
   check_ok=0
elif [ "$CHECK" == "s" ] && [ $# -eq 1 ] ; then
  check_ok=1
elif [ "$CHECK" == "n" ] && [ $# -eq 1  ] ; then
  check_ok=1
elif [ "$CHECK" == "t" ] && [ $# -eq 1  ] ; then
  check_ok=1
elif [ "$CHECK" == "d" ] && [ $# -eq 1  ] ; then
  check_ok=1
elif [ "$CHECK" == "p" ] && [ $# -eq 2  ] && [ $parm1 != "" ] ; then
  check_ok=1
elif [ "$CHECK" == "a" ] && [ $# -eq 2  ] && [ "$parm1" == "c" ] || [ "$parm1" == "r" ] ; then
  check_ok=1
fi

if [ $check_ok == 0 ] ; then
  error_usage "Wrong parameter(s).."
fi

################################################################################
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

if [ $CHECK == "s" ] ; then
  out=""
  msg=""
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
      # used for degugging different states
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
      if (( $rc == 0 )) ; then
         msg="WARNING: no nodes detected. Run cluster configuration first."
         exitrc=1
      else 
        msg="ERROR: node status not detected, Spectrum Archive is potentially down on this node"
        exitrc=2
      fi
    fi 
  fi
  
  if (( $exitrc > 0 )) ; then
    echo $msg
    exit $exitrc
  fi
  
  # mmm might be running but recalld not
  out=$(ps -ef | grep "dsmrecalld" | grep -v grep)

  if [ -z "$out" ] ; then
    echo "ERROR: Recall daemons are not running on node $NODENAME"
    exit 2
  fi

  # check if /ltfs is mounted
  myarray=$(echo $(df | grep "\/" | awk '{print $6}' ))
  if ( ! in_array "/ltfs" "${myarray[*]}" ) ; then
    echo "ERROR: backend LTFS file system (/ltfs) is not mounted on node $NODENAME"
    exit 2
  fi
  
  # if we did not bail out before, all is good
  if (( $found == 0 )) ; then      
     echo "OK: EE is started and running."
  else 
     echo "OK: EE is started and running on inactive control node"
  fi    
  exit 0
fi

################################################################################
## Check IBM Spectrum Archive EE node state
##
## Verify node state for all nodes
################################################################################
## Sample output - this is what we're going to parse
# eeadm node list -- json
#{ "id": 1,
#  "ip": "9.155.113.43",
#  "hostname": "ltfsee-2",
#  "port": 7600,
#  "enabled": true,
#  "num_of_drives": 2,
#  "library_id": "000001302300_LLC",
#  "library_name": "eelib2",
#  "nodegroup_id": "G0@000001302300_LLC",
#  "nodegroup_name": "G0",
#  "state": "available",
#  "control_node": true,
#  "active_control_node": true }


if [ $CHECK == "n" ] ; then
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
    # used for degugging different states
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

      if ( in_array $state1 "${NODE_ERROR_STATES[*]}" ) ; then
        msg="ERROR: Node ID $id ($state2) is in state: $state1 (control node = $state4, enabled = $state3); "$msg
        exitrc=2
      elif ( in_array $state1 "${NODE_WARNING_STATES[*]}" ) ; then
        msg=$msg"WARNING: Node ID $id ($state2) is in state: $state1 (control node = $state4, enabled = $state3); "
        if (( $exitrc < 2 )) ; then
          exitrc=1
        fi
      elif ( ! in_array $state1 "${NODE_GOOD_STATES[*]}" ) ; then
        msg=$msg"WARNING: Unknow node state: $state1 detected for node $id ($state2, control node = $state4, enabled = $state3); "
        if (( $exitrc < 2 )) ; then
          exitrc=1
        fi
      fi
    done <<< "$(echo -e "$out")"
  else
    if (( $rc == 0 )) ; then
       msg="WARNING: no nodes detected. Run cluster configuration first."
       exitrc=1
    else 
      msg="ERROR: node status not detected, Spectrum Archive is potentially down on this node"
      exitrc=2
    fi

    msg="ERROR: node status not detected, Spectrum Archive is potentially down on this node"
    exitrc=2
  fi

  if (( $exitrc == 0 )) ; then
    echo "OK: Nodes state is GOOD"
    exit 0
  else
    echo "$msg"
    exit $exitrc
  fi
fi

################################################################################
## Check IBM Spectrum Archive EE tape state
##
## Verify tape state for all tapes
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


if [ $CHECK == "t" ] ; then
  msg=""
  out=""
  id=""
  state1=""
  state2=""
  state3=""
  state4=""
  exitrc=0

  if (( $DEBUG == 0 )) ; then
    out=$($EE_ADM_CMD tape list --json |  $JQ_TOOL -r '.payload[] | [.barcode, .state, .pool_name, .library_name, .location_type] | @csv' 2>&1)
    rc=$?
  else
    # used for degugging different states
    out=$(cat ./tape_test.json |  $JQ_TOOL -r '.payload[] | [.barcode, .state, .pool_name, .library_name, .location_type] | @csv' 2>&1)
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

      if ( in_array $state1 "${TAPE_ERROR_STATES[*]}" ) ; then
        msg="ERROR: Tape $id is in state: $state1 (pool=$state2, library=$state3, location=$state4); "$msg
        exitrc=2
      elif ( in_array $state1 "${TAPE_WARNING_STATES[*]}" ) ; then
        msg=$msg"WARNING: Tape $id is in state: $state1 (pool=$state2, library=$state3, location=$state4); "
        if (( $exitrc < 2 )) ; then
          exitrc=1
        fi
      elif ( ! in_array $state1 "${TAPE_GOOD_STATES[*]}" ) ; then
        msg=$msg"WARNING: Unknow tape state: $state1 detected for tape $id (pool=$state2, library=$state3, location=$state4); "
        if (( $exitrc < 2 )) ; then
          exitrc=1
        fi
      fi
    done <<< "$(echo -e "$out")"
  else
    if (( $rc == 0 )) ; then
       msg="WARNING: no tapes detected. Tapes may not yet have been inserted."
       exitrc=1
    else 
      msg="ERROR: tape status not detected, Spectrum Archive is potentially down on this node"
      exitrc=2
    fi
  fi

  if (( $exitrc == 0 )) ; then
    echo "OK: Tape state is GOOD"
    exit 0
  else
    echo "$msg"
    exit $exitrc
  fi
fi

################################################################################
## Check IBM Spectrum Archive EE drive state
##
## Verify drive state for all drives
################################################################################
## Sample output - this is what we're going to parse
# eeadm drive list --json
#{ "id": "1068002839",
#  "state": "not_mounted",
#  "type": "LTO6",
#  "role": "mrg",
#  "library_id": "000001302300_LLC",
#  "library_name": "eelib2",
#  "address": 256,
#  "node_id": 1,
#  "node_hostname": "ltfsee-2",
#  "tape_barcode": "",
#  "nodegroup_name": "G0",
#  "task_id": "" }

if [ $CHECK == "d" ] ; then
  msg=""
  out=""
  id=""
  state1=""
  state2=""
  state3=""
  state4=""
  exitrc=0

  if (( $DEBUG == 0 )) ; then
    out=$($EE_ADM_CMD drive list --json |  $JQ_TOOL -r '.payload[] | [.id, .state, .type, .library_name, .node_hostname] | @csv' 2>&1)
    rc=$?
  else
    # used for degugging different states
    out=$(cat ./drive_test.json | $JQ_TOOL -r '.payload[] | [.id, .state, .type, .library_name, .node_hostname] | @csv' )
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

      if ( in_array $state1 "${DRIVE_ERROR_STATES[*]}" ) ; then
        msg="ERROR: drive $id ($state2) is in state: $state1 (library=$state3, node=$state4); "$msg
        exitrc=2
      elif ( in_array $state1 "${DRIVE_WARNING_STATES[*]}" ) ; then
        msg=$msg"WARNING: drive $id ($state2) is in state: $state1 (library=$state3, node=$state4); "
        if (( $exitrc < 2 )) ; then
          exitrc=1
        fi
      elif ( ! in_array $state1 "${DRIVE_GOOD_STATES[*]}" ) ; then
        msg=$msg"WARNING: Unknown state: $state1 detected for drive $id (type=$state2, library=$state3, node=$state4); "
        if (( $exitrc < 2 )) ; then
          exitrc=1
        fi
      fi
    done <<< "$(echo -e "$out")"
  else
    if (( $rc == 0 )) ; then
       msg="WARNING: no drives detected. Run configuration first."
       exitrc=1
    else 
      msg="ERROR: drive status not detected, Spectrum Archive is potentially down on this node"
      exitrc=2
    fi
  fi

  if (( $exitrc == 0 )) ; then
    echo "OK: Drive state is GOOD"
    exit 0
  else
    echo "$msg"
    exit $exitrc
  fi
fi


################################################################################
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


if [ $CHECK == "p" ] ; then
  msg=""
  out=""
  id=""
  state1=""
  state2=0
  state3=0
  state4=0
  exitrc=0

  if (( $DEBUG == 0 )) ; then
    out=$($EE_ADM_CMD pool list --json |  $JQ_TOOL -r '.payload[] | [.name, .free_space, ."reclaimable%", .low_space_warning_threshold, .capacity] | @csv' 2>&1)
    rc=$?
  else
    # used for degugging different states
    out=$(cat ./pool_test.json |  $JQ_TOOL -r '.payload[] | [.name, .free_space, ."reclaimable%", .low_space_warning_threshold, .capacity] | @csv' 2>&1)
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

      (( threshold = ($state4 * $state3)/100 ))

      if (( $state1 <= $threshold )) ; then
        msg="ERROR: Pool $id is full (free space = $state1, capacity = $state4); "$msg
        exitrc=2
      fi
    
      # check if reclaimable space is <= reclamation threshold 
    
      if (( $state2 >= $parm1 )) ; then
        msg=$msg"WARNING: Pool $id has reached reclamation threshold (reclaimable = $state2 %); "
        if (( $exitrc < 2 )) ; then
          exitrc=1
        fi
      fi
    done <<< "$(echo -e "$out")"
  else
    if (( $rc == 0 )) ; then
       msg="WARNING: no pools detected"
       exitrc=1
    else 
      msg="ERROR: tape status not detected, Spectrum Archive is potentially down on this node"
      exitrc=2
    fi
  fi

  if (( $exitrc == 0 )) ; then
    echo "OK: Pool state is GOOD"
    exit 0
  else
    echo "$msg"
    exit $exitrc
  fi
fi


################################################################################
## Check IBM Spectrum Archive EE task state
##
## Check for running tasks (r)
## Check for failed completed task (c)
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


if [ $CHECK == "a" ] ; then
  msg=""
  out=""
  id=""
  state1=""
  state2=""
  exitrc=0
  i=0

  if (( $DEBUG == 0 )) ; then
    out=$($EE_ADM_CMD task list --json | $JQ_TOOL -r '.payload[] | [.task_id, .type, .status, .result] | @csv' 2>&1)
    rc=$?
  else
    # used for degugging different states
    out=$(cat ./task_test.json | $JQ_TOOL -r '.payload[] | [.task_id, .type, .status, .result] | @csv' 2>&1)
    rc=$?
  fi

  if [[ ! -z $out && $rc == 0 ]] ; then
    if [[ $parm1 == "r" ]]; then
      while read line ; do
        id=$(echo $line | cut -d',' -f1)						# task ID
        state1=$(echo $line | cut -d',' -f2 | cut -d'"' -f2)	# task type
        state2=$(echo $line | cut -d',' -f3 | cut -d'"' -f2)	# status
        
        if [[ $state2 == "running" || $state2 == "waiting" ]] ; then
          msg=$msg"$state1 task (ID $id) is in state: $state2; "
          (( i = i + 1 ))
        fi
      done <<< "$(echo -e "$out")"

      if (( $exitrc == 0 )) ; then
        if [[ ! -z $msg ]] ; then
          echo "OK: $i active task: ($msg)"
        else
          echo "OK: no task running"
        fi
        exit 0
      else
        echo "$msg"
        exit $exitrc
      fi

    elif [[ $parm1 == "c" ]] ; then
      i=$(echo "$out" | grep -E "failed|aborted" | wc -l)
      if (( $i > 0 )) ; then
        echo "WARNING: $i failed task(s), consider to clear the history (eeadm task clearhistory)"
        exit 1
      else
        echo "OK: No failed task(s)"
        exit 0
      fi
    fi
    
  else
    if (( $rc == 0 )) ; then
       echo "WARNING: no task detected."
       exit 1
    else
      echo "ERROR: task status not detected, Spectrum Archive is potentially down on this node"
      exit 2
    fi
  fi

fi


################################################################################
## This point should never be reached, because we exit earlier
##
################################################################################

echo "WARNING: Run away code - you should never see this (Parameters: $1 $2 $3)"
exit 1
