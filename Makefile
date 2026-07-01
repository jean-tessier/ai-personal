# Single deterministic sensor. One command; the exit code is the gate.
.PHONY: check

check:
	bash scripts/validate.sh
