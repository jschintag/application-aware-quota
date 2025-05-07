#!/usr/bin/env bash

#Copyright 2023 The AAQ Authors.
#
#Licensed under the Apache License, Version 2.0 (the "License");
#you may not use this file except in compliance with the License.
#You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
#Unless required by applicable law or agreed to in writing, software
#distributed under the License is distributed on an "AS IS" BASIS,
#WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#See the License for the specific language governing permissions and
#limitations under the License.

set -e

script_dir="$(readlink -f $(dirname $0))"
source "${script_dir}"/common.sh
source "${script_dir}"/config.sh

opt="${1:-build}"

if ! command -v docker &> /dev/null && ! command -v podman &> /dev/null; then
    echo "Error: Neither Docker nor Podman found. Please install one of them."
    exit 1
fi

build_container() {
    local BIN_NAME="${1}"
    local ARCH="${2}"
    local IMAGE="${DOCKER_PREFIX}/${BIN_NAME}:${DOCKER_TAG}"
    local platform=""
    if [ "${ARCH}" != "" ]; then
        IMAGE="${IMAGE}-${ARCH}"
        platform="--platform linux/${ARCH}"
    fi

    if [ "${opt}" == "build" ]; then
        (
            pwd
            ${AAQ_CRI} build ${platform} -t ${IMAGE} . -f Dockerfile.${BIN_NAME}
        )
    elif [ "${opt}" == "push" ] || [ "${opt}" == "publish" ]; then
        ${AAQ_CRI} push "${IMAGE}"
    fi
}

multiarch() {
    local BIN_NAME="${1}"
    local IMAGE="${DOCKER_PREFIX}/${BIN_NAME}:${DOCKER_TAG}"
    local tmp_images=""
    local build_count=$(echo "${BUILD_ARCH//,/ }" | wc -w)

    if [ "${build_count}" -gt 1 ]; then
        for arch in ${BUILD_ARCH//,/ }; do
            build_container "${BIN_NAME}" "${arch}"
            tmp_images="${tmp_images} ${IMAGE}-${arch}"
        done

        if [ "${opt}" == "push" ] || [ "${opt}" == "publish" ]; then
            export DOCKER_CLI_EXPERIMENTAL=enabled
            ${AAQ_CRI} manifest create --amend "${IMAGE}" ${tmp_images}
            ${AAQ_CRI} manifest push ${IMAGE}
        fi
    else
        build_container "${BIN_NAME}"
    fi
}

PUSH_TARGETS=(${PUSH_TARGETS:-$CONTROLLER_IMAGE_NAME $AAQ_SERVER_IMAGE_NAME $OPERATOR_IMAGE_NAME})
echo "Using ${AAQ_CRI}, docker_prefix: $DOCKER_PREFIX, docker_tag: $DOCKER_TAG"
for target in ${PUSH_TARGETS[@]}; do
    multiarch "${target}"
done

pushd example_sidecars
PUSH_EXAMPLE_SIDECARS=("$LABEL_SIDECAR_IMAGE_NAME")
for target in ${PUSH_EXAMPLE_SIDECARS[@]}; do
    pushd ${target}
    multiarch "${target}"
    popd
done
popd
