# --- Build stage ---
FROM alpine:latest AS build

# Install build dependencies (including musl-dev for libc)
RUN apk add --no-cache \
    build-base \
    musl-dev \
    git \
    xz

# Install Zig (using the version from your .zigversion file)
COPY .zigversion .
RUN ZIG_VERSION=$(cat .zigversion) && \
    wget https://ziglang.org/download/0.14.0/zig-linux-x86_64-${ZIG_VERSION}.tar.xz && \
    tar -xf zig-linux-x86_64-${ZIG_VERSION}.tar.xz && \
    mv zig-linux-x86_64-${ZIG_VERSION} /opt/zig && \
    ln -s /opt/zig/zig /usr/local/bin/zig && \
    rm -rf zig-linux-x86_64-${ZIG_VERSION}*
RUN export PATH=$PATH:/usr/local/bin && \
    zig version

WORKDIR /build

# Copy project files
COPY cli ./cli
COPY src ./src
COPY main.zig .
COPY build.zig .
COPY build.zig.zon .

# Build the release binary
# Using -Dtarget=native-native-musl for proper static linking
RUN zig build -Doptimize=ReleaseFast -Dtarget=x86_64-linux-musl

# --- Runtime stage ---
FROM alpine:latest

# Install runtime dependencies (musl for running static binary)
# Copy the statically built binary from the build stage
COPY --from=build /build/zig-out/bin/loxz /usr/local/bin/loxz

# Ensure the binary is executable
RUN chmod +x /usr/local/bin/loxz

ENTRYPOINT ["/usr/local/bin/loxz"]