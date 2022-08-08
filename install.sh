# LibreNMS Install script
# NOTE: Script wil update and upgrade currently installed packages.
# forked from straytripod/LibreNMS-Install
# created and maintained from rawIce/LibreNMS-Install
#!/bin/bash

##### Check if sudo
if [[ "$EUID" -ne 0 ]]
  then echo "Please run as root"
  exit
fi

##### Start script
echo "###########################################################"
echo "This script will install LibreNMS using NGINX webserver, developed for Ubuntu 20.04 LTS"
echo "The script will perform apt install and update commands."
echo "Use at your own risk"
echo "###########################################################"
read -p "Please [Enter] to continue..." ignore

##### Installing Required Packages
apt install -y software-properties-common
add-apt-repository universe
apt update
echo "Upgrading installed packages"
echo "###########################################################"
apt upgrade -y
echo "Installing LibreNMS required packages"
echo "###########################################################"
apt install -y acl curl composer fping git graphviz imagemagick mariadb-client \
mariadb-server mtr-tiny nginx-full nmap php8.1-cli php8.1-curl php8.1-fpm \
php8.1-gd php8.1-mbstring php8.1-mysql php8.1-snmp php8.1-xml \
php8.1-zip rrdtool snmp snmpd whois unzip python3-pymysql python3-dotenv \
python3-redis python3-setuptools

##### Add librenms user
echo "Add librenms user"
echo "###########################################################"
# add user link home directory, do not create home directory
useradd librenms -d /opt/librenms -M -r -s "$(which bash)"

##### Download LibreNMS itself
echo "Downloading libreNMS to /opt/librenms"
echo "###########################################################"
cd /opt
git clone https://github.com/librenms/librenms.git
# Set permissions
echo "Setting permissions and file access controls"
echo "###########################################################"
# set owner:group recursively on directory
chown -R librenms:librenms /opt/librenms
# mod permission on directory O=All,G=All, Oth=view
chmod 771 /opt/librenms
# mod default ACL
setfacl -d -m g::rwx /opt/librenms/rrd /opt/librenms/logs /opt/librenms/bootstrap/cache/ /opt/librenms/storage/
# mod ACL recursively
setfacl -R -m g::rwx /opt/librenms/rrd /opt/librenms/logs /opt/librenms/bootstrap/cache/ /opt/librenms/storage/

##### Install PHP dependencies
echo "Install PHP dependencies"
echo "###########################################################"
# run php dependencies installer
su librenms bash -c '/opt/librenms/scripts/composer_wrapper.php install --no-dev'

##### Set system timezone
echo "Setup of system and PHP timezone"
echo "###########################################################"
# Asking for timezome of choice
echo "We have to set the system time zone."
echo "You will get a list of all available time zones"
echo "Use q to quit the list and enter your choice"
read -p "Please [Enter] to continue..." ignore
echo "-----------------------------"
echo " "
timedatectl list-timezones
echo " "
echo "Enter system time zone of choice:"
read TZ
timedatectl set-timezone $TZ
# Set timezone
echo "Setting PHP time zone"
echo "Changing to $TZ"
echo "################################################################################"
sed -i "/;date.timezone =/ a date.timezone = $TZ" /etc/php/8.1/fpm/php.ini
sed -i "/;date.timezone =/ a date.timezone = $TZ" /etc/php/8.1/cli/php.ini

##### Configure MariaDB
echo "Configuring MariaDB"
echo "###########################################################"
##### Within the [mysqld] section of the config file please add: ####
## innodb_file_per_table=1
## lower_case_table_names=0
sed -i '/mysqld]/ a lower_case_table_names=0' /etc/mysql/mariadb.conf.d/50-server.cnf
sed -i '/mysqld]/ a innodb_file_per_table=1' /etc/mysql/mariadb.conf.d/50-server.cnf
# Enable & restart MariaDB
systemctl enable mariadb
systemctl restart mariadb
# Pass commands to mysql and create DB, user, and privlages
echo "Please create a password for LibreNMS database user on MariaDB - you need it later during web installation:"
read ANS
echo "###########################################################"
echo "######### MySQL DB:librenms Password:$ANS #################"
echo "###########################################################"
sleep 3
mysql -uroot -e "CREATE DATABASE librenms CHARACTER SET utf8 COLLATE utf8_unicode_ci;"
mysql -uroot -e "CREATE USER 'librenms'@'localhost' IDENTIFIED BY '$ANS';"
mysql -uroot -e "GRANT ALL PRIVILEGES ON librenms.* TO 'librenms'@'localhost';"
mysql -uroot -e "FLUSH PRIVILEGES;"

##### Configure PHP-FPM
echo "Configure PHP-FPM (FastCGI Process Manager)"
echo "###########################################################"
cp /etc/php/8.1/fpm/pool.d/www.conf /etc/php/8.1/fpm/pool.d/librenms.conf
sed -i 's/^\[www\]/\[librenms\]/' /etc/php/8.1/fpm/pool.d/librenms.conf
sed -i 's/^user = www-data/user = librenms/' /etc/php/8.1/fpm/pool.d/librenms.conf
sed -i 's/^group = www-data/group = librenms/' /etc/php/8.1/fpm/pool.d/librenms.conf
sed -i 's/^listen =.*/listen = \/run\/php-fpm-librenms.sock/' /etc/php/8.1/fpm/pool.d/librenms.conf

##### Configure web server (NGINX
echo "Configure web server (NGINX)"
echo "###########################################################"
# Create NGINX .conf file
echo "We need to change the sever name to the current IP unless the name is resolvable /etc/nginx/conf.d/librenms.conf"
echo "################################################################################"
echo "Enter nginx server_name [x.x.x.x or serv.examp.com]: "
read HOSTNAME
echo 'server {'> /etc/nginx/conf.d/librenms.conf
echo ' listen      80;' >>/etc/nginx/conf.d/librenms.conf
echo " server_name $HOSTNAME;" >>/etc/nginx/conf.d/librenms.conf
echo ' root        /opt/librenms/html;' >>/etc/nginx/conf.d/librenms.conf
echo ' index       index.php;' >>/etc/nginx/conf.d/librenms.conf
echo ' ' >>/etc/nginx/conf.d/librenms.conf
echo ' charset utf-8;' >>/etc/nginx/conf.d/librenms.conf
echo ' gzip on;' >>/etc/nginx/conf.d/librenms.conf
echo ' gzip_types text/css application/javascript text/javascript application/x-javascript image/svg+xml \
text/plain text/xsd text/xsl text/xml image/x-icon;' >>/etc/nginx/conf.d/librenms.conf
echo ' location / {' >>/etc/nginx/conf.d/librenms.conf
echo '  try_files $uri $uri/ /index.php?$query_string;' >>/etc/nginx/conf.d/librenms.conf
echo ' }' >>/etc/nginx/conf.d/librenms.conf
echo ' location ~ [^/]\.php(/|$) {' >>/etc/nginx/conf.d/librenms.conf
echo '  fastcgi_pass unix:/run/php-fpm-librenms.sock;' >>/etc/nginx/conf.d/librenms.conf
echo '  fastcgi_split_path_info ^(.+\.php)(/.+)$;' >>/etc/nginx/conf.d/librenms.conf
echo '  include fastcgi.conf;' >>/etc/nginx/conf.d/librenms.conf
echo ' }' >>/etc/nginx/conf.d/librenms.conf
echo ' location ~ /\.(?!well-known).* {' >>/etc/nginx/conf.d/librenms.conf
echo '  deny all;' >>/etc/nginx/conf.d/librenms.conf
echo ' }' >>/etc/nginx/conf.d/librenms.conf
echo '}' >>/etc/nginx/conf.d/librenms.conf
# remove the default site link
rm /etc/nginx/sites-enabled/default
systemctl restart nginx
systemctl restart php8.1-fpm

##### Enable lnms command completion
echo "Enable lnms command completion"
echo "###########################################################"
ln -s /opt/librenms/lnms /usr/local/bin/lnms
cp /opt/librenms/misc/lnms-completion.bash /etc/bash_completion.d/

##### Configure snmpd
echo "Configure snmpd"
cp /opt/librenms/snmpd.conf.example /etc/snmp/snmpd.conf
# Edit the text which says RANDOMSTRINGGOESHERE and set your own community string.
echo "We need to set your default SNMP community string"
echo "Enter community string [e.g.: public ]: "
read ANS
sed -i "s/RANDOMSTRINGGOESHERE/$ANS/g" /etc/snmp/snmpd.conf

# get standard MIBs
curl -o /usr/bin/distro https://raw.githubusercontent.com/librenms/librenms-agent/master/snmp/distro
chmod +x /usr/bin/distro
systemctl enable snmpd
systemctl restart snmpd

##### Setup Cron job
echo "Setup LibreNMS Cron job"
echo "###########################################################"
cp /opt/librenms/librenms.nonroot.cron /etc/cron.d/librenms

##### Setup logrotate config
echo "Setup logrotate config"
echo "###########################################################"
cp /opt/librenms/misc/librenms.logrotate /etc/logrotate.d/librenms

#### Common fixes
echo "Perform common fixes in order to help pass LibreNMS validation"
echo "###########################################################"
# create default custom config.php in case the user needs it
cp /opt/librenms/config.php.default /opt/librenms/config.php
# set default LibreNMS permissions which cause most errors
sudo chown -R librenms:librenms /opt/librenms
sudo setfacl -d -m g::rwx /opt/librenms/rrd /opt/librenms/logs /opt/librenms/bootstrap/cache/ /opt/librenms/storage/
sudo chmod -R ug=rwX /opt/librenms/rrd /opt/librenms/logs /opt/librenms/bootstrap/cache/ /opt/librenms/storage/
echo "Select yes to the following or you might get a warning during validation"
echo "------------------------------------------------------------------------"
# Remove github leftovers
sudo su librenms bash -c '/opt/librenms/scripts/github-remove -d'

##### End of installation, continue in web browser
echo "###############################################################################################"
echo "Naviagte to http://$HOSTNAME/install.php in you web browser to finish the installation."
echo "###############################################################################################"