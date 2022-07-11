#! /bin/bash
imagename=nhp-abcd-bids-pipeline
datestamp=$( date +%Y%m%d )
tarfile=${imagename}_${datestamp}.tar

pushd /mnt/max/shared/code/internal/utilities/dcan-stack_dockerfiles/${imagename}
docker build . -t dcanlabs/${imagename}
popd

pushd /mnt/max/shared/code/internal/utilities/docker_images
docker save -o ${tarfile} dcanlabs/${imagename}:latest
chmod g+rw ${tarfile}
gzip ${tarfile}
popd
