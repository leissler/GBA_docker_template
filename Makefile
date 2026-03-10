# Declare phony targets
.PHONY: help docker-build-base docker-build-dusk docker-build-butano compile-base compile-dusk compile-butano

# Name of the current project folder (parent of ./source)
PROJECT_NAME := $(notdir $(CURDIR))

# Default target is 'help'
default: help

# Automated help command
help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

# Docker build targets
docker-build-base: ## Build base docker image
	docker build -f docker/base/Dockerfile -t dkarm_base:local .

docker-build-dusk: ## Build dusk docker image
	$(MAKE) docker-build-base
	docker build -f docker/dusk/Dockerfile -t dkarm_dusk:local .

docker-build-butano: ## Build butano docker image
	$(MAKE) docker-build-dusk
	docker build -f docker/butano/Dockerfile -t dkarm_butano:local .

compile-base: ## Compile game in ./source with CMD on base docker image
	docker run -it --rm -v ./source:/source dkarm_base:local -l -c "$(CMD)"

compile-dusk: ## Compile game in ./source with CMD on dusk docker image
	docker run -it --rm -v ./source:/source dkarm_dusk:local -l -c "$(CMD)"

compile-butano: ## Compile game in ./source with CMD on butano docker image
	docker run -it --rm -v ./source:/source dkarm_butano:local -l -c "$(CMD)"
	@if [ -f ./source/source.gba ]; then mv ./source/source.gba ./$(PROJECT_NAME).gba; echo "Created ./$(PROJECT_NAME).gba"; fi
