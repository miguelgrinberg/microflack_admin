#!/bin/bash -e

# This script installs all the requireed dependencies on a host, which is
# assumed to be Ubuntu 16.04.

# install system dependencies
apt-get update -y
apt-get install -y python3 python3-pip python3-venv build-essential pwgen mysql-client
pip3 install --upgrade pip wheel

# install docker
curl -fsSL https://get.docker.com/ | sh
usermod -aG docker vagrant
