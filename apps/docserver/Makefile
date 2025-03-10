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

PLATFORM ?= linux/amd64

GIT_TAG ?= latest

REPOSITORY := anyflow

NAME := docserver

DOC_PUBLISHER_NAME := doc-publisher
DOC_PUBLISHER_VERSION := latest

.PHONY: default
default: build_image run_image

.PHONY: clean

print_environment:
	@echo ${YELLOW}"================================================================================================="
	@echo "NAME : ${NAME}"
	@echo "GIT_TAG : ${GIT_TAG}"
	@echo "GITHUB_TOKEN: ${GITHUB_TOKEN}"
	@echo "PLATFORM: ${PLATFORM}"
	@echo "DOC PUBLISHER: ${REPOSITORY}/${DOC_PUBLISHER_NAME}:${DOC_PUBLISHER_VERSION}"
	@echo "================================================================================================="${COLOR_OFF}

# Need GIT_TAG, Need BUILD_IMAGE_OPTION
build_image: print_environment build
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
inspect_image:
	docker manifest inspect ${REPOSITORY}/${NAME}:${GIT_TAG}

build: _refresh_builder _refresh_output
	docker run --rm \
		-u ${shell id -u}:${shell id -g} \
		-v "${OUTPUT_PATH}:/output" \
		-v "${PWD}/docs:/manifest" \
		-v "${PWD}:/source_root" \
		-e GITHUB_TOKEN=${GITHUB_TOKEN} \
		-e DEFAULT_ENVIRONMENT=openapi \
		${REPOSITORY}/${DOC_PUBLISHER_NAME}:${DOC_PUBLISHER_VERSION} \
		-im /source_root/docs/CHANGELOG.md \
		-io /source_root/docs \
		-om /output/contents/changelog \
		-oo /output/contents/apispec && \
	mv ${OUTPUT_PATH}/contents/changelog/CHANGELOG.html ${OUTPUT_PATH}/contents/changelog/index.html
	cp ${PWD}/docs/openapi/openapi.yaml ${OUTPUT_PATH}/contents/apispec/openapi.yaml
	@echo ${CYAN}"CHANGELOG, swaggerUI/redoc web resources published."${COLOR_OFF}


OUTPUT_PATH := ${PWD}/output

_refresh_output:
	@rm -rf ${OUTPUT_PATH} && \
	mkdir ${OUTPUT_PATH} && \
	mkdir ${OUTPUT_PATH}/contents && \
	mkdir ${OUTPUT_PATH}/contents/changelog && \
	mkdir ${OUTPUT_PATH}/contents/apispec && \
	echo ${CYAN}"output directory refreshed"${COLOR_OFF}

_refresh_builder:
	@docker pull ${REPOSITORY}/${DOC_PUBLISHER_NAME}:${DOC_PUBLISHER_VERSION} && \
	echo ${CYAN}"Doc publisher refreshed"${COLOR_OFF}
