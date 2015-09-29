#!/usr/bin/env bash
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


add_test_type asflicense
add_test asflicense

## @description  Verify all files have an Apache License
## @audience     private
## @stability    evolving
## @replaceable  no
## @return       0 on success
## @return       1 on failure
function asflicense_tests
{
  local numpatch
  local btfails=true

  big_console_header "Determining number of patched ASF License errors"

  start_clock

  personality_modules patch asflicense
  case ${BUILDTOOL} in
    ant)
      modules_workers patch asflicense releaseaudit
    ;;
    gradle)
      btfails=false
      modules_workers patch asflicense rat
    ;;
    maven)
      modules_workers patch asflicense apache-rat:check
    ;;
    *)
      return 0
    ;;
  esac

  # RAT fails the build if there are license problems.
  # so let's take advantage of that a bit.
  if [[ $? == 0 && ${btfails} = true ]]; then
    add_vote_table 1 asflicense "Patch does not generate ASF License warnings."
    return 0
  fi

  #shellcheck disable=SC2038
  find "${BASEDIR}" -name rat.txt \
        -o -name releaseaudit_report.txt \
        -o -name rat-report.txt \
    | xargs cat > "${PATCH_DIR}/patch-asflicense.txt"

  if [[ ! -s "${PATCH_DIR}/patch-asflicense.txt" ]]; then
    if [[ ${btfails} = true ]]; then
      # if we're here, then build actually failed
      modules_messages patch asflicense true
    else
      add_vote_table 0 asflicense "ASF License check generated no output?"
      return 0
    fi
  fi

  numpatch=$("${GREP}" -c '\!?????' "${PATCH_DIR}/patch-asflicense.txt")
  echo ""
  echo ""
  echo "There appear to be ${numpatch} ASF License warnings after applying the patch."
  if [[ -n ${numpatch}
     && ${numpatch} -gt 0 ]] ; then
    add_vote_table -1 asflicense "Patch generated ${numpatch} ASF License warnings."

    echo "Lines that start with ????? in the ASF License "\
        "report indicate files that do not have an Apache license header:" \
          > "${PATCH_DIR}/patch-asflicense-problems.txt"

    ${GREP} '\!?????' "${PATCH_DIR}/patch-asflicense.txt" \
    >>  "${PATCH_DIR}/patch-asflicense-problems.txt"

    add_footer_table asflicense "@@BASE@@/patch-asflicense-problems.txt"
    return 1
  fi
  add_vote_table 1 asflicense "Patch does not generate ASF License warnings."
  return 0
}
