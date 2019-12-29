From amazonlinux:2017.03.1.20170812

ENV CHEZ_VERSION 9.5.2

RUN mkdir layer
WORKDIR ./layer/
RUN yum install -y gcc libuuid-devel ncurses-devel \
  && curl -Lo ChezScheme-${CHEZ_VERSION}.tar.gz https://github.com/cisco/ChezScheme/archive/v${CHEZ_VERSION}.tar.gz \
  && tar xf ChezScheme-${CHEZ_VERSION}.tar.gz

WORKDIR ChezScheme-${CHEZ_VERSION}
RUN ./configure --installprefix=./build --disable-x11 \
  && make && make install && mv a6le/build ..

WORKDIR ../

RUN rm -rf ChezScheme-${CHEZ_VERSION}.tar.gz \
    && rm -rf ChezScheme-${CHEZ_VERSION}

COPY ./src/bootstrap ./src/runtime.sps ./

WORKDIR ../

CMD ["/bin/tar", "c", "layer"]
