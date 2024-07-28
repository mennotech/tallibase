#!/bin/sh

#Set default values if none supplied
: "${DBDRIVER:=sqlite}"
: "${DBNAME:=/opt/drupal/data/db/drupal-site.sqlite}"
: "${FILES:=/opt/drupal/data/files}"
: "${SITENAME:=localhost}"
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


#Create files folder and create link to folder
mkdir -p $FILES && chown www-data:www-data $FILES
rm -Rf /opt/drupal/web/sites/default/files
ln -s /opt/drupal/data/files /opt/drupal/web/sites/default/files

#Create DBNAME parent folder
mkdir -p ${DBNAME%/*} && chown www-data:www-data ${DBNAME%/*}


#Install site if not already installed
if [ "$DBDRIVER" = "sqlite" ]
then
    if [ ! -f "$DBNAME"  ]
    then

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

        #Add sitename to trusted_host_patterns
        echo "\$settings['trusted_host_patterns'] = ['^$SITENAME\$',];" >> /opt/drupal/web/sites/default/settings.php

        #Add servername to Apache2 config
        echo "ServerName $SITENAME" >> /etc/apache2/apache2.conf

        #Edit the sync folder location to '../config/sync'
        # sed -i "s/^\(\$settings\['config_sync_directory'\] = \)'.*'/\1'..\/config\/sync'/" /opt/drupal/web/sites/default/settings.php

        #Remove old config folder
        # rm -Rf /opt/drupal/web/sites/default/files/config_*

    fi
fi


#Pull in any configuration updates
echo "Importing Drupal Configurations from config/sync"
drush config:import
#Rebuild all the caches
drush cr

#Import all content_as_config
drush content_as_config:import-all --style=safe

#Run cron
echo "Running Drupal cron"
drush cron

#Start Apache2
echo "Starting Apache"
exec apache2-foreground