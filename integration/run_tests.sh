#!/bin/bash

# Copyright (c) 2015-2017 Snowplow Analytics Ltd. All rights reserved.
#
# This program is licensed to you under the Apache License Version 2.0,
# and you may not use this file except in compliance with the Apache License Version 2.0.
# You may obtain a copy of the Apache License Version 2.0 at http://www.apache.org/licenses/LICENSE-2.0.
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the Apache License Version 2.0 is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the Apache License Version 2.0 for the specific language governing permissions and limitations there under.

set -e



# -----------------------------------------------------------------------------
#  CONSTANTS
# -----------------------------------------------------------------------------

root=${TRAVIS_BUILD_DIR}
consul_server_uri=localhost:8500
root_key=${root}/integration/resources
assert_counter=0



# -----------------------------------------------------------------------------
#  FUNCTIONS & PROCEDURES
# -----------------------------------------------------------------------------

# Similar to Perl die
function die() {
   echo "$@" 1>&2 ; exit 1;
}

# Is passed an exit code and a command and
# will then assert that the exit code matches.
#
# Parameters:
# 1. exit_code
# 2. command
function assert_ExitCodeForCommand() {
   [ "$#" -eq 2 ] || die "2 arguments required, $# provided"
   local __exit_code="$1"
   local __command="$2"
   let "assert_counter+=1"

   printf "RUNNING: Assertion ${assert_counter}:\n - ${__command}\n\n"

   set +e
   eval ${__command}
   retval=`echo $?`
   set -e

   if [ ${retval} -eq ${__exit_code} ] ; then
      printf "\nSUCCESS: Test finished with exit code ${__exit_code}\n\n"
   else
      printf "\nFAIL: Expected exit code ${__exit_code} got ${retval}\n\n"
      exit 1
   fi
}

# Is passed a line of output and a command and
# will then assert that the line is printed in the command output.
#
# Parameters:
# 1. array of things to search in one line (input as string separated by spaces)
# 2. command
function assert_OutputForCommand() {
   [ "$#" -eq 2 ] || die "2 arguments required, $# provided"
   local __line="$1"
   local __command="$2"

   read -ra terms <<<"${__line}"
   let "assert_counter+=1"

   printf "RUNNING: Assertion ${assert_counter}:\n - ${__command}\n\n"

   set +e
   output=$(eval "${__command} 2>&1")
   retval=`echo $?`
   set -e

   declare -i numterms=${#terms[@]}
   declare -i found=0
   declare -i success=0

   while read -r line; do
      set +e
      echo $line | grep -q "QUERY"
      if [ "$?"  -eq 0 ]; then
         echo $line | grep -q '\[]'
         if [ "$?"  -eq 1 ]; then
            echo $line | grep -q "No output returned"
            if [ "$?"  -eq 1 ]; then
               trimmedline=$(echo $line | grep -o 'QUERY OUTPUT:.*')
               values=`echo $trimmedline | awk -F '[][]' '{print $2}'`
            else
               continue
            fi
         else
            continue
         fi
      else
         continue
      fi
      set -e
      found=0
      read -ra queryterms <<<"$values"

      for term in "${terms[@]}"
      do
         if echo "${queryterms[@]}" | grep -q -w "$term"; then 
            (( found+=1 ))
         fi
      done

      if [ "$found" -eq "$numterms" ]; then
         (( success=1 ))
         break
      fi
   done <<< "$output"

   if [ "$success" -eq 1 ] ; then
      printf "\nSUCCESS: Test finished with line present: ${__line}\n\n"
   else
      printf "\nFAIL: Expected line ${__line}\n\n"
      exit 1
   fi
}


# -----------------------------------------------------------------------------
#  TEST EXECUTION
# -----------------------------------------------------------------------------

cd ${root}

printf "==========================================================\n"
printf " RUNNING INTEGRATION TESTS\n"
printf "==========================================================\n\n"

# Test: Invalid playbook should return exit code 7
assert_ExitCodeForCommand "7" "${root}/sql-runner -playbook ${root_key}/bad-mixed.yml"

# Test: Valid playbook with invalid query should return exit code 6
assert_ExitCodeForCommand "6" "${root}/sql-runner -playbook ${root_key}/good-postgres.yml -var test_date=`date "+%Y_%m_%d"`"

# Test: Valid playbook which attempts to lock but fails should return exit code 1
assert_ExitCodeForCommand "1" "${root}/sql-runner -playbook ${root_key}/good-postgres.yml -var test_date=`date "+%Y_%m_%d"` -fromStep \"Create schema and table\" -lock ${root}/dist/locks/integration/1"
assert_ExitCodeForCommand "1" "${root}/sql-runner -playbook ${root_key}/good-postgres.yml -var test_date=`date "+%Y_%m_%d"` -fromStep \"Create schema and table\" -lock /locks/integration/1 -consul ${consul_server_uri}"
assert_ExitCodeForCommand "1" "${root}/sql-runner -playbook ${root_key}/good-postgres.yml -var test_date=`date "+%Y_%m_%d"` -fromStep \"Create schema and table\" -softLock ${root}/dist/locks/integration/1"
assert_ExitCodeForCommand "1" "${root}/sql-runner -playbook ${root_key}/good-postgres.yml -var test_date=`date "+%Y_%m_%d"` -fromStep \"Create schema and table\" -softLock /locks/integration/1 -consul ${consul_server_uri}"

# Test: Checking for a lock that does not exist should return exit code 0
assert_ExitCodeForCommand "0" "${root}/sql-runner -checkLock ${root}/dist/locks/integration/1"
assert_ExitCodeForCommand "0" "${root}/sql-runner -checkLock locks/integration/1 -consul ${consul_server_uri}"

# Test: Deleting a lock which does not exist should return exit code 1
assert_ExitCodeForCommand "1" "${root}/sql-runner -deleteLock ${root}/dist/locks/integration/1"
assert_ExitCodeForCommand "1" "${root}/sql-runner -deleteLock locks/integration/1 -consul ${consul_server_uri}"

# Test: Valid playbook which creates a hard-lock and then fails SHOULD leave the lock around afterwards
assert_ExitCodeForCommand "6" "${root}/sql-runner -playbook ${root_key}/good-postgres.yml -var test_date=`date "+%Y_%m_%d"` -lock locks/integration/1 -consul ${consul_server_uri}"
assert_ExitCodeForCommand "3" "${root}/sql-runner -playbook ${root_key}/good-postgres.yml -var test_date=`date "+%Y_%m_%d"` -lock locks/integration/1 -consul ${consul_server_uri}"
assert_ExitCodeForCommand "3" "${root}/sql-runner -checkLock locks/integration/1 -consul ${consul_server_uri}"
assert_ExitCodeForCommand "0" "${root}/sql-runner -deleteLock locks/integration/1 -consul ${consul_server_uri}"
assert_ExitCodeForCommand "6" "${root}/sql-runner -playbook ${root_key}/good-postgres.yml -var test_date=`date "+%Y_%m_%d"` -lock ${root}/dist/integration-lock"
assert_ExitCodeForCommand "3" "${root}/sql-runner -playbook ${root_key}/good-postgres.yml -var test_date=`date "+%Y_%m_%d"` -lock ${root}/dist/integration-lock"
assert_ExitCodeForCommand "3" "${root}/sql-runner -checkLock ${root}/dist/integration-lock"
assert_ExitCodeForCommand "0" "${root}/sql-runner -deleteLock ${root}/dist/integration-lock"

# Test: Valid playbook which creates a soft-lock and then fails SHOULD NOT leave the lock around afterwards
assert_ExitCodeForCommand "6" "${root}/sql-runner -playbook ${root_key}/good-postgres.yml -var test_date=`date "+%Y_%m_%d"` -softLock locks/integration/1 -consul ${consul_server_uri}"
assert_ExitCodeForCommand "0" "${root}/sql-runner -checkLock locks/integration/1 -consul ${consul_server_uri}"
assert_ExitCodeForCommand "1" "${root}/sql-runner -deleteLock locks/integration/1 -consul ${consul_server_uri}"
assert_ExitCodeForCommand "6" "${root}/sql-runner -playbook ${root_key}/good-postgres.yml -var test_date=`date "+%Y_%m_%d"` -softLock ${root}/dist/integration-lock"
assert_ExitCodeForCommand "0" "${root}/sql-runner -checkLock ${root}/dist/integration-lock"
assert_ExitCodeForCommand "1" "${root}/sql-runner -deleteLock ${root}/dist/integration-lock"

# Assertion 25
# Test: Valid playbook which creates a hard/soft-lock and then succeeds SHOULD NOT leave the lock around afterwards
assert_ExitCodeForCommand "0" "${root}/sql-runner -playbook ${root_key}/good-postgres.yml -var test_date=`date "+%Y_%m_%d"` -fromStep \"Create schema and table\" -lock locks/integration/1 -consul ${consul_server_uri}"
assert_ExitCodeForCommand "0" "${root}/sql-runner -checkLock locks/integration/1 -consul ${consul_server_uri}"
assert_ExitCodeForCommand "0" "${root}/sql-runner -playbook ${root_key}/good-postgres.yml -var test_date=`date "+%Y_%m_%d"` -fromStep \"Create schema and table\" -lock ${root}/dist/integration-lock"
assert_ExitCodeForCommand "0" "${root}/sql-runner -checkLock ${root}/dist/integration-lock"
assert_ExitCodeForCommand "0" "${root}/sql-runner -playbook ${root_key}/good-postgres.yml -var test_date=`date "+%Y_%m_%d"` -fromStep \"Create schema and table\" -softLock locks/integration/1 -consul ${consul_server_uri}"
assert_ExitCodeForCommand "0" "${root}/sql-runner -checkLock locks/integration/1 -consul ${consul_server_uri}"
assert_ExitCodeForCommand "0" "${root}/sql-runner -playbook ${root_key}/good-postgres.yml -var test_date=`date "+%Y_%m_%d"` -fromStep \"Create schema and table\" -softLock ${root}/dist/integration-lock"
assert_ExitCodeForCommand "0" "${root}/sql-runner -checkLock ${root}/dist/integration-lock"

# Test: Invalid playbook which creates a hard/soft-lock but is run using -dryRun should return exit code 0
assert_ExitCodeForCommand "5" "${root}/sql-runner -playbook ${root_key}/bad-mixed.yml -lock ${root}/dist/integration-lock -dryRun"
assert_ExitCodeForCommand "0" "${root}/sql-runner -playbook ${root_key}/good-postgres.yml -var test_date=`date "+%Y_%m_%d"` -lock ${root}/dist/integration-lock -dryRun"

# Test: Valid playbook outputs proper results from playbooks using -dropOutput
assert_ExitCodeForCommand "6" "${root}/sql-runner -dropOutput -playbook ${root_key}/good-postgres.yml"
assert_OutputForCommand "25 32 18" "${root}/sql-runner -dropOutput -playbook ${root_key}/good-postgres.yml -var test_date=`date "+%Y_%m_%d"` -fromStep \"Create schema and table\""

# Test: Valid playbook which uses playbook template variables
assert_ExitCodeForCommand "6" "${root}/sql-runner -playbook ${root_key}/good-postgres-with-template.yml -var password=,host=localhost"
assert_ExitCodeForCommand "6" "${root}/sql-runner -playbook ${root_key}/good-postgres-with-template.yml"
assert_ExitCodeForCommand "0" "${root}/sql-runner -playbook ${root_key}/good-postgres-with-template.yml -var username=postgres,password=,host=localhost"

printf "==========================================================\n"
printf " INTEGRATION TESTS SUCCESSFUL\n"
printf "==========================================================\n"
