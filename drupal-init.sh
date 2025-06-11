#!/bin/sh
VERSION=1.0.4


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

#Set environment variables if they are not already set
export DBDRIVER
export DBNAME
export SITENAME
export PUBLICFILES
export PRIVATEFILES

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
else 
    echo "Database driver $DBDRIVER is not supported for initial installation. Please use SQLite."
    exit 1
fi

#Create a hash of all the files in the config directory
CONFIG_HASH=$(find /opt/drupal/config -type f -exec md5sum {} + | sort | md5sum | awk '{ print $1 }')
echo "Configuration hash: $CONFIG_HASH"


#Check if the config hash has changed
if [ -f /opt/drupal/data/config_hash.txt ]; then
    OLD_CONFIG_HASH=$(cat /opt/drupal/data/config_hash.txt)
    if [ "$CONFIG_HASH" != "$OLD_CONFIG_HASH" ]; then
        echo "Configuration files have changed, importing new configurations."
        drush config:import --yes

        #Import all content_as_config
        echo "Importing all content_as_config"
        drush content_as_config:import-all --style=safe --yes

        #Run cron tasks
        echo "Running cron tasks"
        drush cron --yes

        #Rebuild all the caches
        echo "Rebuilding Drupal caches"
        drush cr --yes

        #Update the config hash file
        echo $CONFIG_HASH > /opt/drupal/data/config_hash.txt
    else
        echo "Configuration files have not changed, skipping import."
    fi
else
    echo "No previous configuration hash found, importing configurations."
    drush config:import --yes

    #Import all content_as_config
    echo "Importing all content_as_config"
    drush content_as_config:import-all --style=safe --yes

    #Pull in any configuration updates
    echo "Running 2nd config/sync"
    drush config:import --yes

    #Run cron tasks
    echo "Running cron tasks"
    drush cron --yes

    #Rebuild all the caches
    echo "Rebuilding Drupal caches"
    drush cr --yes

    #Save the current config hash for future reference
    echo $CONFIG_HASH > /opt/drupal/data/config_hash.txt
fi

#Check if db updates are needed
if drush updatedb-status 2>&1 | grep -q "No database updates required"; then
    echo "No database updates needed."
else
    echo "Database updates are available."
    # If this is the first run, we will run the updates
    echo "Running database updates "
    drush updatedb -vv --yes

    #Rebuild all the caches
    echo "Rebuilding Drupal caches"
    drush cr --yes
fi

#Start Apache2
echo "Starting Apache"
exec apache2-foreground