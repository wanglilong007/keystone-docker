#!/usr/bin/env bash

TLS_ENABLED=${TLS_ENABLED:-false}
if $TLS_ENABLED; then
    HTTP="https"
    CN=${CN:-$HOSTNAME}
    # generate pem and crt files
    mkdir -p /etc/apache2/ssl
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/apache2/ssl/apache.key -out /etc/apache2/ssl/apache.crt \
        -subj "/C=$CONUTRY/ST=$STATE/L=$LOCALITY/O=$ORG/OU=$ORG_UNIT/CN=$CN"
else
    HTTP="http"
fi

ADMIN_TOKEN=${ADMIN_TOKEN:-294a4c8a8a475f9b9836}

OS_TOKEN=$ADMIN_TOKEN
OS_URL=${OS_AUTH_URL:-"$HTTP://${HOSTNAME}:35357/v3"}
OS_IDENTITY_API_VERSION=3

CONFIG_FILE=/etc/keystone/keystone.conf

if [ -z $KEYSTONE_DB_HOST ]; then
    KEYSTONE_DB_HOST=localhost
    echo "must use Remote MySQL Database; "
    # start mysql locally
    # service mysql restart
else
    if [ -z $KEYSTONE_DB_ROOT_PASSWD_IF_REMOTED ]; then
        echo "Your'are using Remote MySQL Database; "
        echo "Please set KEYSTONE_DB_ROOT_PASSWD_IF_REMOTED when running a container."
        exit 1;
    else
        KEYSTONE_DB_ROOT_PASSWD=$KEYSTONE_DB_ROOT_PASSWD_IF_REMOTED
    fi
fi

if [ "$(id -gn keystone)"  = "nogroup" ]
then
    usermod -g keystone keystone
fi

# create appropriate directories
mkdir -p /var/lib/keystone/ /etc/keystone/ /var/log/keystone/

# change the permissions on key directories
chown keystone:keystone -R /var/lib/keystone/ /etc/keystone/ /var/log/keystone/
chmod 0700 /var/lib/keystone/ /var/log/keystone/ /etc/keystone/

# Update keystone.conf
sed -i "s/KEYSTONE_DB_PASSWORD/$KEYSTONE_DB_PASSWD/g" /etc/keystone/keystone.conf
sed -i "s/KEYSTONE_DB_HOST/$KEYSTONE_DB_HOST/g" /etc/keystone/keystone.conf

# update keystone.conf
sed -i "s#^admin_token.*=.*#admin_token = $ADMIN_TOKEN#" $CONFIG_FILE

# Write openrc to disk
cat >~/openrc <<EOF
export OS_TOKEN=${ADMIN_TOKEN}
export OS_URL=$HTTP://${HOSTNAME}:35357/v3
export OS_IDENTITY_API_VERSION=3
EOF


# Configure Apache2
echo "ServerName $HOSTNAME" >> /etc/apache2/apache2.conf

# if TLS is enabled
if $TLS_ENABLED; then
echo "export OS_CACERT=/etc/apache2/ssl/apache.crt" >> /root/openrc
a2enmod ssl
sed -i '/<VirtualHost/a \
    SSLEngine on \
    SSLCertificateFile /etc/apache2/ssl/apache.crt \
    SSLCertificateKeyFile /etc/apache2/ssl/apache.key \
    ' /etc/apache2/sites-available/keystone.conf
fi

# ensite keystone and start apache2
a2ensite keystone
apache2ctl -D FOREGROUND
