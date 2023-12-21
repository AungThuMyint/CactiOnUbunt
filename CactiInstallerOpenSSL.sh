#!/bin/bash

# Update and upgrade
sudo apt update && sudo apt upgrade -y

# Install Apache
sudo apt install apache2 -y
sudo systemctl enable --now apache2

# Install PHP and required modules
sudo apt install php php-{mysql,curl,net-socket,gd,intl,pear,imap,memcache,pspell,tidy,xmlrpc,snmp,mbstring,gmp,json,xml,common,ldap} -y
sudo apt install libapache2-mod-php

# Configure PHP settings
sudo sed -i 's/memory_limit = .*/memory_limit = 512M/' /etc/php/*/apache2/php.ini
sudo sed -i 's/max_execution_time = .*/max_execution_time = 300/' /etc/php/*/apache2/php.ini
sudo sed -i 's/;date.timezone =.*/date.timezone = Asia\/Yangon/' /etc/php/*/apache2/php.ini
sudo sed -i 's/;date.timezone =.*/date.timezone = Asia\/Yangon/' /etc/php/*/cli/php.ini

# Restart Apache to apply changes
sudo systemctl restart apache2

# Install and configure MariaDB
sudo apt install mariadb-server -y
sudo systemctl enable --now mariadb

# MySQL commands for setting up Cacti database and user
mysql -u root -e "CREATE DATABASE cacti DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;"
mysql -u root -e "GRANT ALL PRIVILEGES ON cacti.* TO 'cacti_user'@'localhost' IDENTIFIED BY 'Di5OqKc^k1@0';"
mysql -u root -e "GRANT SELECT ON mysql.time_zone_name TO cacti_user@localhost;"
mysql -u root -e "ALTER DATABASE cacti CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
mysql -u root -e "FLUSH PRIVILEGES;"

# Configure MariaDB settings
sudo tee -a /etc/mysql/mariadb.conf.d/50-server.cnf > /dev/null << EOL
[mysqld]
innodb_file_format=Barracuda
innodb_large_prefix=1
collation-server=utf8mb4_unicode_ci
character-set-server=utf8mb4
innodb_doublewrite=OFF
max_heap_table_size=128M
tmp_table_size=128M
join_buffer_size=128M
innodb_buffer_pool_size=1G
innodb_flush_log_at_timeout=3
innodb_read_io_threads=32
innodb_write_io_threads=16
innodb_io_capacity=5000
innodb_io_capacity_max=10000
innodb_buffer_pool_instances=9
EOL

# Delete two lines
sudo sed -i '/^character-set-server  = utf8mb4/d' "/etc/mysql/mariadb.conf.d/50-server.cnf"
sudo sed -i '/^collation-server      = utf8mb4_general_ci/d' "/etc/mysql/mariadb.conf.d/50-server.cnf"

# Apply timezone information
mysql_tzinfo_to_sql /usr/share/zoneinfo | mysql -u root mysql

# Install SNMP, SNMPd, and RRDtool
sudo apt install snmp snmpd rrdtool -y

# Install Git
sudo apt install git

# Clone Cacti repository
git clone -b 1.2.x https://github.com/Cacti/cacti.git

# Move Cacti to Apache's web directory
sudo mv cacti /var/www/html

# Import Cacti database schema
sudo mysql -u root cacti < /var/www/html/cacti/cacti.sql

# Copy Cacti configuration file
sudo cp /var/www/html/cacti/include/config.php.dist /var/www/html/cacti/include/config.php

# Configure Cacti database credentials
sudo sed -i "s/\$database_username = 'cactiuser';/\$database_username = 'cacti_user';/" /var/www/html/cacti/include/config.php
sudo sed -i "s/\$database_password = 'cactiuser';/\$database_password = 'Di5OqKc^k1@0';/" /var/www/html/cacti/include/config.php

# Set correct ownership
sudo chown -R www-data:www-data /var/www/html/cacti

# Create Cactid service file
sudo tee /etc/systemd/system/cactid.service > /dev/null << EOL
[Unit]
Description=Cacti Daemon Main Poller Service
After=network.target

[Service]
Type=forking
User=www-data
Group=www-data
EnvironmentFile=/etc/default/cactid
ExecStart=/var/www/html/cacti/cactid.php
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOL

# Create Cactid environment file
sudo touch /etc/default/cactid

# Reload systemd
sudo systemctl daemon-reload

# Enable and restart Cactid service
sudo systemctl enable cactid
sudo systemctl restart cactid

# Restart Apache and MariaDB
sudo systemctl restart apache2 mariadb

echo
echo "Cacti Setup Completed!"

# Get the local IP address
local_ip=$(hostname -I | awk '{print $1}')

# Define the output folder
output_folder="/root/cacti_cert"

# Check if the output folder already exists
if [ ! -d "$output_folder" ]; then
    # Create the output folder if it doesn't exist
    mkdir -p "$output_folder"
    echo "Output folder created: $output_folder"
else
    echo "Output folder already exists: $output_folder"
fi

# Generate RSA private key
openssl genrsa -out "$output_folder/cacti.key" 2048

# Generate Certificate Signing Request (CSR)
openssl req -new -key "$output_folder/cacti.key" -out "$output_folder/cacti.csr" -subj "/C=MM/ST=Yangon/L=Yangon/O=AGB/OU=AGB/CN=cacti.com"

# Generate Self-Signed Certificate (valid for 700 days)
openssl x509 -req -days 700 -in "$output_folder/cacti.csr" -signkey "$output_folder/cacti.key" -out "$output_folder/cacti.crt"

# Remove the CSR file
rm "$output_folder/cacti.csr"

# Apache https configuration
sudo a2enmod ssl
systemctl restart apache2
cp /etc/apache2/sites-available/000-default.conf /etc/apache2/sites-available/000-default.conf.backup
sudo rm /etc/apache2/sites-available/000-default.conf
config_file="/etc/apache2/sites-available/000-default.conf"

cat > "$config_file" <<EOL
<VirtualHost $local_ip:443>
        DocumentRoot /var/www/html
        RedirectMatch ^/$ /cacti/
        SSLEngine on
        SSLCertificateFile /root/cacti_cert/cacti.crt
        SSLCertificateKeyFile /root/cacti_cert/cacti.key
</VirtualHost>
<VirtualHost *:80>
        Redirect "/" "https://$local_ip/cacti/"
</VirtualHost>
EOL
systemctl restart apache2

# Output to user
echo
echo "URL : https://$local_ip/cacti/"
echo "Default Web Username : admin"
echo "Default Web Password : admin"
echo