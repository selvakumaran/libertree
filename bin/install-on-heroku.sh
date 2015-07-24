#!/bin/bash
# Bail out on any error
set -e

# ----------------------------------------------------------------------------
# Pre-flight checks

echo '***************************************************'
echo 'If you do not already have a Heroku account, go to https://signup.heroku.com/dc to create one.'
echo '***************************************************'
echo

which ruby || (echo 'Ruby must be installed.' && exit 1)
which git || (echo 'git must be installed.' && exit 2)
which heroku || (echo 'The Heroku CLI must be installed.  https://toolbelt.heroku.com/' && exit 3)

# ----------------------------------------------------------------------------
# Setup

INSTALLER_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
WORKING_DIR=$(readlink -f ${1:-$INSTALLER_DIR/../../libertree-heroku})
echo "(Using temporary working directory: $WORKING_DIR)"
FRONTEND_BRANCH=heroku
DB_REPO_BRANCH=vue-js
BACKEND_BRANCH=heroku

mkdir -p $WORKING_DIR

# ----------------------------------------------------------------------------
# Frontend

cd $WORKING_DIR
git clone https://github.com/Libertree/libertree-frontend-ramaze.git || echo '(failed to clone libertree-frontend-ramaze)'
cd libertree-frontend-ramaze
git checkout $FRONTEND_BRANCH

heroku auth:whoami || heroku login

echo
echo '***************************************************'
echo 'Please enter the name of the Heroku application that will be created.'
echo 'Try to make it unique.  Press Enter to accept the default shown.'
echo
SUGGESTED_APP_NAME="libertree-$RANDOM"
echo -n "Heroku app name ($SUGGESTED_APP_NAME): "
read HEROKU_APP_NAME
if [[ -z "${HEROKU_APP_NAME// }" ]]; then
  HEROKU_APP_NAME=$SUGGESTED_APP_NAME
fi
heroku apps:create $HEROKU_APP_NAME
WEB_ADDRESS="http://$HEROKU_APP_NAME.herokuapp.com"
HEROKU_WEBSOCKET_BACKEND_APP_NAME="$HEROKU_APP_NAME-websocket"
HEROKU_JOB_PROCESSOR_BACKEND_APP_NAME="$HEROKU_APP_NAME-job-processor"
WEBSOCKET_HOST="$HEROKU_BACKEND_APP_NAME.herokuapp.com"

git push heroku `git rev-parse --abbrev-ref HEAD`:master

heroku config:set LANG=en_GB.UTF-8 LIBERTREE_API_MIN_TIME_BETWEEN=5 LIBERTREE_ENV=production LIBERTREE_FRONTEND_URL_BASE=$WEB_ADDRESS LIBERTREE_GRAPHICSMAGICK=true LIBERTREE_DOMAIN="$HEROKU_APP_NAME.herokuapp.com" LIBERTREE_SIGN_UP=true LIBERTREE_THEMES=default LIBERTREE_TITLE_INSERT=Heroku\ Tree LIBERTREE_WEBSOCKET_JS_HOST="$WEBSOCKET_HOST" LIBERTREE_WEBSOCKET_PATH="/" LIBERTREE_WEBSOCKET_PORT=80
DATABASE_URL=$(heroku config --shell | grep DATABASE_URL | cut -d = -f 2)

# ----------------------------------------------------------------------------
# Database

IFS=' ' read -a PG_CREDS <<< $(heroku pg:credentials DATABASE | grep 'dbname=' | sed "s|[ \"]|\\n|g")
PG_DBNAME=$(echo ${PG_CREDS[0]} | cut -d '=' -f 2)
PG_HOST=$(echo ${PG_CREDS[1]} | cut -d '=' -f 2)
PG_PORT=$(echo ${PG_CREDS[2]} | cut -d '=' -f 2)
PG_USER=$(echo ${PG_CREDS[3]} | cut -d '=' -f 2)
PG_PASSWORD=$(echo ${PG_CREDS[4]} | cut -d '=' -f 2)

cd $WORKING_DIR
git clone https://github.com/Libertree/libertree-db.git || echo '(failed to clone libertree-db)'
cd libertree-db
git checkout $DB_REPO_BRANCH

echo "$PG_HOST:$PG_PORT:$PG_DBNAME:$PG_USER:$PG_PASSWORD" > .pgpass
chmod go-rwx .pgpass
echo "
production:
  host: $PG_HOST
  port: $PG_PORT
  username: $PG_USER
  password: $PG_PASSWORD
  database: $PG_DBNAME
" > database.yaml

LIBERTREE_ENV=production PGPASSFILE=.pgpass ./migrate.sh

# ----------------------------------------------------------------------------
# Backend: Websocket

cd $WORKING_DIR
git clone https://github.com/Libertree/libertree-backend-rb.git libertree-backend-rb-websocket || echo '(failed to clone libertree-backend-rb)'
cd libertree-backend-rb-websocket
git checkout $BACKEND_BRANCH

heroku apps:create $HEROKU_WEBSOCKET_BACKEND_APP_NAME

git push heroku `git rev-parse --abbrev-ref HEAD`:master

# Backend will not have its own DB, the frontend and backend will share the same DB.
heroku addons:destroy heroku-postgresql --confirm $HEROKU_WEBSOCKET_BACKEND_APP_NAME

heroku config:set LANG=en_GB.UTF-8 DATABASE_URL=$DATABASE_URL LIBERTREE_WEBSOCKET_LISTEN_HOST=0.0.0.0 LIBERTREE_DOMAIN=$BACKEND_HOST LIBERTREE_FRONTEND_URL_BASE=$WEB_ADDRESS

# Ensure DATABASE_URL is used
heroku ps:restart

# ----------------------------------------------------------------------------
# Backend: Job Processor (Local)

cd $WORKING_DIR
git clone https://github.com/Libertree/libertree-backend-rb.git libertree-backend-rb-job-processor || echo '(failed to clone libertree-backend-rb)'
cd libertree-backend-rb-job-processor
git checkout $BACKEND_BRANCH

heroku apps:create $HEROKU_JOB_PROCESSOR_BACKEND_APP_NAME

git push heroku `git rev-parse --abbrev-ref HEAD`:master

# Backend will not have its own DB, the frontend and backend will share the same DB.
heroku addons:destroy heroku-postgresql --confirm $HEROKU_JOB_PROCESSOR_BACKEND_APP_NAME

heroku config:set LANG=en_GB.UTF-8 DATABASE_URL=$DATABASE_URL LIBERTREE_TASKS=http:embed,post:add-to-rivers,river:refresh,river:refresh-all LIBERTREE_DOMAIN=$BACKEND_HOST LIBERTREE_FRONTEND_URL_BASE=$WEB_ADDRESS

heroku ps:scale web=0 jobprocessorlocal=1 --app $HEROKU_JOB_PROCESSOR_BACKEND_APP_NAME

# ----------------------------------------------------------------------------

echo
echo "Libertree installed at $WEB_ADDRESS"