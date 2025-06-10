#!/bin/sh

REV_TAG=$(git log -1 --pretty=format:%h)
docker build -t tallibase:latest -t tallibase:$REV_TAG .
