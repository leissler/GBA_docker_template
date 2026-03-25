.PHONY: help default \
        docker-build-base docker-build-dusk docker-build-butano \
        compile-base compile-dusk compile-butano \
        run run-debug run-no-build run-debug-no-build \
        clean clean-all \
        check-container-runtime \
        clean-docker-stamps

PROJECT_NAME := $(notdir $(CURDIR))
SOURCE_DIR := $(abspath ./source)
SOURCE_DIR_MOUNT ?= $(SOURCE_DIR)
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
AUTO_CLEAN_MAKE ?= auto

BASE_STAMP := $(STAMP_DIR)/base.stamp
DUSK_STAMP := $(STAMP_DIR)/dusk.stamp
BUTANO_STAMP := $(STAMP_DIR)/butano.stamp

default: help

help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
	awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Variables:"
	@echo "  SOURCE_DIR_MOUNT=<path-on-daemon>  Override mounted source path for remote Docker daemons"

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
	@RUN_CMD=$$(printf '%s' "$(CMD)"); \
	if [ "$(AUTO_CLEAN_MAKE)" != "0" ]; then \
		case "$$RUN_CMD" in \
			make*) \
				NEEDS_CLEAN=0; \
				if [ "$(AUTO_CLEAN_MAKE)" = "1" ]; then \
					NEEDS_CLEAN=1; \
				elif [ "$(AUTO_CLEAN_MAKE)" = "auto" ]; then \
					if ls "$(SOURCE_DIR)/build"/*.d >/dev/null 2>&1 && \
					   grep -E -q '/source/source/|/workspaces/' "$(SOURCE_DIR)/build"/*.d; then \
						NEEDS_CLEAN=1; \
					fi; \
				fi; \
				if [ "$$NEEDS_CLEAN" = "1" ]; then \
					echo "Running clean before build (AUTO_CLEAN_MAKE=$(AUTO_CLEAN_MAKE))..."; \
					RUN_CMD="make clean && $$RUN_CMD"; \
				fi ;; \
		esac; \
	fi; \
	MOUNT_SOURCE="$(SOURCE_DIR_MOUNT)"; \
	if [ "$(CONTAINER_RUNTIME)" = "docker" ]; then \
		DAEMON_HOST="$$($(CONTAINER_RUNTIME) context inspect --format '{{ (index .Endpoints "docker").Host }}' 2>/dev/null || true)"; \
		case "$$DAEMON_HOST" in \
			""|unix://*|npipe://*) ;; \
			*) \
				if [ "$$MOUNT_SOURCE" = "$(SOURCE_DIR)" ]; then \
					echo "Detected remote Docker daemon: $$DAEMON_HOST"; \
					echo "Bind mount source must be a path on the daemon host."; \
					echo "Retry with SOURCE_DIR_MOUNT=<daemon-host-absolute-path-to-source>."; \
					exit 1; \
				fi ;; \
		esac; \
	fi; \
	$(CONTAINER_RUNTIME) run -it --rm -v "$$MOUNT_SOURCE:/source" $(BASE_IMAGE) -l -c "$$RUN_CMD"

compile-dusk: check-container-runtime $(DUSK_STAMP) ## Compile game in ./source with CMD on dusk docker image
	@if ! $(CONTAINER_RUNTIME) image inspect $(DUSK_IMAGE) > /dev/null 2>&1; then \
		rm -f $(DUSK_STAMP); \
		$(MAKE) $(DUSK_STAMP); \
	fi
	@RUN_CMD=$$(printf '%s' "$(CMD)"); \
	if [ "$(AUTO_CLEAN_MAKE)" != "0" ]; then \
		case "$$RUN_CMD" in \
			make*) \
				NEEDS_CLEAN=0; \
				if [ "$(AUTO_CLEAN_MAKE)" = "1" ]; then \
					NEEDS_CLEAN=1; \
				elif [ "$(AUTO_CLEAN_MAKE)" = "auto" ]; then \
					if ls "$(SOURCE_DIR)/build"/*.d >/dev/null 2>&1 && \
					   grep -E -q '/source/source/|/workspaces/' "$(SOURCE_DIR)/build"/*.d; then \
						NEEDS_CLEAN=1; \
					fi; \
				fi; \
				if [ "$$NEEDS_CLEAN" = "1" ]; then \
					echo "Running clean before build (AUTO_CLEAN_MAKE=$(AUTO_CLEAN_MAKE))..."; \
					RUN_CMD="make clean && $$RUN_CMD"; \
				fi ;; \
		esac; \
	fi; \
	MOUNT_SOURCE="$(SOURCE_DIR_MOUNT)"; \
	if [ "$(CONTAINER_RUNTIME)" = "docker" ]; then \
		DAEMON_HOST="$$($(CONTAINER_RUNTIME) context inspect --format '{{ (index .Endpoints "docker").Host }}' 2>/dev/null || true)"; \
		case "$$DAEMON_HOST" in \
			""|unix://*|npipe://*) ;; \
			*) \
				if [ "$$MOUNT_SOURCE" = "$(SOURCE_DIR)" ]; then \
					echo "Detected remote Docker daemon: $$DAEMON_HOST"; \
					echo "Bind mount source must be a path on the daemon host."; \
					echo "Retry with SOURCE_DIR_MOUNT=<daemon-host-absolute-path-to-source>."; \
					exit 1; \
				fi ;; \
		esac; \
	fi; \
	$(CONTAINER_RUNTIME) run -it --rm -v "$$MOUNT_SOURCE:/source" $(DUSK_IMAGE) -l -c "$$RUN_CMD"

compile-butano: check-container-runtime $(BUTANO_STAMP) ## Compile game in ./source with CMD on butano docker image
	@if ! $(CONTAINER_RUNTIME) image inspect $(BUTANO_IMAGE) > /dev/null 2>&1; then \
		rm -f $(BUTANO_STAMP); \
		$(MAKE) $(BUTANO_STAMP); \
	fi
	@RUN_CMD=$$(printf '%s' "$(CMD)"); \
	if [ "$(AUTO_CLEAN_MAKE)" != "0" ]; then \
		case "$$RUN_CMD" in \
			make*) \
				NEEDS_CLEAN=0; \
				if [ "$(AUTO_CLEAN_MAKE)" = "1" ]; then \
					NEEDS_CLEAN=1; \
				elif [ "$(AUTO_CLEAN_MAKE)" = "auto" ]; then \
					if ls "$(SOURCE_DIR)/build"/*.d >/dev/null 2>&1 && \
					   grep -E -q '/source/source/|/workspaces/' "$(SOURCE_DIR)/build"/*.d; then \
						NEEDS_CLEAN=1; \
					fi; \
				fi; \
				if [ "$$NEEDS_CLEAN" = "1" ]; then \
					echo "Running clean before build (AUTO_CLEAN_MAKE=$(AUTO_CLEAN_MAKE))..."; \
					RUN_CMD="make clean && $$RUN_CMD"; \
				fi ;; \
		esac; \
	fi; \
	MOUNT_SOURCE="$(SOURCE_DIR_MOUNT)"; \
	if [ "$(CONTAINER_RUNTIME)" = "docker" ]; then \
		DAEMON_HOST="$$($(CONTAINER_RUNTIME) context inspect --format '{{ (index .Endpoints "docker").Host }}' 2>/dev/null || true)"; \
		case "$$DAEMON_HOST" in \
			""|unix://*|npipe://*) ;; \
			*) \
				if [ "$$MOUNT_SOURCE" = "$(SOURCE_DIR)" ]; then \
					echo "Detected remote Docker daemon: $$DAEMON_HOST"; \
					echo "Bind mount source must be a path on the daemon host."; \
					echo "Retry with SOURCE_DIR_MOUNT=<daemon-host-absolute-path-to-source>."; \
					exit 1; \
				fi ;; \
		esac; \
	fi; \
	$(CONTAINER_RUNTIME) run -it --rm -v "$$MOUNT_SOURCE:/source" $(BUTANO_IMAGE) -l -c "$$RUN_CMD"
	@if [ -f "$(SOURCE_DIR)/source.gba" ]; then \
		cp "$(SOURCE_DIR)/source.gba" "./$(PROJECT_NAME).gba"; \
		echo "Created ./$(PROJECT_NAME).gba"; \
	fi

run: ## Build release ROM and launch host emulator
	bash scripts/run_and_launch_rom.sh release

run-debug: ## Build debug ROM and launch host emulator
	bash scripts/run_and_launch_rom.sh debug

run-no-build: ## Launch release ROM without rebuilding
	bash scripts/run_and_launch_rom.sh release --no-build

run-debug-no-build: ## Launch debug ROM without rebuilding
	bash scripts/run_and_launch_rom.sh debug --no-build

clean-docker-stamps: ## Remove local docker stamp files
	rm -rf $(STAMP_DIR)

clean: ## Remove generated ROM/build outputs
	bash scripts/clean_all_outputs.sh local

clean-all: clean clean-docker-stamps ## Remove generated outputs and docker stamp files
