# Single deterministic sensor. One command; the exit code is the gate.
.PHONY: check test-install test-install-docker

check:
	bash scripts/validate.sh
	node --test scripts/*.test.ts
	node --test evals/*/report.test.mjs
	npx tsc --noEmit

test-install:
	bash scripts/test-install.sh

test-install-docker:
	bash scripts/test-install-docker.sh
