#!UseOBSRepositories

#!BuildTag: rancher/hardened-dns-node-cache:v1.25.0
#!BuildTag: rancher/hardened-dns-node-cache:latest
#!BuildName: hardened-dns-node-cache

# INFO: image-build-base:latest provides the following:
# - required packages (make, musl-gcc, musl-libc-static, etc)
# - set CC, and C_INCLUDE_PATH evironment variables, to enable building with musl lib

ARG BCI_IMAGE=registry.suse.com/bci/bci-busybox
ARG GO_IMAGE=rancher/image-build-base:latest

FROM ${BCI_IMAGE} as bci

FROM ${GO_IMAGE} as builder

ARG TAG=1.25.0
ARG K3S_ROOT_VERSION=v0.14.1

# TODO(psaggu): review the binaries sourced from k3s-root-* tarball
# - at time of review, if new statically build equivalent binaries are available in BCI repo, switch to use them
# - if not the case above, and final shipping container image is not scratch, test with switching to regular (non-static) equivalent binaries available from BCI repo

#!RemoteAssetUrl: https://github.com/k3s-io/k3s-root/releases/download/v0.14.1/k3s-root-xtables-amd64.tar
COPY k3s-root-xtables-amd64.tar /opt/xtables/k3s-root-xtables-amd64.tar

#!RemoteAssetUrl: https://github.com/k3s-io/k3s-root/releases/download/v0.14.1/k3s-root-xtables-arm64.tar
COPY k3s-root-xtables-arm64.tar /opt/xtables/k3s-root-xtables-arm64.tar

RUN mkdir -p /opt/xtables/ && \
    if [ "$(uname -m)" == "x86_64" ]; then \
        cp /opt/xtables/k3s-root-xtables-amd64.tar /opt/xtables/k3s-root-xtables.tar; \
    elif [ "$(uname -m)" == "aarch64" ]; then \
        cp /opt/xtables/k3s-root-xtables-arm64.tar /opt/xtables/k3s-root-xtables.tar; \
    fi; \
    tar xvf /opt/xtables/k3s-root-xtables.tar -C /opt/xtables

ARG SRC=github.com/kubernetes/dns
ARG PKG=github.com/kubernetes/dns
COPY dns ${GOPATH}/src/${PKG}

WORKDIR $GOPATH/src/${PKG}

RUN GO_LDFLAGS="-linkmode=external -X ${PKG}/pkg/version.VERSION=${TAG}" \
    go-build-static.sh -gcflags=-trimpath=${GOPATH}/src -o . ./...
RUN go-assert-static.sh node-cache
RUN if [ `xx-info arch` = "amd64" ]; then \
        go-assert-boring.sh node-cache; \
    fi
RUN install  node-cache /usr/local/bin

#strip needs to run on TARGETPLATFORM, not BUILDPLATFORM
FROM ${GO_IMAGE} as strip_binary
COPY --from=builder /usr/local/bin/node-cache /node-cache
RUN strip /node-cache

FROM bci
COPY --from=strip_binary /node-cache /node-cache
COPY --from=builder /opt/xtables/bin/ /usr/sbin/
ENTRYPOINT ["/node-cache"]
