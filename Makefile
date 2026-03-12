.PHONY: help default \
        docker-build-base docker-build-dusk docker-build-butano \
        compile-base compile-dusk compile-butano \
        check-container-runtime \
        clean-docker-stamps

PROJECT_NAME := $(notdir $(CURDIR))
SOURCE_DIR := $(abspath ./source)
STAMP_DIR := .docker-stamps

BASE_IMAGE := dkarm_base:local
DUSK_IMAGE := dkarm_dusk:local
BUTANO_IMAGE := dkarm_butano:local

CONTAINER_RUNTIME ?= $(shell \
	if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then echo docker; \
	elif command -v podman >/dev/null 2>&1 && podman info >/dev/null 2>&1; then echo podman; \
	elif command -v docker >/dev/null 2>&1; then echo docker; \
	elif command -v podman >/dev/null 2>&1; then echo podman; \
	fi)
DOCKER_START_TIMEOUT ?= 60

BASE_STAMP := $(STAMP_DIR)/base.stamp
DUSK_STAMP := $(STAMP_DIR)/dusk.stamp
BUTANO_STAMP := $(STAMP_DIR)/butano.stamp

default: help

help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
	awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

$(STAMP_DIR):
	mkdir -p $(STAMP_DIR)

check-container-runtime: ## Ensure container runtime is available and running
	@set -e; \
	if [ -z "$(CONTAINER_RUNTIME)" ]; then \
		echo "No supported container runtime found. Install docker or podman."; \
		exit 1; \
	fi; \
	if ! command -v "$(CONTAINER_RUNTIME)" >/dev/null 2>&1; then \
		echo "Container runtime '$(CONTAINER_RUNTIME)' is not installed."; \
		exit 1; \
	fi; \
	if "$(CONTAINER_RUNTIME)" info >/dev/null 2>&1; then \
		exit 0; \
	fi; \
	if [ "$(CONTAINER_RUNTIME)" = "docker" ] && command -v open >/dev/null 2>&1 && [ -d "/Applications/Docker.app" ]; then \
		echo "Docker daemon is not running. Starting Docker Desktop..."; \
		open -a Docker; \
		i=0; \
		until "$(CONTAINER_RUNTIME)" info >/dev/null 2>&1; do \
			i=$$((i + 1)); \
			if [ $$i -ge "$(DOCKER_START_TIMEOUT)" ]; then \
				echo "Timed out waiting for Docker Desktop after $(DOCKER_START_TIMEOUT)s."; \
				exit 1; \
			fi; \
			sleep 1; \
		done; \
		echo "Docker Desktop is ready."; \
	elif [ "$(CONTAINER_RUNTIME)" = "docker" ] && grep -qi microsoft /proc/version 2>/dev/null; then \
		echo "Docker daemon is not running. Starting Docker Desktop from WSL..."; \
		if command -v powershell.exe >/dev/null 2>&1; then \
			powershell.exe -NoProfile -NonInteractive -Command "Start-Process 'C:\\Program Files\\Docker\\Docker\\Docker Desktop.exe'" >/dev/null 2>&1 || true; \
		elif command -v cmd.exe >/dev/null 2>&1; then \
			cmd.exe /C start "" "C:\\Program Files\\Docker\\Docker\\Docker Desktop.exe" >/dev/null 2>&1 || true; \
		fi; \
		i=0; \
		until "$(CONTAINER_RUNTIME)" info >/dev/null 2>&1; do \
			i=$$((i + 1)); \
			if [ $$i -ge "$(DOCKER_START_TIMEOUT)" ]; then \
				echo "Timed out waiting for Docker Desktop after $(DOCKER_START_TIMEOUT)s."; \
				exit 1; \
			fi; \
			sleep 1; \
		done; \
		echo "Docker Desktop is ready."; \
	else \
		echo "Container runtime '$(CONTAINER_RUNTIME)' is installed but not running."; \
		echo "Start the runtime or override with CONTAINER_RUNTIME=podman."; \
		exit 1; \
	fi

$(BASE_STAMP): docker/base/Dockerfile | $(STAMP_DIR)
	@$(MAKE) check-container-runtime
	@if $(CONTAINER_RUNTIME) image inspect $(BASE_IMAGE) > /dev/null 2>&1; then \
		echo "Rebuilding $(BASE_IMAGE) because Dockerfile changed..."; \
	else \
		echo "Docker image $(BASE_IMAGE) not found, building it..."; \
	fi
	$(CONTAINER_RUNTIME) build -f docker/base/Dockerfile -t $(BASE_IMAGE) .
	@touch $(BASE_STAMP)

$(DUSK_STAMP): docker/dusk/Dockerfile $(BASE_STAMP) | $(STAMP_DIR)
	@$(MAKE) check-container-runtime
	@if $(CONTAINER_RUNTIME) image inspect $(DUSK_IMAGE) > /dev/null 2>&1; then \
		echo "Rebuilding $(DUSK_IMAGE) because Dockerfile or base image changed..."; \
	else \
		echo "Docker image $(DUSK_IMAGE) not found, building it..."; \
	fi
	$(CONTAINER_RUNTIME) build -f docker/dusk/Dockerfile -t $(DUSK_IMAGE) .
	@touch $(DUSK_STAMP)

$(BUTANO_STAMP): docker/butano/Dockerfile $(DUSK_STAMP) | $(STAMP_DIR)
	@$(MAKE) check-container-runtime
	@if $(CONTAINER_RUNTIME) image inspect $(BUTANO_IMAGE) > /dev/null 2>&1; then \
		echo "Rebuilding $(BUTANO_IMAGE) because Dockerfile or parent image changed..."; \
	else \
		echo "Docker image $(BUTANO_IMAGE) not found, building it..."; \
	fi
	$(CONTAINER_RUNTIME) build -f docker/butano/Dockerfile -t $(BUTANO_IMAGE) .
	@touch $(BUTANO_STAMP)

docker-build-base: $(BASE_STAMP) ## Build base docker image

docker-build-dusk: $(DUSK_STAMP) ## Build dusk docker image

docker-build-butano: $(BUTANO_STAMP) ## Build butano docker image

compile-base: check-container-runtime $(BASE_STAMP) ## Compile game in ./source with CMD on base docker image
	@if ! $(CONTAINER_RUNTIME) image inspect $(BASE_IMAGE) > /dev/null 2>&1; then \
		rm -f $(BASE_STAMP); \
		$(MAKE) $(BASE_STAMP); \
	fi
	$(CONTAINER_RUNTIME) run -it --rm -v "$(SOURCE_DIR):/source" $(BASE_IMAGE) -l -c "$(CMD)"

compile-dusk: check-container-runtime $(DUSK_STAMP) ## Compile game in ./source with CMD on dusk docker image
	@if ! $(CONTAINER_RUNTIME) image inspect $(DUSK_IMAGE) > /dev/null 2>&1; then \
		rm -f $(DUSK_STAMP); \
		$(MAKE) $(DUSK_STAMP); \
	fi
	$(CONTAINER_RUNTIME) run -it --rm -v "$(SOURCE_DIR):/source" $(DUSK_IMAGE) -l -c "$(CMD)"

compile-butano: check-container-runtime $(BUTANO_STAMP) ## Compile game in ./source with CMD on butano docker image
	@if ! $(CONTAINER_RUNTIME) image inspect $(BUTANO_IMAGE) > /dev/null 2>&1; then \
		rm -f $(BUTANO_STAMP); \
		$(MAKE) $(BUTANO_STAMP); \
	fi
	$(CONTAINER_RUNTIME) run -it --rm -v "$(SOURCE_DIR):/source" $(BUTANO_IMAGE) -l -c "$(CMD)"
	@if [ -f "$(SOURCE_DIR)/source.gba" ]; then \
		cp "$(SOURCE_DIR)/source.gba" "./$(PROJECT_NAME).gba"; \
		echo "Created ./$(PROJECT_NAME).gba"; \
	fi

clean-docker-stamps: ## Remove local docker stamp files
	rm -rf $(STAMP_DIR)
