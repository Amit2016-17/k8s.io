#!/usr/bin/env bash

# Copyright 2019 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# This runs as you.  It assumes you have built an image named ${USER}/octodns.

# Pushes config to zones.
#   args: args to pass to octodns (e.g. --doit, --force, a list of zones)
push () {
    docker run -ti \
        -u `id -u` \
        -v ~/.config/gcloud:/.config/gcloud:ro \
        -v `pwd`/octodns-config.yaml:/octodns/config.yaml:ro \
        -v `pwd`/zone-configs:/octodns/config:ro \
        ${USER}/octodns \
        octodns-sync \
            --config-file=/octodns/config.yaml \
            --log-stream-stdout \
            --debug \
            "$@"
}

# Assumes to be running in a checked-out git repo directory, and in the same
# subdirectory as this file.
if [ ! -f octodns-config.yaml -o ! -d zone-configs ]; then
    echo "CWD does not appear to have the configs needed: $(pwd)"
    exit 1
fi

# Push to canaries.
echo "Dry-run to canary zones"
push canary.k8s.io. canary.kubernetes.io. canary.x-k8s.io. canary.k8s-e2e.com. > log.canary 2>&1
if [ $? != 0 ]; then
    echo "Canary dry-run FAILED, halting; log follows:"
    echo "========================================="
    cat log.canary
    exit 2
fi
echo "Pushing to canary zones"
push --doit canary.k8s.io. canary.kubernetes.io. canary.x-k8s.io. canary.k8s-e2e.com. >> log.canary 2>&1
if [ $? != 0 ]; then
    echo "Canary push FAILED, halting; log follows:"
    echo "========================================="
    cat log.canary
    exit 2
fi
echo "Canary push SUCCEEDED"

for zone in canary.k8s.io. canary.kubernetes.io. canary.x-k8s.io. canary.k8s-e2e.com.; do
    TRIES=12
    echo "Testing canary zone: $zone"
    for i in $(seq 1 "$TRIES"); do
        ./check-zone.sh "$zone" >> log.canary 2>&1
        if [ $? == 0 ]; then
            break
        fi
        if [ $i != "$TRIES" ]; then
            echo "  test failed, might be propagation delay, will retry..."
            sleep 10
        else
            echo "Canary test FAILED, halting; log follows:"
            echo "========================================="
            cat log.canary
            exit 2
        fi
    done
    echo "Canary $zone SUCCEEDED"
done

# Push to prod.
echo "Dry-run to prod zones"
push k8s.io. kubernetes.io. x-k8s.io. k8s-e2e.com. > log.prod 2>&1
if [ $? != 0 ]; then
    echo "Prod dry-run FAILED, halting; log follows:"
    echo "========================================="
    cat log.prod
    exit 3
fi

echo "Pushing to prod zones"
push --doit k8s.io. kubernetes.io. x-k8s.io. k8s-e2e.com. >> log.prod 2>&1
if [ $? != 0 ]; then
    echo "Prod push FAILED, halting; log follows:"
    echo "========================================="
    cat log.prod
    exit 3
fi
echo "Prod push SUCCEEDED"

for zone in k8s.io. kubernetes.io. x-k8s.io. k8s-e2e.com.; do
    TRIES=12
    echo "Testing prod zone: $zone"
    for i in $(seq 1 "$TRIES"); do
        ./check-zone.sh "$zone" >> log.prod 2>&1
        if [ $? == 0 ]; then
            break
        fi
        if [ $i != "$TRIES" ]; then
            echo "  test failed, might be propagation delay, will retry..."
            sleep 10
        else
            echo "Prod test FAILED, halting; log follows:"
            echo "========================================="
            cat log.prod
            exit 2
        fi
    done
    echo "Prod $zone SUCCEEDED"
done
