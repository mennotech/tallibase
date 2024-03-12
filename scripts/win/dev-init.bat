@ECHO OFF

ECHO Warning. This script will wipe the dev folder and reset it
ECHO.

rd /s dev
mkdir dev\config
mkdir dev\db
mkdir dev\files

copy prod\settings.php dev\settings.php