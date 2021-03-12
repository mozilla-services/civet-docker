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


# Compiler Explorer -----------------------------------
RUN git clone https://github.com/compiler-explorer/compiler-explorer.git /ce && \
    cd /ce                      && \
    git checkout $CE_VERSION


EXPOSE 10240

WORKDIR /ce
ENTRYPOINT ["make"]
CMD ["run"]
