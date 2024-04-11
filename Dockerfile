ARG HTTPD_SOURCES="https://dlcdn.apache.org/httpd/httpd-2.4.59.tar.gz"

FROM fedora:38

RUN yum install cmake gcc g++ wget apr-devel apr-util-devel openssl-devel pcre-devel redhat-rpm-config wcstools git autoconf -y

ARG HTTPD_SOURCES

ENV CONF=httpd/mod_proxy_cluster.conf
ENV HTTPD=${HTTPD_SOURCES}

# make sure you have copy of the local repository at place
# (our function "httpd_create" takes care of that)
ADD mod_proxy_cluster /
ADD run.sh /tmp

RUN wget $HTTPD
RUN mkdir httpd
RUN tar xvf $(filename $HTTPD) --strip 1 -C httpd
RUN ls
WORKDIR /httpd
RUN ./configure --enable-proxy \
                --enable-proxy-http \
                --enable-proxy-ajp \
                --enable-proxy-wstunnel \
                --enable-proxy-hcheck \
                --with-port=8000
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

RUN sed -i 's|EnableMCMPReceive|EnableMCPMReceive|' /test/httpd/mod_proxy_cluster.conf

CMD /tmp/run.sh

