#!/bin/bash

ROOT=$(dirname "${BASH_SOURCE}")/..

# build_docker builds docker binaries
# Sets:
#   DOCKERD_BINS: paths to daemon binaries
#   DOCKER_BIN: path to docker client binary
build_docker() {
  local version="${1:?version}"

  mkdir -p "${ROOT}/.docker-build"
  local build_dir="${ROOT}/.docker-build/${version}"
  if [[ -d "${build_dir}" ]]; then
    rm -rf "${build_dir}"
  fi

  git clone --branch "${version}" --depth 1 https://github.com/docker/docker.git "${build_dir}"
  pushd "${build_dir}"

  { 
    AUTO_GOPATH=1 \
      DOCKER_BUILDTAGS='exclude_graphdriver_aufs seccomp selinux journald' \
      CFLAGS='-O0' \
      ./hack/make.sh dynbinary
  }

  # Binaries for 1.12.6, might need to have variants of the function for other versions
  DOCKERD_BIN="${build_dir}/bundles/1.12.6/dynbinary-daemon/dockerd"
  DOCKER_PROXY_BIN="${build_dir}/bundles/1.12.6/dynbinary-daemon/docker-proxy"
  DOCKER_BIN="${build_dir}/bundles/1.12.6/dynbinary-client/docker"
  popd
}

# Build runc
# Sets:
#   RUNC_BIN: path to the runc binary
build_runc() {
  local repo="${1:?repo}"
  local commit="${2:?commit}"
  
  mkdir -p "${ROOT}/.docker-build"
  local build_dir="${ROOT}/.docker-build/runc-${commit}"
  if [[ -d "${build_dir}" ]]; then
    rm -rf "${build_dir}"
  fi

  git clone "https://github.com/${repo}.git" "${build_dir}"
  pushd "${build_dir}"
  git checkout -q "${commit}"
  make BUILDTAGS="seccomp selinux"
  RUNC_BIN="${build_dir}/runc"
  popd
}

# Build containerd
# Sets:
#   CONTAINERD_BIN: path to the containerd binary
#   CTR_BIN: path to the ctr
#   CONTAINERD_SHIM_BIN: path to the containerd-shim binary
build_containerd() {
  local commit="${1:?commit}"
  
  mkdir -p "${ROOT}/.docker-build"
  local build_dir="${ROOT}/.docker-build/containerd-${commit}"
  if [[ -d "${build_dir}" ]]; then
    rm -rf "${build_dir}"
  fi

set -x
  export GOPATH="$(readlink -f "${build_dir}")"

  mkdir -p "${build_dir}/src/github.com/docker"
  local gp_dir="${build_dir}/src/github.com/docker/containerd"
  git clone "https://github.com/docker/containerd.git" "${gp_dir}"

  pushd "${gp_dir}"
  git checkout -q "${commit}"
  make static
  set +x
  CONTAINERD_BIN="${gp_dir}/bin/containerd"
  CONTAINERD_SHIM_BIN="${gp_dir}/bin/containerd-shim"
  CTR_BIN="${gp_dir}/bin/ctr"
  popd
}

package_dockerd_aci() {
  local name="${1:?name}"
  local version="${2:?version}"
  local output="${3:?output}"

  local prefix="/usr/bin"

  { 
    trap 'acbuild end' EXIT
    acbuild begin
    acbuild set-name "${name}"
    acbuild label add version "$version"
    acbuild label add arch "amd64"
    acbuild label add os "linux"
    acbuild copy "${DOCKERD_BIN}" "${prefix}/dockerd"
    acbuild copy "${DOCKER_BIN}" "${prefix}/docker"
    acbuild copy "${DOCKER_PROXY_BIN}" "${prefix}/docker-proxy"

    acbuild copy "${RUNC_BIN}" "${prefix}/docker-runc"
    acbuild copy "${CONTAINERD_BIN}" "${prefix}/docker-containerd"
    acbuild copy "${CTR_BIN}" "${prefix}/docker-containerd-ctr"
    acbuild copy "${CONTAINERD_SHIM_BIN}" "${prefix}/docker-containerd-shim"

    acbuild set-exec "${prefix}/dockerd"

    acbuild write --overwrite "${output}"
  }
}
