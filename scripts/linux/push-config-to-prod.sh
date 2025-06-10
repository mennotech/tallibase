#!/bin/sh

docker exec -it tallibase-dev-1 drush cex -y
rm prod/config/sync/*
cp dev/config/sync/* prod/config/sync/
