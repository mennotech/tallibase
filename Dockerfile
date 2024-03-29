# https://www.drupal.org/docs/system-requirements/php-requirements
FROM php:8.3-apache-bookworm

# install the PHP extensions we need
RUN set -eux; \
	\
	if command -v a2enmod; then \
# https://github.com/drupal/drupal/blob/d91d8d0a6d3ffe5f0b6dde8c2fbe81404843edc5/.htaccess (references both mod_expires and mod_rewrite explicitly)
		a2enmod expires rewrite; \
	fi; \
	\
	savedAptMark="$(apt-mark showmanual)"; \
	\
	apt-get update; \
	apt-get install -y --no-install-recommends \
		libfreetype6-dev \
		libjpeg-dev \
		libpng-dev \
		libpq-dev \
		libwebp-dev \
		libzip-dev \
		#added postgresql
		postgresql \
	; \
	\
	docker-php-ext-configure gd \
		--with-freetype \
		--with-jpeg=/usr \
		--with-webp \
	; \
	\
	docker-php-ext-install -j "$(nproc)" \
		gd \
		opcache \
		pdo_mysql \
		pdo_pgsql \
		zip \
	; \
	\
# reset apt-mark's "manual" list so that "purge --auto-remove" will remove all build dependencies
	apt-mark auto '.*' > /dev/null; \
	apt-mark manual $savedAptMark; \
	ldd "$(php -r 'echo ini_get("extension_dir");')"/*.so \
		| awk '/=>/ { so = $(NF-1); if (index(so, "/usr/local/") == 1) { next }; gsub("^/(usr/)?", "", so); print so }' \
		| sort -u \
		| xargs -r dpkg-query -S \
		| cut -d: -f1 \
		| sort -u \
		| xargs -rt apt-mark manual; \
	\
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
	rm -rf /var/lib/apt/lists/*

# set recommended PHP.ini settings
# see https://secure.php.net/manual/en/opcache.installation.php
RUN { \
		echo 'opcache.memory_consumption=128'; \
		echo 'opcache.interned_strings_buffer=8'; \
		echo 'opcache.max_accelerated_files=4000'; \
		echo 'opcache.revalidate_freq=60'; \
	} > /usr/local/etc/php/conf.d/opcache-recommended.ini

COPY --from=composer:2 /usr/bin/composer /usr/local/bin/

# 2024-03-06: https://www.drupal.org/project/drupal/releases/10.2.4
ENV DRUPAL_VERSION 10.2.4

#Allow root composer
ENV COMPOSER_ALLOW_SUPERUSER 1

WORKDIR /opt/drupal

#Base Drupal Install copied from Offical Drupal Docker images
RUN set -eux; \
	export COMPOSER_HOME="$(mktemp -d)"; \
	composer create-project --no-interaction "drupal/recommended-project:$DRUPAL_VERSION" ./; \
	chown -R www-data:www-data web/sites web/modules web/themes; \
	# install drush
	composer require "drush/drush" "^12.4" --no-interaction ; \
	composer require "composer/installers" "^2.0"; \
	ln -s /opt/drupal/vendor/bin/drush /usr/local/bin/drush; \
	rmdir /var/www/html; \
	composer update; \
	ln -sf /opt/drupal/web /var/www/html; \
	# delete composer cache
	rm -rf "$COMPOSER_HOME";


ENV PATH=${PATH}:/opt/drupal/vendor/bin

#Drupal customizations should come afte this line

#Install additional Debian packages
RUN apt update; \
	apt install unzip; \
	#Clean up apt cache
	rm -rf /var/lib/apt/lists/*

#Drupal php.ini optimizations
RUN { \
		echo 'output_buffering=4096'; \
	} > /usr/local/etc/php/conf.d/drupal-recommended.ini

#Set up custom drupal init script
COPY drupal-init.sh /drupal-init.sh

#Install contib modules
RUN composer require 'drupal/config_split:^2.0'; \
	composer require 'drupal/config_ignore:^3.2'; \
	composer require 'drupal/environment_indicator:^4.0';\
	composer require 'drupal/admin_toolbar:^3.4'; \
	composer update; \
	# delete composer cache
	rm -rf "$COMPOSER_HOME";


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