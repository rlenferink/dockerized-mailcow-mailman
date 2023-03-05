#!/bin/bash

# Request a new certificate
certbot renew --pre-hook "systemctl stop apache2" --post-hook "systemctl start apache2" --renew-hook "systemctl reload apache2" --quiet

# Ensure to load the new certificates to mailcow
cd /srv/mail/mailcow-dockerized
cp /etc/letsencrypt/live/mail.roylenferink.com/fullchain.pem ./data/assets/ssl/cert.pem
cp /etc/letsencrypt/live/mail.roylenferink.com/privkey.pem ./data/assets/ssl/key.pem

# TODO: This can be improved to only restart the services if the certificates are actually changed (e.g. by comparing a checksum) instead of restarting every day
./mailcow-compose.sh restart nginx-mailcow dovecot-mailcow postfix-mailcow

