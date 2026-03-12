FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive

# Install base system packages.
# Ubuntu 22.04 ships Python 3.10, which satisfies BitNet's python>=3.9 requirement.
RUN apt-get update && apt-get install -y \
    wget \
    curl \
    git \
    ninja-build \
    python3 \
    python3-dev \
    python3-pip \
    lsb-release \
    software-properties-common \
    gnupg \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# Install CMake >= 3.22 via the official Kitware APT repository.
RUN wget -O - https://apt.kitware.com/keys/kitware-archive-latest.asc 2>/dev/null \
      | gpg --dearmor - \
      | tee /usr/share/keyrings/kitware-archive-keyring.gpg > /dev/null && \
    echo "deb [signed-by=/usr/share/keyrings/kitware-archive-keyring.gpg] \
          https://apt.kitware.com/ubuntu/ jammy main" \
      | tee /etc/apt/sources.list.d/kitware.list && \
    apt-get update && apt-get install -y cmake && \
    rm -rf /var/lib/apt/lists/*

# Install Clang 18 + ALL companion packages (includes libomp-18-dev which
# BitNet/llama.cpp needs for OpenMP parallelism).
# Passing "all" as the second argument to llvm.sh installs the full toolchain.
RUN wget -qO- https://apt.llvm.org/llvm.sh | bash -s -- 18 all && \
    update-alternatives --install /usr/bin/clang   clang   /usr/bin/clang-18   100 && \
    update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-18 100 && \
    rm -rf /var/lib/apt/lists/*

# Ensure `python` resolves to python3.
RUN update-alternatives --install /usr/bin/python python /usr/bin/python3 1

# Tell CMake to use clang-18 explicitly — without this, cmake may fall back to
# whatever gcc is on the PATH and the BitNet kernels won't compile correctly.
ENV CC=clang-18
ENV CXX=clang++-18

# Sanity-check all required tools are present and meet version requirements.
RUN echo "=== clang ===" && clang --version && \
    echo "=== cmake ===" && cmake --version && \
    echo "=== python ===" && python3 --version

WORKDIR /app

# Clone the BitNet repository with all submodules (llama.cpp lives in 3rdparty/).
RUN git clone --recursive https://github.com/microsoft/BitNet.git .

# Upstream const-correctness bug in ggml-bitnet-mad.cpp: `y` is declared
# `const int8_t*` but line 811 tries to assign it to `int8_t* y_col`.
# Clang 18 (correctly) rejects this. Patch it to `const int8_t*` here.
RUN sed -i 's/int8_t \* y_col = y + col \* by;/const int8_t * y_col = y + col * by;/' \
    /app/src/ggml-bitnet-mad.cpp

# Install Python runtime dependencies.
RUN pip install --no-cache-dir -r requirements.txt

# Pre-create the directories that setup_env.py and run_inference.py expect.
RUN mkdir -p /app/models /app/logs

# Default command — overridden by every Makefile target.
CMD ["python3", "run_inference.py", "--help"]
