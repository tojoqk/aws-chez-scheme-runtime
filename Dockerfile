From amazonlinux:2017.03.1.20170812

RUN mkdir layer
WORKDIR ./layer/
Run yum -y install libcurl-devel libuuid-devel gcc git ncurses-devel \
  && mkdir lib64 \
  && cp /usr/lib64/lib{curl.so,nghttp2.so.14,nss3.so} lib64/ \
  && git clone https://github.com/cisco/ChezScheme.git

WORKDIR ChezScheme
RUN ./configure --installprefix=./build --disable-x11 \
  && make && make install && mv a6le/build ..

WORKDIR ../

RUN rm -rf ChezScheme
COPY ./src/chez-tojoqk/ ./tojoqk-aws-custom-runtime/
RUN sed -i 's/(tojoqk/(tojoqk-aws-custom-runtime/g' ./tojoqk-aws-custom-runtime/*.sls
COPY ./src/bootstrap ./src/runtime.ss ./

WORKDIR ../

CMD ["/bin/tar", "c", "layer"]
