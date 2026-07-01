# Single deterministic sensor. One command; the exit code is the gate.
.PHONY: check test-install test-install-docker

check:
	bash scripts/validate.sh

test-install:
	bash scripts/test-install.sh

test-install-docker:
	bash scripts/test-install-docker.sh
