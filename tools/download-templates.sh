#!/bin/bash

# get the root project directory
PROJECT_DIR=$(dirname $(realpath $(dirname ${BASH_SOURCE[0]})))
# if a templates folder already exists, remove it
[ -d ${PROJECT_DIR}/scripts/dcan_macaque_pipeline/global/templates ] && \
    rm -rf ${PROJECT_DIR}/scripts/dcan_macaque_pipeline/global/templates
# download templates to global
curl -L https://wustl.box.com/shared/static/jnpz4ibgttwoeyz1bxyavrn8y4rgh37o.gz \
    -o ${PROJECT_DIR}/scripts/dcan_macaque_pipeline/global/templates.tar.gz
# unpack the files
tar -xvf ${PROJECT_DIR}/scripts/dcan_macaque_pipeline/global/templates.tar.gz \
    -C ${PROJECT_DIR}/scripts/dcan_macaque_pipeline/global/
# remove the tar file
rm ${PROJECT_DIR}/scripts/dcan_macaque_pipeline/global/templates.tar.gz
