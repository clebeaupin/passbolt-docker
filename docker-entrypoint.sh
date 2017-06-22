#!/bin/bash

set -exo pipefail

gpg_private_key=/var/www/passbolt/app/Config/gpg/private.key
gpg_public_key=/var/www/passbolt/app/Config/gpg/public.key
gpg=$(which gpg)

core_config='/var/www/passbolt/app/Config/core.php'
db_config='/var/www/passbolt/app/Config/database.php'
app_config='/var/www/passbolt/app/Config/app.php'
email_config='/var/www/passbolt/app/Config/email.php'
ssl_key='/etc/ssl/certs/certificate.key'
ssl_cert='/etc/ssl/certs/certificate.crt'

gpg_import_key() {
  echo "Setup[keys]"
  local key_id=$(su -m -c "gpg --with-colons $gpg_private_key | grep sec |cut -f5 -d:" -ls /bin/bash nginx)

  su -m -c "$gpg --batch --import $gpg_public_key" -ls /bin/bash nginx
  su -m -c "gpg -K $key_id" -ls /bin/bash nginx || su -m -c "$gpg --batch --import $gpg_private_key" -ls /bin/bash nginx
}

core_setup() {
  #Env vars:
  # salt
  # cipherseed
  # url

  echo "Setup[core]"
  local default_salt='DYhG93b0qyJfIxfs2guVoUubWwvniR2G0FgaC9mi'
  local default_seed='76859309657453542496749683645'
  local default_url='example.com'

  cp $core_config{.default,}
  sed -i s:$default_salt:${salt:-$default_salt}:g $core_config
  sed -i s:$default_seed:${cipherseed:-$default_seed}:g $core_config
  sed -i s:$default_url:${url:-$default_url}:g $core_config
}

db_setup() {
  #Env vars:
  # db_type
  # db_host
  # db_user
  # db_pass
  # db_name

  echo "Setup[db]"
  local default_type='Database/Mysql'
  local default_host='localhost'
  local default_user='user'
  local default_pass='password'
  local default_db='database_name'

  cp $db_config{.default,}
  sed -i s:$default_type:Database/$DB_TYPE:g $db_config
  sed -i s:$default_host:$DB_HOST:g $db_config
  sed -i s:$default_user:$DB_USER:g $db_config
  sed -i s:$default_pass\',:$DB_PASS\',:g $db_config
  sed -i s:$default_db:$DB_NAME:g $db_config
}

app_setup() {
  #Env vars:
  # fingerprint
  # registration
  # ssl

  echo "Setup[app]"
  local default_home='/home/www-data/.gnupg'
  local default_public_key='unsecure.key'
  local default_private_key='unsecure_private.key'
  local default_fingerprint='2FC8945833C51946E937F9FED47B0811573EE67E'
  local default_ssl='force'
  local default_registration='public'
  local gpg_home='/var/lib/nginx/.gnupg'
  local auto_fingerprint=$(su -m -c "$gpg --fingerprint |grep fingerprint| awk '{for(i=4;i<=NF;++i)printf \$i}'" -ls /bin/bash nginx)

  cp $app_config{.default,}
  sed -i s:$default_home:$gpg_home:g $app_config
  sed -i s:$default_public_key:serverkey.asc:g $app_config
  sed -i s:$default_private_key:serverkey.private.asc:g $app_config
  sed -i s:$default_fingerprint:${APP_FINGERPRINT:-$auto_fingerprint}:g $app_config
  sed -i "/force/ s:true:${APP_SSL:-true}:" $app_config
}

email_setup() {
  #Env vars:
  # email_tansport
  # email_from
  # email_host
  # email_port
  # email_timeout
  # email_username
  # email_password

  echo "Setup[email]"
  local default_transport='Smtp'
  local default_from='contact@passbolt.com'
  local default_host='smtp.mandrillapp.com'
  local default_port='587'
  local default_timeout='30'
  local default_username="''"
  local default_password="''"

  cp $email_config{.default,}
  sed -i s:$default_transport:${email_transport:-Smtp}:g $email_config
  sed -i s:$default_from:${EMAIL_FROM:-contact@mydomain.local}:g $email_config
  sed -i s:$default_host:${SMTP_HOST:-localhost}:g $email_config
  sed -i s:$default_port:${SMTP_PORT:-587}:g $email_config
  sed -i s:$default_timeout:${email_timeout:-30}:g $email_config
  sed -i "0,/"$default_username"/s:"$default_username":'${email_username:-email_user}':" $email_config
  sed -i "0,/"$default_username"/s:"$default_password":'${email_password:-email_password}':" $email_config
}

install() {
  echo "Setup[install-db]"
  local database=${db_host:-$(grep -m1 -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}' $db_config)}
  tables=$(mysql -u ${db_user:-passbolt} -h $database -p -BN -e "SHOW TABLES FROM passbolt" -p${db_pass:-P4ssb0lt} |wc -l)

  if [ $tables -eq 0 ]; then
    su -c "/var/www/passbolt/app/Console/cake install --send-anonymous-statistics true --no-admin" -ls /bin/bash nginx
  else
    echo "Enjoy! ☮"
  fi
}

php_fpm_setup() {
  echo "Setup[php-fpm]"
  sed -i '/^user\s/ s:nobody:nginx:g' /etc/php5/php-fpm.conf
  sed -i '/^group\s/ s:nobody:nginx:g' /etc/php5/php-fpm.conf
  cp /etc/php5/php-fpm.conf /etc/php5/fpm.d/www.conf
  sed -i '/^include\s/ s:^:#:' /etc/php5/fpm.d/www.conf
}

email_cron_job() {
  echo "Setup[cron-job]"
  local root_crontab='/etc/crontabs/root'
  local cron_task_dir='/etc/periodic/1min'
  local cron_task='/etc/periodic/1min/email_queue_processing'
  local process_email="/var/www/passbolt/app/Console/cake EmailQueue.sender --quiet"

  mkdir -p $cron_task_dir

  echo "* * * * * run-parts $cron_task_dir" >> $root_crontab
  echo "#!/bin/sh" > $cron_task
  chmod +x $cron_task
  echo "su -c \"$process_email\" -ls /bin/bash nginx" >> $cron_task

  crond -f -c /etc/crontabs
}

gpg_import_key

if [ ! -f $core_config ]; then
  core_setup
fi

if [ ! -f $db_config ]; then
  db_setup
fi

if [ ! -f $app_config ]; then
  app_setup
fi

if [ ! -f $email_config ]; then
  email_setup
fi

php_fpm_setup

install

php-fpm5

nginx -g "pid /tmp/nginx.pid; daemon off;" &

email_cron_job
