#!/bin/sh
VERSION=1.0.3


#Set default values if none supplied
: "${DBDRIVER:=sqlite}"
: "${DBNAME:=/opt/drupal/data/db/drupal-site.sqlite}"
: "${PUBLICFILES:=/opt/drupal/data/files}"
: "${PRIVATEFILES:=/opt/drupal/data/private}"
: "${SITENAME:=localhost}"
: "${ADMINUSER:=admin}"
: "${ADMINPASSWORD:=tallibase}"

echo Starting drupal-init.sh v$VERSION
echo SITENAME:$SITENAME
echo DBDRIVER:$DBDRIVER
echo DBNAME:$DBNAME
echo DBHOST:$DBHOST
echo DBPORT:$DBPORT
echo DBUSER:$DBUSER
echo ADMINUSER:$ADMINUSER
echo ADMINPASSWORD:$ADMINPASSWORD
echo CMD:$@
echo PUBLICFILES:$PUBLICFILES
echo PRIVATEFILES:$PRIVATEFILES

#Check if the drush command is available
if ! command -v drush >/dev/null 2>&1; then
    echo "Drush command not found. Please install Drush to continue."
    exit 1
fi


#Create public and private files directories and set ownership
mkdir -p $PUBLICFILES
chown -R www-data:www-data $PUBLICFILES

mkdir -p $PRIVATEFILES
chown -R www-data:www-data $PRIVATEFILES

#Point the public files directory to the configured public files location
rm -Rf /opt/drupal/web/sites/default/files
ln -s $PUBLICFILES /opt/drupal/web/sites/default/files

#Create DBNAME parent folder and set ownership
mkdir -p ${DBNAME%/*}
chown -R www-data:www-data ${DBNAME%/*}


#Install site if not already installed
if [ "$DBDRIVER" = "sqlite" ]
then
    if [ ! -f "$DBNAME"  ]
    then
        echo "Database file $DBNAME does not exist, creating a new SQLite database."

        #Run the site installation
        drush site:install \
            --db-url=$DBDRIVER://$DBNAME \
            --site-name=$SITENAME \
            --account-name=$ADMINUSER \
            --account-pass=$ADMINPASSWORD \
            minimal \
            install_configure_form.enable_update_status_emails=NULL \
            --yes

        #Reset the uuid to match the config files, this may a bad idea, however this allows
        #my configuration files to say consistent across all installations
        drush cset system.site uuid d6368e4e-823a-41ea-a5f1-f8e06bd9fe05 --yes

        
        #Change ownerhsip for the created database
        chown www-data:www-data $DBNAME
    fi
fi

#Check if the site is already installed
if [ ! -f "/.initialized" ]
then
    echo "Running initial setup tasks..."

    #Add sitename to trusted_host_patterns
    echo "\$settings['trusted_host_patterns'] = ['^$SITENAME\$',];\n" >> /opt/drupal/web/sites/default/settings.php

    #Set private file path
    echo "\$settings['file_private_path'] = '$PRIVATEFILES';\n" >> /opt/drupal/web/sites/default/settings.php

    #Add servername to Apache2 config
    echo "ServerName $SITENAME\n" >> /etc/apache2/apache2.conf

    touch /.initialized
    echo "Initial setup tasks completed."
fi

#Apply private files settings
sed -i "s|^\(\$settings\['file_private_path'\] = \).*$|\1'$PRIVATEFILES';|" /opt/drupal/web/sites/default/settings.php


#Pull in any configuration updates
echo "Importing Drupal Configurations from config/sync"
drush config:import --yes

#Rebuild all the caches
drush cr --yes

#Import all content_as_config
drush content_as_config:import-all --style=safe --yes

#Install any Database Updates
echo "Running Database Updates"
drush updatedb -vv --yes

#Run cron
echo "Running Drupal cron"
drush cron --yes

#Start Apache2
echo "Starting Apache"
exec apache2-foreground