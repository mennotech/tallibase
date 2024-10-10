# Tallibase
Tallibase is a web-based computer technology asset and inventory management platform. Properly inventory of digital assets is essential to proper security practices. Tallibase will allow organizations to track and manage security risks and enforce and roll out security roles and profiles to their devices.

The following types of resource records are avaiable:
- Software and Code
- Devices (computers, servers, printers, etc)
- People
- Roles
- Vendors

# Automation
Tallibase is built to be the central repository for inventory allowing for automation and enforcement of policies.

New users and devices will be automatically detected and flagged to ensure any changes to the environment are logged.


# Docker Image

To start the docker image, the following Environment Variables should be set

```
DBDRIVER: sqlite
DBNAME: /opt/drupal/data/db/drupal-site.sqlite
PUBLICFILES: /opt/drupal/data/files
PRIVATEFILES: /opt/drupal/data/private
SITENAME: localhost
ENV_TYPE: staging
ENV_HOST: docker
```
