FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive \
    EPRINTS_ROOT=/opt/eprints3 \
    PERL5LIB=/opt/eprints3/perl_lib \
    PATH="/opt/eprints3/bin:${PATH}"

RUN apt-get update && apt-get install -y --no-install-recommends \
    apache2 \
    libapache2-mod-perl2 \
    perl \
    build-essential \
    wget curl gnupg unzip git ca-certificates \
    imagemagick \
    poppler-utils \
    antiword \
    lynx \
    libxml2-dev libxslt1-dev libexpat1-dev \
    libcompress-raw-zlib-perl \
    default-mysql-client \
    cpanminus \
    && rm -rf /var/lib/apt/lists/*

RUN cpanm --notest \
    DBI \
    DBD::mysql \
    XML::LibXML \
    XML::LibXSLT \
    Data::UUID \
    JSON \
    Unicode::String \
    Text::Unidecode \
    Digest::MD5

RUN git clone --branch 3.4 --depth 1 https://github.com/eprints/eprints.git ${EPRINTS_ROOT}

WORKDIR ${EPRINTS_ROOT}

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh \
    && chown -R www-data:www-data ${EPRINTS_ROOT}

EXPOSE 80

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["apache2ctl", "-D", "FOREGROUND"]