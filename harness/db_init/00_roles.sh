#!/bin/bash
# Runs once at DB init (inside the db container, as the postgres superuser).
set -euo pipefail
APP_PW=$(cat /run/secrets/app_pw); AN_PW=$(cat /run/secrets/analytics_pw); MIG_PW=$(cat /run/secrets/migrator_pw)
psql -v ON_ERROR_STOP=1 -U postgres <<SQL
CREATE ROLE migrator LOGIN PASSWORD '$MIG_PW';     -- owns the schema objects; NOT superuser
CREATE ROLE app      LOGIN PASSWORD '$APP_PW';
CREATE ROLE analytics LOGIN PASSWORD '$AN_PW';
SQL
