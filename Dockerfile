FROM ubuntu:20.04

ENV CE_VERSION=3c2aa307e1a2dbda3c6eb4ac6052a6a6689e6bd6

ARG DEBIAN_FRONTEND=noninteractive

# Regular Packages ------------------------------------
# First set is for compiler-explorer and related; second set is for firejail

RUN apt-get update &&          \
    apt-get install -y         \
      apt-transport-https      \
      clang-9                  \
      clang-tools-9            \
      clang-10                 \
      clang-tools-10           \
      clang-11                 \
      clang-tools-11           \
      curl                     \
      debian-archive-keyring   \
      debian-keyring           \
      emacs                    \
      git                      \
      make                     \
      net-tools                \
      wget                     \
      zstd         &&          \
    apt-get install -y         \
      clang                    \
      gawk


# Firejail --------------------------------------------
RUN git clone https://github.com/netblue30/firejail.git && \
    cd firejail          && \
    git checkout LTSbase && \
    ./configure          && \
    make install-strip


# Node 12 ---------------------------------------------
RUN curl -sL https://deb.nodesource.com/setup_12.x | bash -  && \
    apt-get update &&  \
    apt-get install -y \
       nodejs


# Compiler Explorer -----------------------------------
RUN git clone https://github.com/compiler-explorer/compiler-explorer.git /ce && \
    cd /ce                                                                   && \
    git checkout $CE_VERSION
COPY execution.mozilla.properties /ce/etc/config/execution.local.properties
COPY c++.mozilla.properties /ce/etc/config/c++.local.properties
COPY ce-mozilla.svg         /ce/views/resources/site-logo.svg
# Matt has given his blessing for us slapping a fox on his logo; thanks Matt!


# Our Clang --------------------------------------------
RUN cd /                      && \
    wget -q https://firefox-ci-tc.services.mozilla.com/api/index/v1/task/gecko.cache.level-1.toolchains.v3.linux64-clang-11.latest/artifacts/public/build/clang.tar.zst && \
    unzstd clang.tar.zst      && \
    tar xf clang.tar          && \
    mv clang mozilla-clang-11

# Setup -------------------------------------------------

EXPOSE 10240

WORKDIR /ce
ENTRYPOINT ["make"]
CMD ["run"]
