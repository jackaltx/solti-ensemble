#!/bin/bash

# This allows you to download the git repository and "fake" installing the collection.
# You cannot use this for testing, but it is handy for development as 
# changed are pushed out real-time.

# This assumes you did not change the location in your running ansible.cfg
# Create the ansible collections directory structure if it doesn't exist
mkdir -p ~/.ansible/collections/ansible_collections/jackaltx

# Create the symlink
ln -s $(pwd) ~/.ansible/collections/ansible_collections/jackaltx/solti_ensemble
