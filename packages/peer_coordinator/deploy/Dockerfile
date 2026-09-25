# Build the hub as a self-contained native binary.
#
# Two stages so the runtime image carries neither the SDK nor the source: the
# result is the AOT binary plus the small Dart runtime it links against.
#
# Build from the REPOSITORY ROOT, not from this directory:
#   docker build -f packages/peer_coordinator/deploy/Dockerfile .
# (docker-compose.yml already sets that context.)
FROM dart:stable AS build

WORKDIR /build

# The repository is a pub workspace whose members include Flutter packages,
# which a plain Dart SDK cannot resolve. Rather than pull the whole Flutter
# toolchain in to build a pure-Dart binary, this image declares a minimal
# workspace containing only the hub's package. peer_coordinator's own pubspec
# says `resolution: workspace`, so it still needs *a* root — just not that one.
COPY packages/peer_coordinator/ packages/peer_coordinator/
RUN rm -rf packages/peer_coordinator/example \
    && printf 'name: hub_build\nenvironment:\n  sdk: ^3.12.2\nworkspace:\n  - packages/peer_coordinator\n' > pubspec.yaml \
    && dart pub get

RUN dart compile exe packages/peer_coordinator/bin/hub.dart -o /build/hub

FROM debian:bookworm-slim AS runtime

# The Dart runtime the AOT binary needs, and nothing else.
COPY --from=build /runtime/ /
COPY --from=build /build/hub /app/hub

# Unprivileged: the hub opens listening sockets and touches no files.
RUN useradd --system --uid 10001 --no-create-home hub
USER hub

# Inside the container only. docker-compose deliberately does NOT publish this
# — Caddy reaches it over the compose network, and nothing else can.
EXPOSE 8080

ENTRYPOINT ["/app/hub"]
