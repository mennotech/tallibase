#!/bin/sh

echo Warning. This script will wipe the dev folder and reset it

docker compose down dev

rm -Rf dev
mkdir -p dev/data

cp -R prod/config dev/config
cp prod/settings.php dev/settings.php
