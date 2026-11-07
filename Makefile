# OnCall-PG: one-command entry points. Requires Docker (Compose v2) and Python >= 3.11. No pip packages.
#   make up                      start PostgreSQL 17 + load + migrator containers, build the 5M-row seed (~1 min)
#   make calibrate N=5           grader validation: every reference must PASS N/N, every mutation FAIL N/N
#   make regrade                 re-grade the shipped model outputs locally (NO API key needed)
#   make generate MODELS=claude-opus-5.5,gpt-6.1-sol TRIALS=5   call models via OpenRouter (needs OPENROUTER_API_KEY)
#   make grade / make report     grade new outputs / rebuild results/summary.md
#   make prompt T=H2             print the exact prompt for a ticket
#   make down                    remove containers and data

SHELL := /bin/bash
N ?= 5
TRIALS ?= 5
MODELS ?= claude-haiku-5.5,nemotron-3-ultra-free
TICKETS ?= C1,C2,C3,C4,H1,H2,H3,H4,H5
TICKET_DIRS = $(shell for t in $$(echo $(TICKETS) | tr ',' ' '); do ls -d tickets/$${t}_* ; done)

.PHONY: up down calibrate generate grade regrade report prompt check-env

up:
	./harness/up.sh

down:
	./harness/down.sh

calibrate: up
	./harness/calibrate.sh $(N) $(TICKET_DIRS) | tee results/calibration_$$(date +%Y%m%d_%H%M).txt

check-env:
	@test -n "$$OPENROUTER_API_KEY" || { test -f .env && echo "loading .env"; } || { echo "Set OPENROUTER_API_KEY (see .env.example)"; exit 1; }

generate: check-env
	set -a; [ -f .env ] && source .env; set +a; python3 evalpg/run_eval.py generate --models $(MODELS) --tickets $(TICKETS) --trials $(TRIALS)

grade: up
	python3 evalpg/run_eval.py grade --tickets $(TICKETS)

regrade: up
	python3 evalpg/run_eval.py grade --tickets $(TICKETS) --force
	python3 evalpg/run_eval.py report

report:
	python3 evalpg/run_eval.py report

prompt:
	@python3 evalpg/run_eval.py prompt $(T)
