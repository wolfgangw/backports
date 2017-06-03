FROM aptible/ruby:1.9.3-debian-jessie

RUN apt-get update && apt-get -y install libexpat-dev wget sox

RUN gem install nokogiri -v 1.6.8.rc2
RUN gem install ttfunk -v 1.4.0

WORKDIR /tmp
RUN wget http://download.cinecert.com/asdcplib/asdcplib-1.12.58.tar.gz && \
    tar xvf /tmp/asdcplib-1.12.58.tar.gz && \
    cd asdcplib-1.12.58 && \
    ./configure && \
    make -j && \
    make install && \
    cd .. && \
    rm -rf /tmp/asdcplib-1.12.58

RUN cp /usr/local/lib/libkumu* /usr/lib/ && \
    cp /usr/local/lib/libasdcp* /usr/lib/

COPY xsd /usr/bin/xsd
COPY dcp_inspect /usr/bin/dcp_inspect

ENTRYPOINT ["dcp_inspect"]
