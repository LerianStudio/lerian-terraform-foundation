.PHONY: init hooks deps

init: deps
	@echo "Initializing git hooks..."
	@hooks=$$(git rev-parse --git-path hooks) && mkdir -p "$$hooks" \
		&& cp scripts/pre-commit.sh "$$hooks/pre-commit" \
		&& cp scripts/commit-msg.sh "$$hooks/commit-msg" \
		&& chmod +x "$$hooks/pre-commit" "$$hooks/commit-msg"
	@echo "Git hooks initialized!"

deps:
	@echo "Installing dependencies..."
	@npm install --save-dev @commitlint/cli @commitlint/config-conventional
	@echo "Dependencies installed!"

hooks: init
