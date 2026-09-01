#!/usr/bin/env bash
#
# Creates the load database if it does not exist and fills it with the fixed
# corpus (T040). Re-runnable: seed.rb replaces the corpus rather than adding a
# second one, and drops the click rows the previous run left behind.
#
#   load/seed.sh
#
# db:prepare is safe here even though the database is `shortener_load`:
# db/seeds.rb refuses to load the development fixtures under RAILS_ENV
# production, so this creates an empty schema and nothing else.

source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

bin/rails db:prepare
bin/rails runner ../load/seed.rb
