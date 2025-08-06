FROM fedora:42 AS builder

# hack for Fedora 42: we need to ensure that /usr/bin is searched before /usr/sbin for apr-1-config
ENV PATH="/usr/bin:$PATH"

RUN dnf install cmake gcc g++ wget apr-devel apr-util apr-util-devel openssl-devel pcre-devel redhat-rpm-config wcstools autoconf -y

ARG HTTPD_SOURCES="https://dlcdn.apache.org/httpd/httpd-2.4.65.tar.gz"

ENV HTTPD=${HTTPD_SOURCES}

# make sure you have copy of the local repository at place
# (our function "httpd_create" takes care of that)
COPY mod_proxy_cluster /

ADD ${HTTPD} .

RUN mkdir /httpd && tar xvf $(filename $HTTPD) --strip 1 -C /httpd

WORKDIR /httpd
RUN ./configure --enable-proxy \
                --enable-proxy-http \
                --enable-proxy-ajp \
                --enable-proxy-wstunnel \
                --enable-proxy-hcheck
RUN make
RUN make install

# httpd is installed in /usr/local/apache2/bin/
# build and install mod_proxy_cluster *.so files.
WORKDIR /native
RUN mkdir build || true
WORKDIR /native/build
RUN cmake ../ -G "Unix Makefiles" -DAPACHE_INCLUDE_DIR=/usr/local/apache2/include/
RUN make
RUN cp modules/*.so /usr/local/apache2/modules/

RUN rm -rf /test/httpd/mod_proxy_cluster


FROM fedora:42

ENV CONF=httpd/mod_proxy_cluster.conf

RUN dnf install pcre apr-util wcstools -y

COPY --from=builder /usr/local/apache2/ /usr/local/apache2

COPY --from=builder /test /test

COPY run.sh /tmp

WORKDIR /usr/local/apache2/

CMD /tmp/run.sh

