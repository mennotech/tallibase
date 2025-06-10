#!/bin/sh

REV_TAG=$(git log -1 --pretty=format:%h)
docker build -t tallibase:latest -ttallibase:$REV_TAG .

# nominate the tagged image for deployment
docker tag tallibase:$REV_TAG mennotech/tallibase:$REV_TAG
docker tag tallibase:latest mennotech/tallibase:latest

# push docker image to remote repository
docker push mennotech/tallibase
docker push mennotech/tallibase:$REV_TAG
