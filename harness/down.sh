#!/bin/bash
# Stop and remove the environment (containers + data volume). Secrets are kept.
cd "$(dirname "$0")/.." && docker compose -p oncallpg down -v
