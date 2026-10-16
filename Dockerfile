# The build tools at pinned versions: Python with Pillow, StormLib and CascLib (shared libraries, for
# the scripts' ctypes) and Zig (for client/dinput8.dll). The source, the client and the retail
# install are mounted when it runs (see README, "Build with Docker"); nothing of Blizzard's is in it.
FROM python:3.12-slim-bookworm

RUN apt-get update && apt-get install -y --no-install-recommends \
        git curl ca-certificates xz-utils cmake make g++ \
    && rm -rf /var/lib/apt/lists/*
RUN pip install --no-cache-dir Pillow==12.0.0

# The same StormLib commit client/build.sh compiles into the DLL.
RUN git clone -q https://github.com/ladislav-zezula/StormLib.git /opt/StormLib \
    && git -C /opt/StormLib checkout -q 44ebfbf \
    && cmake -S /opt/StormLib -B /opt/StormLib/build -DBUILD_SHARED_LIBS=ON -DSTORM_USE_BUNDLED_LIBRARIES=ON \
        -DCMAKE_BUILD_TYPE=Release \
    && cmake --build /opt/StormLib/build -j"$(nproc)"
RUN git clone -q -b 3.0 https://github.com/ladislav-zezula/CascLib.git /opt/CascLib \
    && cmake -S /opt/CascLib -B /opt/CascLib/build -DCASC_BUILD_SHARED_LIB=ON -DCASC_BUILD_STATIC_LIB=OFF \
        -DCMAKE_BUILD_TYPE=Release \
    && cmake --build /opt/CascLib/build -j"$(nproc)"
RUN curl -sfL https://ziglang.org/download/0.13.0/zig-linux-x86_64-0.13.0.tar.xz | tar xJ -C /opt

ENV STORMLIB=/opt/StormLib/build/libstorm.so \
    CASCLIB=/opt/CascLib/build/libcasc.so \
    ZIG=/opt/zig-linux-x86_64-0.13.0/zig \
    WOW_DIR=/wow \
    WOW_RETAIL=/retail \
    HOME=/tmp
WORKDIR /src
ENTRYPOINT ["sh", "/src/docker-build.sh"]
