# Samsung Exynos 9611 AOSP Kernel - Docker Build Environment
# 基于 Ubuntu 22.04，包含完整的内核构建工具链

FROM ubuntu:22.04 AS base

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Shanghai

# 安装基础构建依赖
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    clang \
    lld \
    llvm \
    gcc-aarch64-linux-gnu \
    gcc-arm-linux-gnueabihf \
    binutils-aarch64-linux-gnu \
    binutils-arm-linux-gnueabihf \
    libssl-dev \
    libelf-dev \
    bison \
    flex \
    bc \
    python3 \
    python3-pip \
    git \
    curl \
    wget \
    cpio \
    rsync \
    zip \
    unzip \
    p7zip-full \
    xz-utils \
    zlib1g-dev \
    libncurses5-dev \
    debhelper \
    kmod \
    ccache \
    && rm -rf /var/lib/apt/lists/*

# 设置工作目录
WORKDIR /kernel

# 复制项目文件
COPY . .

# 初始化 git 子模块
RUN if [ -d .git ]; then git submodule update --init --recursive || true; fi

# 设置工具链路径环境变量
ENV PATH="/kernel/toolchain/bin:${PATH}"
ENV CROSS_COMPILE=aarch64-linux-gnu-
ENV ARCH=arm64
ENV CC=clang

# ============================================================
# 预编译阶段：构建所有支持的设备内核
# ============================================================
FROM base AS prebuild

# 复制构建入口脚本
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["--target", "a51"]

# ============================================================
# 最终发布镜像：仅包含预编译产物
# ============================================================
FROM ubuntu:22.04 AS release

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /output

# 从预编译阶段复制产物
COPY --from=prebuild /kernel/output/*.zip /output/
COPY --from=prebuild /kernel/output/*.sha256 /output/

# 添加版本信息
ARG BUILD_DATE
ARG KERNEL_VERSION
ARG TARGET_DEVICES
LABEL org.opencontainers.image.title="Exynos 9611 AOSP Kernel"
LABEL org.opencontainers.image.description="Pre-built Samsung Exynos 9611 AOSP Kernel"
LABEL org.opencontainers.image.version="${KERNEL_VERSION}"
LABEL org.opencontainers.image.created="${BUILD_DATE}"
LABEL org.opencontainers.image.target_devices="${TARGET_DEVICES}"

# 默认命令：列出产物
CMD ["ls", "-lah", "/output/"]
