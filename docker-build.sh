#!/bin/bash
# Docker 构建管理脚本 - 简化 Docker 操作
set -e

IMAGE_NAME="exynos9611-kernel"
IMAGE_TAG="latest"
RELEASE_TAG="release"

# 颜色输出
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[Docker] $1${NC}"; }
warn() { echo -e "${YELLOW}[Docker] $1${NC}"; }

# 检测 docker compose 命令
detect_compose() {
    if docker compose version &>/dev/null; then
        echo "docker compose"
    elif docker-compose version &>/dev/null; then
        echo "docker-compose"
    else
        echo ""
    fi
}

COMPOSE_CMD=$(detect_compose)

build_image() {
    log "构建 Docker 镜像: ${IMAGE_NAME}:${IMAGE_TAG}"
    docker build \
        --target prebuild \
        -t "${IMAGE_NAME}:${IMAGE_TAG}" \
        --build-arg BUILD_DATE="$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
        --build-arg KERNEL_VERSION="4.14.356" \
        .
    log "镜像构建完成"
}

build_release() {
    log "构建发布镜像: ${IMAGE_NAME}:${RELEASE_TAG}"
    docker build \
        --target release \
        -t "${IMAGE_NAME}:${RELEASE_TAG}" \
        --build-arg BUILD_DATE="$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
        --build-arg KERNEL_VERSION="4.14.356" \
        --build-arg TARGET_DEVICES="a51,f41,m31s,m31,m21,gta4xl,gta4xlwifi" \
        .
    log "发布镜像构建完成"
}

build_target() {
    local target="${1:-a51}"
    log "构建内核: ${target}"

    if [ -n "${COMPOSE_CMD}" ]; then
        ${COMPOSE_CMD} run --rm kernel-build --target "${target}"
    else
        docker run --rm \
            -v "$(pwd)/toolchain:/kernel/toolchain:ro" \
            -v "$(pwd)/output:/kernel/output" \
            "${IMAGE_NAME}:${IMAGE_TAG}" \
            --target "${target}"
    fi
}

build_all() {
    log "全量预编译所有设备"

    if [ -n "${COMPOSE_CMD}" ]; then
        ${COMPOSE_CMD} run --rm kernel-prebuild-all
    else
        docker run --rm \
            -v "$(pwd)/toolchain:/kernel/toolchain:ro" \
            -v "$(pwd)/output:/kernel/output" \
            "${IMAGE_NAME}:${IMAGE_TAG}" \
            --all
    fi
}

defconfig() {
    local target="${1:-a51}"
    log "生成 defconfig: ${target}"

    if [ -n "${COMPOSE_CMD}" ]; then
        ${COMPOSE_CMD} run --rm kernel-defconfig --defconfig "${target}"
    else
        docker run --rm \
            -v "$(pwd)/toolchain:/kernel/toolchain:ro" \
            "${IMAGE_NAME}:${IMAGE_TAG}" \
            --defconfig "${target}"
    fi
}

shell() {
    log "进入容器 Shell"
    docker run --rm -it \
        -v "$(pwd)/toolchain:/kernel/toolchain:ro" \
        -v "$(pwd)/output:/kernel/output" \
        --entrypoint /bin/bash \
        "${IMAGE_NAME}:${IMAGE_TAG}"
}

clean() {
    log "清理构建产物"
    docker run --rm \
        -v "$(pwd)/toolchain:/kernel/toolchain:ro" \
        "${IMAGE_NAME}:${IMAGE_TAG}" \
        --clean
}

push_image() {
    local registry="${1:-}"
    if [ -z "${registry}" ]; then
        warn "请指定镜像仓库地址，例如: ./docker-build.sh push ghcr.io/username"
        exit 1
    fi
    log "推送镜像到: ${registry}"
    docker tag "${IMAGE_NAME}:${RELEASE_TAG}" "${registry}/${IMAGE_NAME}:${RELEASE_TAG}"
    docker push "${registry}/${IMAGE_NAME}:${RELEASE_TAG}"
}

show_help() {
    cat <<EOF
Exynos 9611 AOSP Kernel - Docker 构建工具
==========================================

用法: ./docker-build.sh <命令> [参数]

命令:
  build             构建 Docker 镜像
  release           构建发布镜像（包含预编译产物）
  target <device>   构建指定设备内核 (默认: a51)
  all               全量预编译所有设备
  defconfig <dev>   仅生成 defconfig (默认: a51)
  shell             进入容器交互 Shell
  clean             清理构建产物
  push <registry>   推送发布镜像到仓库
  help              显示此帮助

支持的设备: a51, f41, m31s, m31, m21, gta4xl, gta4xlwifi

示例:
  # 1. 首次构建镜像
  ./docker-build.sh build

  # 2. 构建 a51 内核
  ./docker-build.sh target a51

  # 3. 全量预编译
  ./docker-build.sh all

  # 4. 构建发布镜像并推送
  ./docker-build.sh release
  ./docker-build.sh push ghcr.io/username

  # 5. 使用 docker compose
  docker compose run --rm kernel-build --target a51
  docker compose run --rm kernel-prebuild-all

EOF
}

case "${1:-}" in
    build)      build_image ;;
    release)    build_release ;;
    target)     build_target "${2:-a51}" ;;
    all)        build_all ;;
    defconfig)  defconfig "${2:-a51}" ;;
    shell)      shell ;;
    clean)      clean ;;
    push)       push_image "${2:-}" ;;
    help|--help|-h) show_help ;;
    *)          echo "未知命令: ${1:-}"; show_help; exit 1 ;;
esac
