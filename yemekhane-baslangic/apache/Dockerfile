# Apache 2.4 · proxy modülleri açık, yemekhane.conf eklenmiş hali
FROM httpd:2.4-alpine

RUN sed -i \
      -e 's/^#\(LoadModule proxy_module modules\/mod_proxy.so\)/\1/' \
      -e 's/^#\(LoadModule proxy_http_module modules\/mod_proxy_http.so\)/\1/' \
      conf/httpd.conf \
 && echo 'Include conf/extra/yemekhane.conf' >> conf/httpd.conf

COPY yemekhane.conf conf/extra/yemekhane.conf
