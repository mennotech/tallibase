# Workflow
We are working through deciding on how to set up the development workflow. At this point we are testing by deploying to fly.io using docker images for development and deployment.

The goal is to be able to spin up new new instances of this configuration very quickly. The long term goal is to build multiple sites and keep the configuration syncronized across all the sites.

Any user data or preferences for the system should be stored in the database. The default is to run sqlite for the database. This keeps things simple. The DB will run on the local disk allwing for high performance. fly.io does allow distributed sqlite databases through LiteFS. If I need to scale horizontally in the future, this remains as an open option. However, I don't expect there to be much traffic.

Build process is as follows:
- Start with base Docker Image: drupal:apache
- Dockerfile: Add additional debian packages
- Dockerfile: Add additional Drupal modules using composer
- Dockerfile: inject drupal-init.sh script as entry point
- Dockerfile: set propery permissions (TODO move this into drupal-init.sh ??)
- drupal-init.sh: make sure defined file and db paths are created and writeable
- drupal-init.sh: if no SQLite database is found, install new site with minimal profile
- drupal-init.sh: on site install, set static site UUID (TODO have the script modify the settings files to match site UUID??)
- drupal-init.sh: on every start up do the following:
  - Import configuration using **drush config:import**
  - Clear cache using **drush cr**
  - Import Taxonomy, Blocks and Menus using **drush content_as_config:import-all --style=safe**
  - Run cron: **drush cron**
  - Start Apache2: **exec apache2-foreground**

Site configurations should all be code managed in this repo in the prod/config/sync sub-folder.

# Setting up a new site on local system
You will need to install Docker

Run the .\scripts\win\dev-init.bat (windows) or #TODO ./scripts/linux/dev-init.sh (linux). This should take care of the following:
- Initialize the dev folders
- Copy the production settings.php file to dev/settings.php

# Pushing configuration to production
Run the script #TODO .\scripts\win\push-config-to-prod.bat (windows) or ./scripts/linux/push-config-to-prod.sh
