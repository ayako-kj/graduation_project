#!/usr/bin/env bash
set -o errexit

bundle install
bundle exec rails assets:precompile
bundle exec rails assets:clean
bundle exec rails db:migrate
bundle exec rails db:seed
bundle exec rails admin:reset_password
bundle exec rails actual_leaves:sync_from_requests
