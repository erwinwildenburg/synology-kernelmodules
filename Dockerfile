FROM alpine:latest

RUN apk add --update bash \
                     python3 \
                     bash \
                     xz \
                     alpine-sdk \
                     cifs-utils \
                     libc6-compat \
                     jq \
                     perl
WORKDIR /root
COPY entrypoint.sh .
COPY config_modification.json .
RUN ["chmod", "+x", "entrypoint.sh"]

ENV PLATFORM="GeminiLake"
ENV DSM_VERSION="7.2-72806"
ENV KERNEL_VERSION="4.4.302"

ENTRYPOINT ["/root/entrypoint.sh"]