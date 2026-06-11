#!/bin/bash
# Docker 容器入口脚本 - 支持单设备构建和全量预编译
set -e

KERNEL_DIR="/kernel"
OUTPUT_DIR="${KERNEL_DIR}/output"
ANYKERNEL3_DIR="${KERNEL_DIR}/AnyKernel3"

# 支持的设备列表
ALL_DEVICES="a51 f41 m31s m31 m21 gta4xl gta4xlwifi"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    local timestamp
    timestamp=$(date '+%H:%M:%S')
    echo -e "[${timestamp}] ${GREEN}$1${NC}"
}

error() {
    echo -e "[ERROR] ${RED}$1${NC}" >&2
}

warn() {
    echo -e "[WARN] ${YELLOW}$1${NC}"
}

# 检查工具链
check_toolchain() {
    if [ -d "${KERNEL_DIR}/toolchain/bin" ]; then
        log "使用项目自带工具链: ${KERNEL_DIR}/toolchain/bin"
        export PATH="${KERNEL_DIR}/toolchain/bin:${PATH}"
    else
        warn "未找到项目自带工具链，使用系统工具链"
        # 验证系统工具链可用
        if ! command -v clang &> /dev/null; then
            error "未找到 clang 编译器，请挂载工具链或安装系统 clang"
            exit 1
        fi
    fi

    # 显示编译器版本
    log "编译器信息:"
    clang --version 2>&1 | head -2 || true
}

# 构建单个设备内核
build_kernel() {
    local target="$1"
    local allow_dirty="$2"

    log "========================================="
    log "开始构建内核: ${target}"
    log "========================================="

    cd "${KERNEL_DIR}"

    # 使用 Python 构建脚本
    local cmd="python3 build_kernel.py --target ${target}"
    if [ "${allow_dirty}" = "1" ]; then
        cmd="${cmd} --allow-dirty"
    fi

    eval ${cmd}

    # 收集产物到 output 目录
    mkdir -p "${OUTPUT_DIR}"
    for zip_file in "${KERNEL_DIR}"/AOSP_${target}_*.zip; do
        if [ -f "${zip_file}" ]; then
            local basename
            basename=$(basename "${zip_file}")
            cp "${zip_file}" "${OUTPUT_DIR}/"
            log "产物已复制: ${basename}"
        fi
    done
}

# 全量预编译：构建所有支持的设备
build_all() {
    local allow_dirty="$1"
    local success=0
    local failed=0

    log "========================================="
    log "开始全量预编译"
    log "目标设备: ${ALL_DEVICES}"
    log "========================================="

    mkdir -p "${OUTPUT_DIR}"

    for device in ${ALL_DEVICES}; do
        log "构建设备: ${device}"
        if build_kernel "${device}" "${allow_dirty}"; then
            success=$((success + 1))
            log "设备 ${device} 构建成功"
        else
            failed=$((failed + 1))
            error "设备 ${device} 构建失败"
        fi
    done

    log "========================================="
    log "预编译完成"
    log "成功: ${success}, 失败: ${failed}"
    log "========================================="

    # 生成 SHA256 校验文件
    cd "${OUTPUT_DIR}"
    for zip_file in *.zip; do
        if [ -f "${zip_file}" ]; then
            sha256sum "${zip_file}" > "${zip_file}.sha256"
            log "校验文件已生成: ${zip_file}.sha256"
        fi
    done

    # 生成构建信息
    cat > "${OUTPUT_DIR}/build_info.txt" <<EOF
构建时间: $(date '+%Y-%m-%d %H:%M:%S')
内核版本: 4.14.356
目标设备: ${ALL_DEVICES}
成功数: ${success}
失败数: ${failed}
编译器: $(clang --version 2>&1 | head -1)
EOF

    log "构建信息已保存到 build_info.txt"
}

# 仅配置（不编译）
defconfig_only() {
    local target="$1"
    log "生成 defconfig: exynos9611-${target}_defconfig"

    cd "${KERNEL_DIR}"
    make O=out LLVM=1 CROSS_COMPILE=aarch64-linux-gnu- \
        CC=clang LD=ld.lld AS=llvm-as AR=llvm-ar \
        OBJDUMP=llvm-objdump READELF=llvm-readelf NM=llvm-nm \
        OBJCOPY=llvm-objcopy ARCH=arm64 \
        "exynos9611-${target}_defconfig"
}

# 清理构建产物
clean_build() {
    log "清理构建产物..."
    cd "${KERNEL_DIR}"
    rm -rf out/
    log "清理完成"
}

# 显示帮助
show_help() {
    cat <<EOF
Exynos 9611 AOSP Kernel Docker Build Tool
==========================================

用法: docker-entrypoint.sh [选项]

选项:
  --target <device>    构建指定设备的内核 (a51|f41|m31s|m31|m21|gta4xl|gta4xlwifi)
  --all                预编译所有支持的设备
  --allow-dirty        允许脏构建（不清理旧产物）
  --defconfig <device> 仅生成 defconfig，不编译
  --clean              清理构建产物
  --help               显示此帮助信息

示例:
  # 构建 a51 内核
  docker-entrypoint.sh --target a51

  # 预编译所有设备
  docker-entrypoint.sh --all

  # 脏构建（增量编译）
  docker-entrypoint.sh --target m21 --allow-dirty

  # 仅生成配置
  docker-entrypoint.sh --defconfig a51

EOF
}

# 主入口
main() {
    check_toolchain

    case "${1:-}" in
        --target)
            if [ -z "${2:-}" ]; then
                error "--target 需要指定设备名称"
                show_help
                exit 1
            fi
            build_kernel "$2" "${ALLOW_DIRTY:-0}"
            ;;
        --all)
            build_all "${ALLOW_DIRTY:-0}"
            ;;
        --allow-dirty)
            export ALLOW_DIRTY=1
            shift
            # 继续处理下一个参数
            main "$@"
            ;;
        --defconfig)
            if [ -z "${2:-}" ]; then
                error "--defconfig 需要指定设备名称"
                show_help
                exit 1
            fi
            defconfig_only "$2"
            ;;
        --clean)
            clean_build
            ;;
        --help|-h)
            show_help
            ;;
        *)
            error "未知参数: ${1:-}"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
