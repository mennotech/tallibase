#!/bin/sh

#Set default values if none supplied
: "${DBDRIVER:=sqlite}"
: "${DBNAME:=/opt/drupal/db/drupal-site.sqlite}"
: "${SITENAME:=tallibase.fly.io}"
: "${ADMINUSER:=admin}"
: "${ADMINPASSWORD:=tallibase}"

echo Starting drupal-init.sh
echo SITENAME:$SITENAME
echo DBDRIVER:$DBDRIVER
echo DBNAME:$DBNAME
echo DBHOST:$DBHOST
echo DBPORT:$DBPORT
echo DBUSER:$DBUSER
echo ADMINUSER:$ADMINUSER
echo ADMINPASSWORD:$ADMINPASSWORD
echo CMD:$@


cd /opt/drupal
mkdir -p /opt/drupal/config/sync


#Install site if not already installed
if [ "$DBDRIVER" = "sqlite" ]
then
    if [ ! -f "$DBNAME"  ]
    then
        #Create folder for the sqlite database and change ownership
        mkdir -p "${DBNAME%/*}"
        chown www-data:www-data "${DBNAME%/*}"

        #Run the site installation
        drush site:install \
            --db-url=$DBDRIVER://$DBNAME \
            --site-name=$SITENAME \
            --account-name=$ADMINUSER \
            --account-pass=$ADMINPASSWORD \
            minimal \
            install_configure_form.enable_update_status_emails=NULL
        
        #Change ownerhsip for the created database
        chown www-data:www-data $DBNAME

        #Reset the uuid to match the config files, this may a bad idea, however this allows
        #my configuration files to say consistent across all installations
        drush cset system.site uuid d6368e4e-823a-41ea-a5f1-f8e06bd9fe05

        #Edit the sync folder location to '../config/sync'
        # sed -i "s/^\(\$settings\['config_sync_directory'\] = \)'.*'/\1'..\/config\/sync'/" /opt/drupal/web/sites/default/settings.php

        #Remove old config folder
        # rm -Rf /opt/drupal/web/sites/default/files/config_*

    fi
else
    #Detect if the current database name is not in the setting.php file and run site installtion
    if ! grep -q "$DBNAME" "/opt/drupal/web/sites/default/settings.php"; then
        drush site:install \
            --site-name=$SITENAME \
            --db-url=$DBDRIVER://$DBUSER:$DBPASSWORD@$DBHOST:$DBPORT/$DBNAME \
            --account-name=$ADMINNAME \
            --account-pass=$ADMINPASSWORD \
            minimal \
            install_configure_form.enable_update_status_emails=NULL
    fi
fi


#Pull in any configuration updates
echo "Importing Drupal Configurations from config/sync"
drush config:import

#Start Apache2
echo "Starting Apache"
exec apache2-foreground