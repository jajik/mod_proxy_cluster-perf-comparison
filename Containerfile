FROM fedora:42 AS builder

RUN dnf install cmake gcc g++ wget apr-devel apr-util apr-util-devel openssl-devel pcre-devel redhat-rpm-config wcstools autoconf -y

ARG HTTPD_SOURCES="https://dlcdn.apache.org/httpd/httpd-2.4.66.tar.gz"

ENV HTTPD=${HTTPD_SOURCES}

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

# make sure you have copy of the local repository at place
# (our function "httpd_create" takes care of that)
COPY native /native

# httpd is installed in /usr/local/apache2/bin/
# build and install mod_proxy_cluster *.so files.
RUN mkdir -p /native/build && \
    cd /native/build && \
    cmake ../ -G "Unix Makefiles" -DAPACHE_INCLUDE_DIR=/usr/local/apache2/include/ && \
    make
RUN cp /native/build/modules/*.so /usr/local/apache2/modules/
# preserve the version
RUN grep -rh "#define MOD_CLUSTER_EXPOSED_VERSION " /native > /mpc_version


FROM fedora:42

LABEL perfsuite-mod_proxy_cluster=

RUN dnf install pcre apr-util wcstools -y

COPY --from=builder /usr/local/apache2/ /usr/local/apache2

COPY --from=builder /mpc_version /mpc_version

COPY mod_proxy_cluster.conf /usr/local/apache2/conf/

COPY httpd-container-run.sh /

WORKDIR /usr/local/apache2/

CMD /httpd-container-run.sh

