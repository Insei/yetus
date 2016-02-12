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

# Override these to match Apache Hadoop's requirements

personality_plugins "all,-ant,-gradle,-scalac,-scaladoc"

function personality_globals
{
  #shellcheck disable=SC2034
  PATCH_BRANCH_DEFAULT=trunk
  #shellcheck disable=SC2034
  PATCH_NAMING_RULE="https://wiki.apache.org/hadoop/HowToContribute"
  #shellcheck disable=SC2034
  JIRA_ISSUE_RE='^(HADOOP|YARN|MAPREDUCE|HDFS)-[0-9]+$'
  #shellcheck disable=SC2034
  GITHUB_REPO="apache/hadoop"
  #shellcheck disable=SC2034
  PYLINT_OPTIONS="--indent-string='  '"
}

function hadoop_order
{
  declare ordering=$1
  declare hadoopm

  if [[ ${ordering} = normal ]]; then
    hadoopm=${CHANGED_MODULES}
  elif  [[ ${ordering} = union ]]; then
    hadoopm=${CHANGED_UNION_MODULES}
  else
    hadoopm="${ordering}"
  fi
  echo "${hadoopm}"
}

function hadoop_unittest_prereqs
{
  declare input=$1
  declare mods
  declare need_common=0
  declare building_common=0
  declare module
  declare flags
  declare fn

  # prior to running unit tests, hdfs needs libhadoop.so built
  # if we're building root, then this extra work is moot

  #shellcheck disable=SC2086
  mods=$(hadoop_order ${input})

  for module in ${mods}; do
    if [[ ${module} = hadoop-hdfs-project* ]]; then
      need_common=1
    elif [[ ${module} = hadoop-common-project/hadoop-common
      || ${module} = hadoop-common-project ]]; then
      building_common=1
    elif [[ ${module} = . ]]; then
      return
    fi
  done

  if [[ ${need_common} -eq 1
      && ${building_common} -eq 0 ]]; then
    echo "unit test pre-reqs:"
    module="hadoop-common-project/hadoop-common"
    fn=$(module_file_fragment "${module}")
    flags=$(hadoop_native_flags)
    pushd "${BASEDIR}/${module}" >/dev/null
    # shellcheck disable=SC2086
    echo_and_redirect "${PATCH_DIR}/maven-unit-prereq-${fn}-install.txt" \
      "${MAVEN}" "${MAVEN_ARGS[@]}" install -DskipTests ${flags}
    popd >/dev/null
  fi
}

function hadoop_native_flags
{

  if [[ ${BUILD_NATIVE} != true ]]; then
    return
  fi

  # Based upon HADOOP-11937
  #
  # Some notes:
  #
  # - getting fuse to compile on anything but Linux
  #   is always tricky.
  # - Darwin assumes homebrew is in use.
  # - HADOOP-12027 required for bzip2 on OS X.
  # - bzip2 is broken in lots of places.
  #   e.g, HADOOP-12027 for OS X. so no -Drequire.bzip2
  #

  case ${OSTYPE} in
    Linux)
      # shellcheck disable=SC2086
      echo -Pnative -Drequire.libwebhdfs \
        -Drequire.snappy -Drequire.openssl -Drequire.fuse \
        -Drequire.test.libhadoop
    ;;
    Darwin)
      JANSSON_INCLUDE_DIR=/usr/local/opt/jansson/include
      JANSSON_LIBRARY=/usr/local/opt/jansson/lib
      export JANSSON_LIBRARY JANSSON_INCLUDE_DIR
      # shellcheck disable=SC2086
      echo \
      -Pnative -Drequire.snappy  \
      -Drequire.openssl \
        -Dopenssl.prefix=/usr/local/opt/openssl/ \
        -Dopenssl.include=/usr/local/opt/openssl/include \
        -Dopenssl.lib=/usr/local/opt/openssl/lib \
      -Drequire.libwebhdfs -Drequire.test.libhadoop
    ;;
    *)
      # shellcheck disable=SC2086
      echo \
        -Pnative \
        -Drequire.snappy -Drequire.openssl \
        -Drequire.test.libhadoop
    ;;
  esac
}

function personality_modules
{
  declare repostatus=$1
  declare testtype=$2
  declare extra=""
  declare ordering="normal"
  declare needflags=false
  declare flags
  declare fn
  declare i
  declare hadoopm

  yetus_debug "Personality: ${repostatus} ${testtype}"

  clear_personality_queue

  case ${testtype} in
    asflicense)
      # this is very fast and provides the full path if we do it from
      # the root of the source
      personality_enqueue_module .
      return
    ;;
    checkstyle)
      ordering="union"
      extra="-DskipTests"
    ;;
    compile)
      ordering="union"
      extra="-DskipTests"
      needflags=true

      # if something in common changed, we build the whole world
      if [[ ${CHANGED_MODULES} =~ hadoop-common ]]; then
        yetus_debug "hadoop personality: javac + hadoop-common = ordering set to . "
        ordering="."
      fi
    ;;
    distclean)
      ordering="."
      extra="-DskipTests"
    ;;
    javadoc)
      if [[ "${CHANGED_MODULES}" =~ \. ]]; then
        ordering=.
      fi

      if [[ ${repostatus} = patch ]]; then
        echo "javadoc pre-reqs:"
        for i in hadoop-project \
          hadoop-common-project/hadoop-annotations; do
            fn=$(module_file_fragment "${i}")
            pushd "${BASEDIR}/${i}" >/dev/null
            echo "cd ${i}"
            echo_and_redirect "${PATCH_DIR}/maven-${fn}-install.txt" \
              "${MAVEN}" "${MAVEN_ARGS[@]}" install
            popd >/dev/null
        done
      fi
      extra="-Pdocs -DskipTests"
    ;;
    mvneclipse)
      if [[ "${CHANGED_MODULES}" =~ \. ]]; then
        ordering=.
      fi
    ;;
    mvninstall)
      extra="-DskipTests"
      if [[ ${repostatus} = branch ]]; then
        ordering=.
      fi
    ;;
    mvnsite)
      if [[ "${CHANGED_MODULES}" =~ \. ]]; then
        ordering=.
      fi
    ;;
    unit)
      if [[ "${CHANGED_MODULES}" =~ \. ]]; then
        ordering=.
      fi

      if [[ ${TEST_PARALLEL} = "true" ]] ; then
        extra="-Pparallel-tests"
        if [[ -n ${TEST_THREADS:-} ]]; then
          extra="${extra} -DtestsThreadCount=${TEST_THREADS}"
        fi
      fi
      needflags=true
      hadoop_unittest_prereqs "${ordering}"

      verify_needed_test javac
      if [[ $? == 0 ]]; then
        yetus_debug "hadoop: javac not requested"
        verify_needed_test native
        if [[ $? == 0 ]]; then
          yetus_debug "hadoop: native not requested"
          yetus_debug "hadoop: adding -DskipTests to unit test"
          extra="-DskipTests"
        fi
      fi

      verify_needed_test shellcheck
      if [[ $? == 0
          && ! ${CHANGED_FILES} =~ \.bats ]]; then
        yetus_debug "hadoop: NO shell code change detected; disabling shelltest profile"
        extra="${extra} -P!shelltest"
      else
        extra="${extra} -Pshelltest"
      fi
    ;;
    *)
      extra="-DskipTests"
    ;;
  esac

  if [[ ${needflags} = true ]]; then
    flags=$(hadoop_native_flags)
    extra="${extra} ${flags}"
  fi

  extra="-Ptest-patch ${extra}"

  for module in $(hadoop_order ${ordering}); do
    # shellcheck disable=SC2086
    personality_enqueue_module ${module} ${extra}
  done
}

function personality_file_tests
{
  declare filename=$1

  yetus_debug "Using Hadoop-specific personality_file_tests"

  if [[ ${filename} =~ src/main/webapp ]]; then
    yetus_debug "tests/webapp: ${filename}"
  elif [[ ${filename} =~ \.sh
       || ${filename} =~ \.cmd
       || ${filename} =~ src/scripts
       || ${filename} =~ src/test/scripts
       || ${filename} =~ src/main/bin
       || ${filename} =~ shellprofile\.d
       || ${filename} =~ src/main/conf
       ]]; then
    yetus_debug "tests/shell: ${filename}"
    add_test mvnsite
    add_test unit
  elif [[ ${filename} =~ \.md$
       || ${filename} =~ \.md\.vm$
       || ${filename} =~ src/site
       ]]; then
    yetus_debug "tests/site: ${filename}"
    add_test mvnsite
  elif [[ ${filename} =~ \.c$
       || ${filename} =~ \.cc$
       || ${filename} =~ \.h$
       || ${filename} =~ \.hh$
       || ${filename} =~ \.proto$
       || ${filename} =~ \.cmake$
       || ${filename} =~ CMakeLists.txt
       ]]; then
    yetus_debug "tests/units: ${filename}"
    add_test compile
    add_test cc
    add_test mvnsite
    add_test javac
    add_test unit
  elif [[ ${filename} =~ build.xml$
       || ${filename} =~ pom.xml$
       || ${filename} =~ \.java$
       || ${filename} =~ src/main
       ]]; then
      yetus_debug "tests/javadoc+units: ${filename}"
      add_test compile
      add_test javac
      add_test javadoc
      add_test mvninstall
      add_test mvnsite
      add_test unit
  fi

  if [[ ${filename} =~ src/test ]]; then
    yetus_debug "tests: src/test"
    add_test unit
  fi

  if [[ ${filename} =~ \.java$ ]]; then
    add_test findbugs
  fi
}

function hadoop_console_success
{
  printf "IF9fX19fX19fX18gCjwgU3VjY2VzcyEgPgogLS0tLS0tLS0tLSAKIFwgICAg";
  printf "IC9cICBfX18gIC9cCiAgXCAgIC8vIFwvICAgXC8gXFwKICAgICAoKCAgICBP";
  printf "IE8gICAgKSkKICAgICAgXFwgLyAgICAgXCAvLwogICAgICAgXC8gIHwgfCAg";
  printf "XC8gCiAgICAgICAgfCAgfCB8ICB8ICAKICAgICAgICB8ICB8IHwgIHwgIAog";
  printf "ICAgICAgIHwgICBvICAgfCAgCiAgICAgICAgfCB8ICAgfCB8ICAKICAgICAg";
  printf "ICB8bXwgICB8bXwgIAo"
}
