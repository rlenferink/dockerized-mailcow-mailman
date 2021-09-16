# Installing Mailcow and Mailman3 based on dockerized versions

## Introduction

This guide aims to install and configure [mailcow-dockerized](https://github.com/mailcow/mailcow-dockerized) with [docker-mailman](https://github.com/maxking/docker-mailman) and to provide some useful scripts.

There are some guides and projects on the internet, but there are not up to date and/or incomplete in documentation or configuration. This guide is based on the work of:

- [mailcow-mailman3-dockerized](https://github.com/Shadowghost/mailcow-mailman3-dockerized) by [Shadowghost](https://github.com/Shadowghost)
- [mailman-mailcow-integration](https://gitbucket.pgollor.de/docker/mailman-mailcow-integration)

After finishing this guide, [mailcow-dockerized](https://github.com/mailcow/mailcow-dockerized) and [docker-mailman](https://github.com/maxking/docker-mailman) will run and *Apache* as a reverse proxy will serve the web frontends.

The operating system used is an *Ubuntu 20.04 LTS*.

## Disclaimer

I'm not responsible for any data loss, hardware damage or broken keyboards. This guide comes without any warranty. Make backups before starting, 'coze: **No backup no pity!**

## Installation

This guide ist based on different steps:

1. DNS setup
1. Install *Apache* as a reverse proxy
1. Obtain ssl certificates with *Let's Encrypt*
1. Install *Mailcow* with *Mailman* integration
1. Install *Mailman*
1. 🏃 Run

### DNS setup

Most of the configuration ist covered by *Mailcow*s [DNS setup](https://mailcow.github.io/mailcow-dockerized-docs/prerequisite-dns/). After finishing this setup add another subdomain for *Mailman*, e.g. `lists.example.org` that points to the same server:

```
# Name    Type       Value
lists     IN A       1.2.3.4
lists     IN AAAA    dead:beef
```

### Install *Apache* as a reverse proxy

Install *Apache*, e.g. with this guide from *Digital Ocean*: [How To Install the Apache Web Server on Ubuntu 20.04](https://www.digitalocean.com/community/tutorials/how-to-install-the-apache-web-server-on-ubuntu-20-04).

Activate certain *Apache* modules (as *root* or *sudo*):

```
a2enmod rewrite proxy proxy_http headers ssl wsgi proxy_uwsgi http2
```

Maybe you have to install further packages to get these modules. This [PPA](https://launchpad.net/~ondrej/+archive/ubuntu/apache2) by *Ondřej Surý* may help you.

#### vhost configuration

Copy the `apache/mailcow.conf` and the `apache/mailman.conf` to the *Apache* conf folder `sites-available` (e.g. under `/etc/apache2/sites-available`).

Change in `mailcow.conf`:
- `MAILCOW_HOSTNAME` to your **MAILCOW_HOSTNAME**

Change in `mailman.conf`:
- `MAILMAN_DOMAIN` to your *Mailman* domain (e.g. `lists.example.org`)

**Don't activate the configuration, as the ssl certificates and directories are missing yet.**


### Obtain ssl certificates with *Let's Encrypt*

Check if your DNS config is available over the internet and points to the right IP addresses, e.g. with [MXToolBox](https://mxtoolbox.com):

- https://mxtoolbox.com/SuperTool.aspx?action=a%3aMAILCOW_HOSTNAME
- https://mxtoolbox.com/SuperTool.aspx?action=aaaa%3aMAILCOW_HOSTNAME
- https://mxtoolbox.com/SuperTool.aspx?action=a%3aMAILMAN_DOMAIN
- https://mxtoolbox.com/SuperTool.aspx?action=aaaa%3aMAILMAN_DOMAIN

Install `certbot` (as *root* or *sudo*):

```
apt install certbot
```

Get the desired certificates (as *root* or *sudo*):

```
certbot certonly -d MAILCOW_HOSTNAME
certbot certonly -d MAILMAN_DOMAIN
```

### Install *Mailcow* with *Mailman* integration

**install Mailcow**

Follow the [Mailcow installation](https://mailcow.github.io/mailcow-dockerized-docs/i_u_m_install/). **Omit step 5 and do not pull and up with `docker-compose`!**

**conf Mailcow**

This is also **Step 4** in the official *Mailcow installation* (`nano mailcow.conf`). So change to your needs and alter the following variables:

```
HTTP_PORT=18080
HTTP_BIND=127.0.0.1
HTTPS_PORT=18443
HTTPS_BIND=127.0.0.1

SKIP_LETS_ENCRYPT=y

SNAT_TO_SOURCE=1.2.3.4 # change this to your server ip
SNAT6_TO_SOURCE=dead:beef # change this to your global ipv6
```

**add Mailman integration**

Create the file `/opt/mailcow-dockerized/docker-compose.override.yml` (e.g. with `nano`) and add the following lines:

```
version: '2.1'

services:
  postfix-mailcow:
    volumes:
      - /opt/mailman:/opt/mailman
    networks:
      - docker-mailman_mailman

networks:
  docker-mailman_mailman:
    external: true
```

Create the file `/opt/mailcow-dockerized/data/conf/postfix/extra.cf` (e.g. with `nano`) and add the following lines:

```
# mailman

recipient_delimiter = +
unknown_local_recipient_reject_code = 550
owner_request_special = no

local_recipient_maps =
  regexp:/opt/mailman/core/var/data/postfix_lmtp,
  proxy:unix:passwd.byname,
  $alias_maps
virtual_mailbox_maps =
  proxy:mysql:/opt/postfix/conf/sql/mysql_virtual_mailbox_maps.cf,
  regexp:/opt/mailman/core/var/data/postfix_lmtp
transport_maps =
  pcre:/opt/postfix/conf/custom_transport.pcre,
  pcre:/opt/postfix/conf/local_transport,
  proxy:mysql:/opt/postfix/conf/sql/mysql_relay_ne.cf,
  proxy:mysql:/opt/postfix/conf/sql/mysql_transport_maps.cf,
  regexp:/opt/mailman/core/var/data/postfix_lmtp
relay_domains =
  proxy:mysql:/opt/postfix/conf/sql/mysql_virtual_relay_domain_maps.cf,
  regexp:/opt/mailman/core/var/data/postfix_domains
relay_recipient_maps =
  proxy:mysql:/opt/postfix/conf/sql/mysql_relay_recipient_maps.cf,
  regexp:/opt/mailman/core/var/data/postfix_lmtp
```

**ssl certificates**

As we proxying *Mailcow*, we need to copy the ssl certificates into the *Mailcow* file structure. This task will do the script `renew-ssl.sh` for us:

- copy the file to `/opt/mailcow-dockerized`
- change **MAILCOW_HOSTNAME** to your *Mailcow* hostname
- make it executable (`chmod a+x renew-ssl.sh`)
- **do not run it yet, as we first need Mailman**

You have to put the script into *cron*, so that new certificates will be copied. Execute as *root* or *sudo*:

```
crontab -e
```

To run the script every day at 5am, add:

```
0   5  *   *   *     /opt/mailcow-dockerized/renew-ssl.sh
```

### Install *Mailman*

Basicly follow the instructions at [docker-mailman](https://github.com/maxking/docker-mailman). As there are a lot, here is a short description what to do:

As *root* or *sudo*:

```
cd /opt
mkdir -p mailman/core
mkdir -p mailman/web
git clone https://github.com/maxking/docker-mailman
cd docker-mailman
```

**conf Mailman**

Create a long key for *Hyperkitty*, e.g. with the linux command `cat /dev/urandom | tr -dc a-zA-Z0-9 | head -c30; echo`. Save this key for a moment as HYPERKITTY_KEY.

Create a long password for the database, e.g. with the linux command `cat /dev/urandom | tr -dc a-zA-Z0-9 | head -c30; echo`. Save this password for a moment as DBPASS.

Create a long key for *Django*, e.g. with the linux command `cat /dev/urandom | tr -dc a-zA-Z0-9 | head -c30; echo`. Save this key for a moment as DJANGO_KEY.

Create the file `/opt/docker-mailman/docker-compose.override.yaml` and replace `HYPERKITTY_KEY`, `DBPASS` and `DJANGO_KEY` with the generated values:

```
version: '2'

services:
  mailman-core:
    environment:
    - DATABASE_URL=postgres://mailman:DBPASS@database/mailmandb
    - HYPERKITTY_API_KEY=HYPERKITTY_KEY
    - TZ=Europe/Berlin
    - MTA=postfix
    restart: always
    networks:
      - mailman

  mailman-web:
    environment:
    - DATABASE_URL=postgres://mailman:DBPASS@database/mailmandb
    - HYPERKITTY_API_KEY=HYPERKITTY_KEY
    - TZ=Europe/Berlin
    - SECRET_KEY=DJANGO_KEY
    - SERVE_FROM_DOMAIN=MAILMAN_DOMAIN # e.g. lists.example.org
    - MAILMAN_ADMIN_USER=admin # the admin user
    - MAILMAN_ADMIN_EMAIL=admin@example.org # the admin mail address
    - UWSGI_STATIC_MAP=/static=/opt/mailman-web-data/static
    restart: always

  database:
    environment:
    - POSTGRES_PASSWORD=DBPASS
    restart: always
```

At `mailman-web` fill in correct values for `SERVE_FROM_DOMAIN` (e.g. `lists.example.org`), `MAILMAN_ADMIN_USER` and `MAILMAN_ADMIN_EMAIL`. You need the admin credential to log into the web interface (*Pistorius*). For setting **the password for the first time** use the *Forgot password* function in the web interface.

Please read [Mailman-web](https://github.com/maxking/docker-mailman#mailman-web-1) and [Mailman-core](https://github.com/maxking/docker-mailman#mailman-core-1) for further informations.

**conf Mailman core and Mailman web**

Create the file `/opt/mailman/core/mailman-extra.cfg` with the following content. `mailman@example.org` should be pointing to a valid mail box.

```
[mailman]
default_language: de
site_owner: mailman@example.org
```

Create the file `/opt/mailman/web/settings_local.py` with the following content. `mailman@example.org` should be pointing to a valid mail box.

```
# locale
LANGUAGE_CODE = 'de-de'

# disable social authentication
SOCIALACCOUNT_PROVIDERS = {}

# change it
DEFAULT_FROM_EMAIL = 'mailman@example.org'

DEBUG = False
```


### 🏃 Run

Run (as *root* or *sudo*)

```
a2ensite mailcow.conf
a2ensite mailman.conf
systemctl restart apache2

cd /opt/docker-mailman
docker-compose pull
docker-compose up -d

cd /opt/mailcow-dockerized/
docker-compose pull
./renew-ssl.sh
```

**Wait a few minutes!** The containers have to create there databases and config files. This can last up to 1 minute and more.

## Remarks

### New lists aren't recognized by postfix instantly

When you create a new list and try to immediately send an e-mail, *postfix* responses with `User doesn't exist`, because *postfix* won't deliver it to *Mailman* yet. The configuration at `/opt/mailman/core/var/data/postfix_lmtp` is not instantly updated. If you need the list instantly, restart *postifx* manually:

```
cd /opt/mailcow-dockerized
docker-compose restart postfix-mailcow
```


## Update

**Mailcow** has it's own update script in `/opt/mailcow-dockerized/update.sh'. Fruther informations [in the docs](https://mailcow.github.io/mailcow-dockerized-docs/i_u_m_update/).

For **Mailman** just fetch the newest version from the [github repository](https://github.com/maxking/docker-mailman).

## Backup

**Mailcow** has an own backup script. [Read the docs](https://mailcow.github.io/mailcow-dockerized-docs/b_n_r_backup/) for further informations.

**Mailman** won't state backup instructions in the README.md. In the [gitbucket of pgollor](https://gitbucket.pgollor.de/docker/mailman-mailcow-integration/blob/master/mailman-backup.sh) is a script that may be helpful.
