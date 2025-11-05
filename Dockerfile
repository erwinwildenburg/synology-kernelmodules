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
ENV KERNEL_MAJORVERSION="4"
ENV KERNEL_PATCHLEVEL="4"
ENV KERNEL_SUBLEVEL="302"
ENV KERNEL_EXTRAVERSION="+"

ENTRYPOINT ["/root/entrypoint.sh"]