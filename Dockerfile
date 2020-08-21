
FROM busybox

RUN wget https://github.com/fatedier/frp/releases/download/v0.33.0/frp_0.33.0_linux_amd64.tar.gz && \
    tar -xzvf frp_0.33.0_linux_amd64.tar.gz && \
    rm -rf frp_0.33.0_linux_amd64.tar.gz

WORKDIR frp_0.33.0_linux_amd64
COPY frps.ini frps.ini
