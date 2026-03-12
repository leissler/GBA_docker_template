.PHONY: help default \
        docker-build-base docker-build-dusk docker-build-butano \
        compile-base compile-dusk compile-butano \
        clean-docker-stamps

PROJECT_NAME := $(notdir $(CURDIR))
SOURCE_DIR := $(abspath ./source)
STAMP_DIR := .docker-stamps

BASE_IMAGE := dkarm_base:local
DUSK_IMAGE := dkarm_dusk:local
BUTANO_IMAGE := dkarm_butano:local

BASE_STAMP := $(STAMP_DIR)/base.stamp
DUSK_STAMP := $(STAMP_DIR)/dusk.stamp
BUTANO_STAMP := $(STAMP_DIR)/butano.stamp

default: help

help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
	awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

$(STAMP_DIR):
	mkdir -p $(STAMP_DIR)

$(BASE_STAMP): docker/base/Dockerfile | $(STAMP_DIR)
	@if docker image inspect $(BASE_IMAGE) > /dev/null 2>&1; then \
		echo "Rebuilding $(BASE_IMAGE) because Dockerfile changed..."; \
	else \
		echo "Docker image $(BASE_IMAGE) not found, building it..."; \
	fi
	docker build -f docker/base/Dockerfile -t $(BASE_IMAGE) .
	@touch $(BASE_STAMP)

$(DUSK_STAMP): docker/dusk/Dockerfile $(BASE_STAMP) | $(STAMP_DIR)
	@if docker image inspect $(DUSK_IMAGE) > /dev/null 2>&1; then \
		echo "Rebuilding $(DUSK_IMAGE) because Dockerfile or base image changed..."; \
	else \
		echo "Docker image $(DUSK_IMAGE) not found, building it..."; \
	fi
	docker build -f docker/dusk/Dockerfile -t $(DUSK_IMAGE) .
	@touch $(DUSK_STAMP)

$(BUTANO_STAMP): docker/butano/Dockerfile $(DUSK_STAMP) | $(STAMP_DIR)
	@if docker image inspect $(BUTANO_IMAGE) > /dev/null 2>&1; then \
		echo "Rebuilding $(BUTANO_IMAGE) because Dockerfile or parent image changed..."; \
	else \
		echo "Docker image $(BUTANO_IMAGE) not found, building it..."; \
	fi
	docker build -f docker/butano/Dockerfile -t $(BUTANO_IMAGE) .
	@touch $(BUTANO_STAMP)

docker-build-base: $(BASE_STAMP) ## Build base docker image

docker-build-dusk: $(DUSK_STAMP) ## Build dusk docker image

docker-build-butano: $(BUTANO_STAMP) ## Build butano docker image

compile-base: $(BASE_STAMP) ## Compile game in ./source with CMD on base docker image
	@if ! docker image inspect $(BASE_IMAGE) > /dev/null 2>&1; then \
		rm -f $(BASE_STAMP); \
		$(MAKE) $(BASE_STAMP); \
	fi
	docker run -it --rm -v "$(SOURCE_DIR):/source" $(BASE_IMAGE) -l -c "$(CMD)"

compile-dusk: $(DUSK_STAMP) ## Compile game in ./source with CMD on dusk docker image
	@if ! docker image inspect $(DUSK_IMAGE) > /dev/null 2>&1; then \
		rm -f $(DUSK_STAMP); \
		$(MAKE) $(DUSK_STAMP); \
	fi
	docker run -it --rm -v "$(SOURCE_DIR):/source" $(DUSK_IMAGE) -l -c "$(CMD)"

compile-butano: $(BUTANO_STAMP) ## Compile game in ./source with CMD on butano docker image
	@if ! docker image inspect $(BUTANO_IMAGE) > /dev/null 2>&1; then \
		rm -f $(BUTANO_STAMP); \
		$(MAKE) $(BUTANO_STAMP); \
	fi
	docker run -it --rm -v "$(SOURCE_DIR):/source" $(BUTANO_IMAGE) -l -c "$(CMD)"
	@if [ -f "$(SOURCE_DIR)/source.gba" ]; then \
		cp "$(SOURCE_DIR)/source.gba" "./$(PROJECT_NAME).gba"; \
		echo "Created ./$(PROJECT_NAME).gba"; \
	fi

clean-docker-stamps: ## Remove local docker stamp files
	rm -rf $(STAMP_DIR)
