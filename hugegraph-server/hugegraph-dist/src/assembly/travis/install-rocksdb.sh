#!/bin/bash
#
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
#

function abs_path() {
    SOURCE="${BASH_SOURCE[0]}"
    while [[ -h "$SOURCE" ]]; do
        DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
        SOURCE="$(readlink "$SOURCE")"
        [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
    done
    cd -P "$(dirname "$SOURCE")" && pwd
}

function extract_so_with_jar() {
    local jar_file="$1"
    local dest_dir="$2"
    local abs_jar_path
    local pipeline_status

    if [ ! -f "$jar_file" ]; then
      echo "'$jar_file' Not Exist" >&2
      exit 1
    fi

    if ! mkdir -p "$dest_dir"; then
      echo "Cannot mkdir '$dest_dir'" >&2
      exit 1
    fi

    if [[ "$jar_file" == /* ]]; then
      abs_jar_path="$jar_file"
    else
      abs_jar_path="$(pwd)/$jar_file"
    fi

    (cd "$dest_dir" && jar tf "$abs_jar_path" | grep '\.so$' | xargs jar xf "$abs_jar_path")
    pipeline_status=$?

    if [ $pipeline_status -ne 0 ]; then
      echo "(Error: $pipeline_status)" >&2
    fi
}

download_and_verify() {
    local url=$1
    local filepath=$2
    local expected_md5=$3

    if [[ -f $filepath ]]; then
        echo "File $filepath exists. Verifying MD5 checksum..."
        actual_md5=$(md5sum $filepath | awk '{ print $1 }')
        if [[ $actual_md5 != $expected_md5 ]]; then
            echo "MD5 checksum verification failed for $filepath. Expected: $expected_md5, but got: $actual_md5"
            echo "Deleting $filepath..."
            rm -f $filepath
        else
            echo "MD5 checksum verification succeeded for $filepath."
            return 0
        fi
    fi

    echo "Downloading $filepath..."
    curl -L -o $filepath $url

    actual_md5=$(md5sum $filepath | awk '{ print $1 }')
    if [[ $actual_md5 != $expected_md5 ]]; then
        echo "MD5 checksum verification failed for $filepath after download. Expected: $expected_md5, but got: $actual_md5"
        return 1
    fi

    return 0
}

function get_libjemalloc() {
  arch=$(uname -m)
  mkdir -p "$LIBRARY"
  if [[ $arch == "aarch64" || $arch == "arm64" ]]; then
      lib_file="$LIBRARY/libjemalloc_aarch64.so"
      download_url="${GITHUB}/apache/hugegraph-doc/raw/binary-1.5/dist/server/libjemalloc_aarch64.so"
      expected_md5="2a631d2f81837f9d5864586761c5e380"
      if download_and_verify $download_url $lib_file $expected_md5; then
          :
      else
          echo "Failed to verify or download $lib_file, skip it"
      fi
  elif [[ $arch == "x86_64" ]]; then
      lib_file="$LIBRARY/libjemalloc.so"
      download_url="${GITHUB}/apache/hugegraph-doc/raw/binary-1.5/dist/server/libjemalloc.so"
      expected_md5="fd61765eec3bfea961b646c269f298df"
      if download_and_verify $download_url $lib_file $expected_md5; then
          :
      else
          echo "Failed to verify or download $lib_file, skip it"
      fi
  else
      echo "Unsupported architecture: $arch"
  fi
}

function preload_toplingdb() {
  local jar_file=$(find $LIB -name "rocksdbjni*.jar")
  local dest_dir=$LIBRARY

  get_libjemalloc
  extract_so_with_jar $jar_file $dest_dir
  ldd $dest_dir/librocksdbjni-linux64.so
  export LD_LIBRARY_PATH=$dest_dir:$LD_LIBRARY_PATH
  export LD_PRELOAD=libjemalloc.so:librocksdbjni-linux64.so
}

TRAVIS_DIR=$(dirname $0)
VERSION=$(mvn help:evaluate -Dexpression=project.version -q -DforceStdout)
SERVER_DIR=hugegraph-server/apache-hugegraph-server-incubating-$VERSION
BIN=$SERVER_DIR/bin
LIB=$SERVER_DIR/lib
CONF=$SERVER_DIR/conf
DB_CONF=$CONF/graphs/db_bench_community.yaml
LIBRARY=$SERVER_DIR/library
GITHUB="https://github.com"

preload_toplingdb

cp $DB_CONF .
