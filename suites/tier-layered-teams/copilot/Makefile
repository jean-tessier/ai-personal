# Single deterministic sensor. One command; the exit code is the gate.
# Wired identically into .vscode/tasks.json and the PostToolUse hook so the human,
# the task runner, and the agent all invoke ONE path.
.PHONY: check check-java check-node

check:
	@if [ -f pom.xml ];      then $(MAKE) check-java; fi
	@if [ -f package.json ]; then $(MAKE) check-node; fi

check-java:
	mvn -q -B verify

check-node:
	npx tsc --noEmit
	npx eslint .
	npx vitest run       # Angular app: swap for `npx ng lint && npx ng test --watch=false`
