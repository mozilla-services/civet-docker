FROM ubuntu:20.04

ENV CE_VERSION=3c2aa307e1a2dbda3c6eb4ac6052a6a6689e6bd6

ARG DEBIAN_FRONTEND=noninteractive

# Regular Packages ------------------------------------
RUN apt-get update
RUN apt-get install -y \
    apt-transport-https \
    clang-11 \
    clang-tools-11 \
    curl    \
    debian-archive-keyring \
    debian-keyring \
    emacs   \
    git     \
    make    \
    net-tools \
    wget


# Node 12 ---------------------------------------------
RUN curl -sL https://deb.nodesource.com/setup_12.x | bash -
RUN apt-get update
RUN apt-get install -y \
    nodejs


# Caddy ------------------------------------------------
RUN curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | apt-key add -
RUN curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee -a /etc/apt/sources.list.d/caddy-stable.list
RUN apt-get update
RUN apt-get install -y \
    caddy

RUN echo "\n\
localhost.local, threadripper.local, staticanalyze.me { \n\
    reverse_proxy {\n\
        to http://localhost:10240 \n\
    } \n\
}" > /etc/caddy/Caddyfile


# Compiler Explorer -----------------------------------
RUN git clone https://github.com/compiler-explorer/compiler-explorer.git /ce && \
    cd /ce                      && \
    git checkout $CE_VERSION


# Services Start --------------------------------------
RUN echo "#!/bin/bash\n\
    caddy start --config /etc/caddy/Caddyfile \n\
    make run \n\
    " > /start.sh
RUN chmod +x /start.sh


EXPOSE 80
EXPOSE 443

WORKDIR /ce
ENTRYPOINT ["/start.sh"]
