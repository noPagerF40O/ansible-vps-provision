# docker/ansible/Dockerfile
# syntax=docker/dockerfile=1.4

FROM alpine:3.19

ARG USERNAME
ARG USER_UID
ARG USER_GID
ARG KEYS_MOUNT_PATH
ARG WORKDIR

RUN apk add --no-cache \
    bash \
    python3 \
    py3-pip \
    openssh-client \
    git \
    && rm -rf /var/cache/apk/*

RUN pip3 install --no-cache-dir --break-system-packages \
    ansible \
    ansible-lint \
    yamllint \
    jmespath \
    hvac \
    requests \
    urllib3 

RUN addgroup -g ${USER_GID} ${USERNAME} && \
    adduser -D -u ${USER_UID} -G ${USERNAME} ${USERNAME}

RUN mkdir -p /home/${USERNAME}/.ansible && \
    mkdir -p /etc/ansible && \
    chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}

RUN mkdir -p ${KEYS_MOUNT_PATH} && \
    chown -R ${USER_UID}:${USER_GID} ${KEYS_MOUNT_PATH} && \
    chmod 755 ${KEYS_MOUNT_PATH}

COPY --chown=${USERNAME}:${USERNAME} --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh

USER ${USERNAME}
WORKDIR ${WORKDIR}

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]