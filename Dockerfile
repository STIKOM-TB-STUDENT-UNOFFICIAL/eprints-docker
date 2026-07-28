FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive \
    EPRINTS_ROOT=/opt/eprints3 \
    PERL5LIB=/opt/eprints3/perl_lib \
    PATH="/opt/eprints3/bin:${PATH}"

RUN apt-get update && apt-get install -y --no-install-recommends \
    perl libncurses6 libselinux1 apache2 libapache2-mod-perl2 libxml-libxml-perl \
    libunicode-string-perl libterm-readkey-perl libmime-lite-perl libmime-types-perl libdigest-sha-perl \
    libdbd-mysql-perl libxml-parser-perl libxml2-dev libxml-twig-perl libarchive-any-perl libjson-perl \
    liblwp-protocol-https-perl libtext-unidecode-perl lynx wget ghostscript poppler-utils antiword elinks \
    texlive-base texlive-binaries psutils imagemagick adduser tar gzip unzip libsearch-xapian-perl \
    libtex-encode-perl libio-string-perl python3-html2text make libexpat1-dev libxslt1-dev \
    cpanminus build-essential pkg-config git libssl-dev zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

RUN apt-get update && \
    apt-get install -y mariadb-client && \
    rm -rf /var/lib/apt/lists/*

RUN cpanm --verbose --notest \
    Data::UUID \
    XML::LibXSLT \
    XML::Generator \
    XML::DOM \
    XML::SAX \
    XML::NamespaceSupport \
    Archive::Zip \
    CGI \
    CGI::Cookie \
    CGI::Carp \
    File::Slurp \
    File::Copy::Recursive \
    Net::SMTP \
    Email::Valid \
    Crypt::SSLeay

ARG CACHE_BUST=1
RUN git clone https://github.com/STIKOM-TB-STUDENT-UNOFFICIAL/eprints-elysia.git ${EPRINTS_ROOT}

WORKDIR ${EPRINTS_ROOT}

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh \
    && chown -R www-data:www-data ${EPRINTS_ROOT}

EXPOSE 80

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["apache2ctl", "-D", "FOREGROUND"]