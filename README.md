# tallibase
A Drupal site to manage an organizations staff, systems and software

# Workflow
I'm working through deciding on how to set up the development workflow. I'm going to start by deploying my project to fly.io. I will be working with docker images for development and deployment, however fly.io does not use Docker to run the actual images, just for building. This is at least how I understand things for now.

To start with I'm looking to be able to spin up new instances of this configuration very quickly. I'm hoping to build multiple sites and keep the configuration syncronized across all the sites.

Any user data or preferences for the system should be stored in the database. The default is to run sqlite for the database. This keeps things simple. The DB will run on the local disk allwing for high performance. fly.io does allow distributed sqlite databases through LiteFS. If I need to scale horizontally in the future, this remains as an open option. However, I don't expect there to be much traffic.

The goal is to have a simple stack with a simple workflow.

Site configurations should all be code managed in this repo.

# Setting up a new site on local system
You will need to install Docker

Run the .\scripts\win\dev-init.bat (windows) or #TODO ./scripts/linux/dev-init.sh (linux). This should take care of the following:
- Initialize the dev folders
- Copy the production settings.php file to dev/settings.php

# Pushing configuration to production
Run the script #TODO .\scripts\win\push-config-to-prod.bat (windows) or x/scripts/linux/push-config-to-prod.sh