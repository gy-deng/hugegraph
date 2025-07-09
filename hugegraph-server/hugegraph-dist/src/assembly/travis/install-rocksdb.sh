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
    fi

    if ! mkdir -p "$dest_dir"; then
      echo "Cannot mkdir '$dest_dir'" >&2
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

function install_dependency() {
  # fix 24.04. see https://askubuntu.com/questions/1512196/libaio1-on-noble/1512197#1512197
  sudo ln -s /usr/lib/x86_64-linux-gnu/libaio.so.1t64 /usr/lib/x86_64-linux-gnu/libaio.so.1
}

function preload_toplingdb() {
  local jar_file=$(find $LIB -name "rocksdbjni*.jar")
  local dest_dir=$LIBRARY

  install_dependency
  extract_so_with_jar $jar_file $dest_dir
  export LD_LIBRARY_PATH=$dest_dir:$LD_LIBRARY_PATH
  ldd $dest_dir/librocksdbjni-linux64.so
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
