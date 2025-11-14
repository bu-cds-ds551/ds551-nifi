# OpenShift-Compatible Apache NiFi Dockerfile
# Based on apache/nifi:1.24.0 but modified for OpenShift Security Context Constraints

ARG IMAGE_NAME=bellsoft/liberica-openjdk-debian
ARG IMAGE_TAG=21
FROM ${IMAGE_NAME}:${IMAGE_TAG}

LABEL maintainer="DS-551 Infrastructure Team"
LABEL description="OpenShift-compatible Apache NiFi image"

ARG UID=1000
ARG GID=0
ARG NIFI_VERSION=1.24.0
ARG MIRROR_BASE_URL=https://archive.apache.org/dist
ARG BASE_URL=${MIRROR_BASE_URL}
ARG DISTRO_PATH=nifi/${NIFI_VERSION}
ARG NIFI_BINARY_PATH=${DISTRO_PATH}/nifi-${NIFI_VERSION}-bin.zip
ARG NIFI_TOOLKIT_BINARY_PATH=${DISTRO_PATH}/nifi-toolkit-${NIFI_VERSION}-bin.zip

ENV NIFI_BASE_DIR=/opt/nifi
ENV NIFI_HOME=${NIFI_BASE_DIR}/nifi-current
ENV NIFI_TOOLKIT_HOME=${NIFI_BASE_DIR}/nifi-toolkit-current
ENV NIFI_PID_DIR=${NIFI_HOME}/run
ENV NIFI_LOG_DIR=${NIFI_HOME}/logs

# Add scripts
ADD https://raw.githubusercontent.com/apache/nifi/main/nifi-docker/dockerhub/sh/start.sh ${NIFI_BASE_DIR}/scripts/
ADD https://raw.githubusercontent.com/apache/nifi/main/nifi-docker/dockerhub/sh/common.sh ${NIFI_BASE_DIR}/scripts/
ADD https://raw.githubusercontent.com/apache/nifi/main/nifi-docker/dockerhub/sh/secure.sh ${NIFI_BASE_DIR}/scripts/
ADD https://raw.githubusercontent.com/apache/nifi/main/nifi-docker/dockerhub/sh/update_cluster_state_management.sh ${NIFI_BASE_DIR}/scripts/
ADD https://raw.githubusercontent.com/apache/nifi/main/nifi-docker/dockerhub/sh/update_login_providers.sh ${NIFI_BASE_DIR}/scripts/
ADD https://raw.githubusercontent.com/apache/nifi/main/nifi-docker/dockerhub/sh/update_oidc_properties.sh ${NIFI_BASE_DIR}/scripts/
ADD https://raw.githubusercontent.com/apache/nifi/main/nifi-docker/dockerhub/sh/toolkit.sh ${NIFI_BASE_DIR}/scripts/

RUN chmod -R +x ${NIFI_BASE_DIR}/scripts/*.sh \
    && apt-get update \
    && apt-get install -y unzip curl jq xmlstarlet procps python3 python3-venv \
    && apt-get -y autoremove \
    && apt-get clean autoclean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Create nifi user but use group 0 (root) for OpenShift compatibility
RUN groupadd -g ${GID} nifi || true \
    && useradd --shell /bin/bash -u ${UID} -g ${GID} -m nifi \
    && mkdir -p ${NIFI_BASE_DIR} \
    && chown -R nifi:root ${NIFI_BASE_DIR}

# Switch to nifi user for downloads
USER nifi

# Install uv for Python
RUN curl -LsSf https://astral.sh/uv/install.sh | sh

# Download and install NiFi Toolkit
RUN curl -fSL ${MIRROR_BASE_URL}/${NIFI_TOOLKIT_BINARY_PATH} -o ${NIFI_BASE_DIR}/nifi-toolkit-${NIFI_VERSION}-bin.zip \
    && echo "$(curl ${BASE_URL}/${NIFI_TOOLKIT_BINARY_PATH}.sha512) *${NIFI_BASE_DIR}/nifi-toolkit-${NIFI_VERSION}-bin.zip" | sha512sum -c - \
    && unzip ${NIFI_BASE_DIR}/nifi-toolkit-${NIFI_VERSION}-bin.zip -d ${NIFI_BASE_DIR} \
    && rm ${NIFI_BASE_DIR}/nifi-toolkit-${NIFI_VERSION}-bin.zip \
    && mv ${NIFI_BASE_DIR}/nifi-toolkit-${NIFI_VERSION} ${NIFI_TOOLKIT_HOME} \
    && ln -s ${NIFI_TOOLKIT_HOME} ${NIFI_BASE_DIR}/nifi-toolkit-${NIFI_VERSION}

# Download and install NiFi
RUN curl -fSL ${MIRROR_BASE_URL}/${NIFI_BINARY_PATH} -o ${NIFI_BASE_DIR}/nifi-${NIFI_VERSION}-bin.zip \
    && echo "$(curl ${BASE_URL}/${NIFI_BINARY_PATH}.sha512) *${NIFI_BASE_DIR}/nifi-${NIFI_VERSION}-bin.zip" | sha512sum -c - \
    && unzip ${NIFI_BASE_DIR}/nifi-${NIFI_VERSION}-bin.zip -d ${NIFI_BASE_DIR} \
    && rm ${NIFI_BASE_DIR}/nifi-${NIFI_VERSION}-bin.zip \
    && mv ${NIFI_BASE_DIR}/nifi-${NIFI_VERSION} ${NIFI_HOME} \
    && mkdir -p ${NIFI_HOME}/conf \
    && mkdir -p ${NIFI_HOME}/database_repository \
    && mkdir -p ${NIFI_HOME}/flowfile_repository \
    && mkdir -p ${NIFI_HOME}/content_repository \
    && mkdir -p ${NIFI_HOME}/provenance_repository \
    && mkdir -p ${NIFI_HOME}/python_extensions \
    && mkdir -p ${NIFI_HOME}/nar_extensions \
    && mkdir -p ${NIFI_HOME}/state \
    && mkdir -p ${NIFI_LOG_DIR} \
    && ln -s ${NIFI_HOME} ${NIFI_BASE_DIR}/nifi-${NIFI_VERSION}

# Create empty nifi-env.sh
RUN echo "#!/bin/sh\n" > $NIFI_HOME/bin/nifi-env.sh

# CRITICAL: Make all necessary directories writable by group 0 (root group)
# This allows OpenShift to assign any UID but still have write permissions via group ownership
USER root
RUN mkdir -p ${NIFI_HOME}/run
RUN chgrp -R 0 ${NIFI_BASE_DIR} \
    && chmod -R g=u ${NIFI_BASE_DIR} \
    && chmod -R g+w ${NIFI_HOME}/conf \
    && chmod -R g+w ${NIFI_HOME}/logs \
    && chmod -R g+w ${NIFI_HOME}/database_repository \
    && chmod -R g+w ${NIFI_HOME}/flowfile_repository \
    && chmod -R g+w ${NIFI_HOME}/content_repository \
    && chmod -R g+w ${NIFI_HOME}/provenance_repository \
    && chmod -R g+w ${NIFI_HOME}/state \
    && chmod -R g+w ${NIFI_HOME}/run

# Web HTTP(s) & Socket Site-to-Site Ports
EXPOSE 8443/tcp 10000/tcp 8000/tcp

WORKDIR ${NIFI_HOME}

# Switch back to nifi user (but OpenShift will override this with arbitrary UID anyway)
USER nifi

# Apply configuration and start NiFi
ENTRYPOINT ["../scripts/start.sh"]
