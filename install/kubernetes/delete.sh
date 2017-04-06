#!/bin/bash -e

# This script deletes all the resources associated with a MicroFlack kubernetes
# deployment.

KUBECTL=$(which kubectl || true)
if [[ "$KUBECTL" == "" ]]; then
    echo Please install and configure kubectl for your cluster.
    exit 1
fi

$KUBECTL delete --ignore-not-found=true service ui users tokens messages socketio redis mysql lb etcd0 etcd1 etcd2 etcd-client
$KUBECTL delete --ignore-not-found=true deployment ui users tokens messages socketio redis mysql lb
$KUBECTL delete --ignore-not-found=true pod etcd0 etcd1 etcd2
$KUBECTL delete --ignore-not-found=true pvc mysql-pv-claim
$KUBECTL delete --ignore-not-found=true pv mysql-pv
$KUBECTL delete --ignore-not-found=true secret app mysql

echo MicroFlack has been removed.
