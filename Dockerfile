FROM drupal:10.3.1-apache

#Drupal customizations should come afte this line


# Install unzip utility and libs needed by zip PHP extension 
RUN apt-get update && apt-get install -y \
    zlib1g-dev \
    libzip-dev \
    unzip \
	zip

RUN docker-php-ext-install zip

# Install additional packages
RUN apt-get update && apt-get install -y \
    git

#Clean up apt cache
RUN rm -rf /var/lib/apt/lists/*


#Drupal php.ini optimizations
RUN { \
		echo 'output_buffering=4096'; \
	} > /usr/local/etc/php/conf.d/drupal-recommended.ini


#Install contib modules
RUN \
	composer require "drush/drush" "^12.4" --no-interaction ; \
	composer require 'drupal/config_split:^2.0.1'; \
	composer require 'drupal/config_ignore:^3.3'; \
	composer require 'drupal/environment_indicator:^4.0.19'; \
	composer require 'drupal/admin_toolbar:^3.4'; \
	composer require 'drupal/inline_entity_form:^3.0@RC' --prefer-dist; \
	composer require 'drupal/content_as_config:^1.0' --prefer-dist; \
	composer require 'drupal/restui:^1.22' --prefer-dist; \
	composer require 'drupal/rest_api_authentication:^2.0' --prefer-dist; \
	composer update; \
	# delete composer cache
	rm -rf "$COMPOSER_HOME";

#Set up custom drupal init script
COPY drupal-init.sh /drupal-init.sh

#Copy site configuration
ADD prod/config /opt/drupal/config

#Copy settings.php
COPY prod/settings.php /opt/drupal/web/sites/default/settings.php

#Set permissions
RUN chown www-data:www-data /opt/drupal/web/sites/default/settings.php; \
	chmod 400 /opt/drupal/web/sites/default/settings.php; \
	chmod +x /drupal-init.sh; \
	mkdir -p /opt/drupal/web/sites/default/files; \
	chown www-data:www-data /opt/drupal/web/sites/default/files;

ENTRYPOINT ["/drupal-init.sh"]