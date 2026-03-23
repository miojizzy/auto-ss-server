# Dockerfile.cnb - Derived image for CNB / buildpack workflows
# 使用 Ubuntu 24.04 作为基础镜像，独立构建，不依赖 Dockerfile.base

FROM ubuntu:24.04

# 避免交互式提示
ENV DEBIAN_FRONTEND=noninteractive

# 安装 GCC 13、CMake 3.22+、Make、Python 3.12、Go 1.23、GDB
RUN apt-get update && apt-get install -y \
    software-properties-common \
    curl \
    wget \
    git \
    git-lfs \
    vim \
    rsync \
    jq \
    g++-13 \
    gcc-13 \
    make \
    cmake \
    gdb \
    python3.12 \
    python3.12-dev \
    python3-pip \
    zsh \
    unzip \
    lsof \
    nload \
    htop \
    net-tools \
    dnsutils \
    openssh-server \
    docker.io \
    docker-compose \
    && ln -sf /usr/bin/python3.12 /usr/bin/python3 \
    && ln -sf /usr/bin/g++-13 /usr/bin/g++ \
    && ln -sf /usr/bin/gcc-13 /usr/bin/gcc \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# 安装 Go 1.23
RUN wget -q https://go.dev/dl/go1.23.0.linux-amd64.tar.gz -O /tmp/go.tar.gz \
    && rm -rf /usr/local/go \
    && tar -C /usr/local -xzf /tmp/go.tar.gz \
    && rm /tmp/go.tar.gz \
    && ln -sf /usr/local/go/bin/go /usr/bin/go

# 配置 Git LFS
RUN git lfs install

# 安装 code-server 和扩展
RUN curl -fsSL https://code-server.dev/install.sh | sh \
    && code-server --install-extension cnbcool.cnb-welcome \
    && code-server --install-extension tencent-cloud.coding-copilot

# 安装 Oh My Zsh 和插件
RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended \
    && git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions \
    && git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting \
    && echo 'setopt NO_AUTO_REMOVE_SLASH' >> /root/.zshrc \
    && mkdir -p ~/.oh-my-zsh/completions \
    && chsh -s $(which zsh)

# 配置 .zshrc
RUN sed -i '1isetopt NULL_GLOB 2>/dev/null\n\
source /etc/profile\n\
unsetopt NULL_GLOB 2>/dev/null\n\
if command -v docker > /dev/null; then\n\
    docker completion zsh > ~/.oh-my-zsh/completions/_docker\n\
fi' /root/.zshrc

# 设置字符集
ENV LANG=C.UTF-8
ENV LANGUAGE=C.UTF-8

WORKDIR /workspace
COPY . /workspace
