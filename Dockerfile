ARG HYPHANET_VERSION=1507

FROM eclipse-temurin:21.0.7_6-jre-jammy AS builder

ARG HYPHANET_VERSION
# Primary mirror: official GitHub release asset; fallback: draketo.de mirror.
ENV HYPHANET_INSTALLER_URLS="https://github.com/hyphanet/fred/releases/download/build0${HYPHANET_VERSION}/new_installer_offline_${HYPHANET_VERSION}.jar https://www.draketo.de/dateien/freenet/build0${HYPHANET_VERSION}/new_installer_offline_${HYPHANET_VERSION}.jar"
ENV INSTALLER_JAR=new_installer_offline.jar
ENV HYPHANET_HOME=/opt/hyphanet
ENV INSTALL_USER=installer
ENV INSTALL_UID=1001
ENV INSTALL_GID=1001

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    expect \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd --gid ${INSTALL_GID} ${INSTALL_USER} && \
    useradd --uid ${INSTALL_UID} --gid ${INSTALL_GID} --shell /bin/bash --create-home ${INSTALL_USER}

RUN mkdir -p ${HYPHANET_HOME} && chown ${INSTALL_UID}:${INSTALL_GID} ${HYPHANET_HOME}

USER ${INSTALL_USER}
WORKDIR /home/${INSTALL_USER}

# Download the offline installer JAR, trying each mirror in HYPHANET_INSTALLER_URLS.
RUN set -eux; \
    for url in ${HYPHANET_INSTALLER_URLS}; do \
        echo "Downloading installer from ${url}"; \
        if curl -fsSL --connect-timeout 30 --max-time 600 --retry 3 --retry-delay 5 -o "${INSTALLER_JAR}" "${url}"; then \
            echo "Downloaded ${INSTALLER_JAR}"; \
            break; \
        fi; \
        echo "WARN: download failed from ${url}"; \
    done; \
    if [ ! -s "${INSTALLER_JAR}" ]; then \
        echo "ERROR: could not download installer for build 0${HYPHANET_VERSION}"; \
        exit 1; \
    fi

COPY --chmod=755 <<'EOT' install_script.exp
#!/usr/bin/expect -f
set hyphanet_home "/opt/hyphanet"
set installer_jar "new_installer_offline.jar"
set timeout 600

puts "DEBUG: HYPHANET_HOME in expect is $hyphanet_home"
puts "DEBUG: INSTALLER_JAR in expect is $installer_jar"
puts "Starting installation of Hyphanet"

if {![file exists $installer_jar]} {
    puts "ERROR: Installer JAR '$installer_jar' not found!"
    exit 1
}
spawn java -jar $installer_jar -console

expect "Select target path*"
send -- "$hyphanet_home\n"

expect "press 1 to continue, 2 to quit, 3 to redisplay"
send "1\n"

expect {
    "Console installation done" { puts "Installation appears successful (Console installation done)" }
    "All done" { puts "Installation appears successful (All done)" }
    timeout { puts "ERROR: Installation Timeout"; exit 1 }
    eof { puts "ERROR: Unexpected EOF during installation"; exit 1 }
}

expect eof
catch wait result
set exit_status [lindex $result 3]
if {$exit_status != 0} {
    puts "ERROR: Java installer process exited with status $exit_status"
    exit 1
}
puts "Expect script finished successfully."
EOT

RUN ./install_script.exp

# Sanity-check that the installer produced a usable node layout.
RUN test -f ${HYPHANET_HOME}/run.sh && test -f ${HYPHANET_HOME}/freenet.ini


FROM eclipse-temurin:21.0.7_6-jre-jammy

ARG HYPHANET_VERSION
LABEL org.opencontainers.image.title="hyphanet-docker" \
      org.opencontainers.image.version="0.7.5.${HYPHANET_VERSION}"

ENV HYPHANET_VERSION=${HYPHANET_VERSION}
ENV HYPHANET_USER=hyphanet
ENV HYPHANET_UID=1000
ENV HYPHANET_GID=1000
ENV HYPHANET_HOME=/opt/hyphanet
ENV HYPHANET_DATA=/data

RUN apt-get update && apt-get install -y --no-install-recommends \
    net-tools \
    iproute2 \
    socat \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd --gid ${HYPHANET_GID} ${HYPHANET_USER} && \
    useradd --uid ${HYPHANET_UID} --gid ${HYPHANET_GID} --shell /bin/bash --create-home ${HYPHANET_USER}

COPY --from=builder --chown=${HYPHANET_UID}:${HYPHANET_GID} ${HYPHANET_HOME} ${HYPHANET_HOME}

# Snapshot the installer's pristine freenet.ini so the entrypoint can tell it
# apart from a node-written config (see the promotion logic in entrypoint.sh).
RUN cp -p ${HYPHANET_HOME}/freenet.ini ${HYPHANET_HOME}/freenet.ini.image-default && \
    chown ${HYPHANET_UID}:${HYPHANET_GID} ${HYPHANET_HOME}/freenet.ini.image-default

RUN mkdir -p ${HYPHANET_DATA} && \
  chown ${HYPHANET_UID}:${HYPHANET_GID} ${HYPHANET_DATA}

COPY --chown=${HYPHANET_UID}:${HYPHANET_GID} entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint.sh

USER ${HYPHANET_USER}
WORKDIR ${HYPHANET_HOME}

EXPOSE 8123
VOLUME [ "${HYPHANET_DATA}" ]

ENTRYPOINT [ "/usr/local/bin/entrypoint.sh" ]
CMD [ "start" ]
