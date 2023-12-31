# Reset
COLOR_OFF="\033[0m"

# Regular Colors
BLACK="\033[0;30m"
RED="\033[1;31m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
PURPLE="\033[1;35m"
CYAN="\033[1;36m"
WHITE="\033[0;37m"

# load environment variable in .env
include $(shell find .env -type f -print0 | xargs -0 -I {} echo {})

# PLATFORM variable should be exported before calling make like this,
# > export PLATFORM=linux/arm64
# variable range : [linux/arm64, linux/amd64]
# default PLATFORM is linux/arm64
PLATFORM ?= linux/amd64

GIT_TAG ?= latest

REPOSITORY := docker-registry.anyflow.net

NAME := docserver

MANIFEST_GENERATOR_NAME := manifest-generator
MANIFEST_GENERATOR_VERSION := latest
DOC_PUBLISHER_NAME := doc-publisher
DOC_PUBLISHER_VERSION := latest


# Makefile lint recommends that have to use the PHONY target when It is possible to not fixed the target.
.PHONY: default
default: build_image run_image

.PHONY: clean

define exit_if_undefined
	@if [ -z "$($1)" ]; then \
		echo "$1 should be defined!"; \
		exit 1; \
	fi
endef

exit_if_git_tag_not_defined:
	$(call exit_if_undefined,GIT_TAG)

print_environment:
	@echo ${YELLOW}"================================================================================================="
	@echo "NAME : ${NAME}"
	@echo "GIT_TAG : ${GIT_TAG}"
	@echo "GITHUB_TOKEN: ${GITHUB_TOKEN}"
	@echo "PLATFORM : ${PLATFORM}"
	@echo "manifest-generator : ${REPOSITORY}/${MANIFEST_GENERATOR_NAME}:${MANIFEST_GENERATOR_VERSION}"
	@echo "================================================================================================="${COLOR_OFF}

# Need GIT_TAG, Need BUILD_IMAGE_OPTION
build_image: exit_if_git_tag_not_defined print_environment build_manifest publish_web_resources
	docker buildx build \
	--pull \
	--load \
	--platform ${PLATFORM} \
	--tag ${REPOSITORY}/${NAME}:${GIT_TAG} \
	--file ./Dockerfile \
	.

# Need GIT_TAG
push_image: build_image
	docker push ${REPOSITORY}/${NAME}:${GIT_TAG}

# Need GIT_TAG
run_image:
	@docker run --rm \
	 -p 8080:8080 \
	-t ${REPOSITORY}/${NAME}:${GIT_TAG} \
	run -c local.krakend.yaml

run_directly:
	@docker run --rm \
	 -p 8080:8080 \
	 -v "${PWD}/output:/etc/krakend/" \
	 ${KRAKEND_NAME}:${KRAKEND_VERSION} \
	 run -c local.krakend.yaml

# Need GIT_TAG
remove_image: exit_if_git_tag_not_defined
	aws ecr batch-delete-image --repository-name ${REPO_NAME} --image-ids imageTag=${GIT_TAG}

# Need GIT_TAG
inspect_image: exit_if_git_tag_not_defined
	docker manifest inspect ${REPOSITORY}/${NAME}:${GIT_TAG}

check_ancestor:
	$(eval MAIN := $(shell git ls-remote origin main | cut -f1))
	$(eval COMMON := $(shell git merge-base HEAD $(MAIN)))
	@if [ "$(MAIN)" = "$(COMMON)" ]; then \
		echo ${CYAN}"The common ancestor is the latest main branch."${COLOR_OFF}; \
	else \
		echo ${RED}"The branch needs to be rebased onto the latest main branch!"${COLOR_OFF}; \
		exit 1; \
	fi

refresh_deployment: push_image
	kubectl rollout restart deployment krakend

publish_web_resources:
	@mkdir ${OUTPUT_PATH}/contents/changelog && \
	mkdir ${OUTPUT_PATH}/contents/apispec/media && \
	docker run --rm \
		-u ${shell id -u}:${shell id -g} \
		-v "${OUTPUT_PATH}:/output" \
		-v "${PWD}/manifest:/manifest" \
		-v "${PWD}:/source_root" \
		-e GITHUB_TOKEN=${GITHUB_TOKEN} \
		-e DEFAULT_ENVIRONMENT=prod \
		${REPOSITORY}/${DOC_PUBLISHER_NAME}:${DOC_PUBLISHER_VERSION} \
		-im /source_root/CHANGELOG.md \
		-om /output/contents/changelog \
		-io /output/contents/apispec/openapi \
		-oo /output/contents/apispec/media && \
	mv ${OUTPUT_PATH}/contents/changelog/CHANGELOG.html ${OUTPUT_PATH}/contents/changelog/index.html && \
	echo ${CYAN}"CHANGELOG, swaggerUI/redoc web resources published."${COLOR_OFF}

# Should call validate_* via ${MAKE}, unless the rules use the old yamls instead of the generated newly
build_manifest: print_environment _refresh_output _refresh_builder _build_manifest _remove_intermediates

OUTPUT_PATH := ${PWD}/output

_refresh_output:
	@rm -rf ${OUTPUT_PATH} && \
	mkdir ${OUTPUT_PATH} && \
	echo ${CYAN}"output directory refreshed"${COLOR_OFF}

_refresh_builder:
	@docker pull ${REPOSITORY}/${MANIFEST_GENERATOR_NAME}:${MANIFEST_GENERATOR_VERSION} && \
	docker pull ${REPOSITORY}/${DOC_PUBLISHER_NAME}:${DOC_PUBLISHER_VERSION} && \
	echo ${CYAN}"manifest generator, doc publisher refreshed"${COLOR_OFF}

# Need GIT_TAG
_build_manifest:
	@docker run --rm \
		-u ${shell id -u}:${shell id -g} \
		-v "${OUTPUT_PATH}:/output" \
		-v "${PWD}/manifest:/manifest" \
		-v "${PWD}:/source_root" \
		${REPOSITORY}/${MANIFEST_GENERATOR_NAME}:${MANIFEST_GENERATOR_VERSION} \
		-m /manifest \
		-ak /source_root/apikeys.yaml \
		-as /source_root/apikeySpecs.yaml \
		-v ${GIT_TAG} \
		-o /output && \
	echo ${CYAN}"(openapi.yaml, krakend.yaml) per environments created."${COLOR_OFF}

_remove_intermediates:
	@rm -f output/*.json