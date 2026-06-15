ARG DEBIAN_VERSION=bullseye-slim
FROM debian:${DEBIAN_VERSION}

ENV DEBIAN_FRONTEND=noninteractive

# System dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    git \
    openssh-client \
    bash-completion \
    && rm -rf /var/lib/apt/lists/*

# Docker CLI
RUN mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/debian/gpg \
       | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
       https://download.docker.com/linux/debian $(lsb_release -cs) stable" \
       | tee /etc/apt/sources.list.d/docker.list > /dev/null \
    && apt-get update && apt-get install -y --no-install-recommends docker-ce-cli \
    && rm -rf /var/lib/apt/lists/*

# Node.js (version via build arg)
ARG NODE_VERSION=22
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# @devcontainers/cli (version fixed via build arg)
ARG DEVCONTAINER_CLI_VERSION=0.75.0
RUN npm install -g @devcontainers/cli@${DEVCONTAINER_CLI_VERSION}

# opencode
RUN curl -fsSL https://opencode.ai/install | bash -

# Pre-trust common git hosts
RUN mkdir -p -m 0700 ~/.ssh \
    && ssh-keyscan github.com gitlab.com bitbucket.org >> ~/.ssh/known_hosts 2>/dev/null

ENV OPENCODE_CONFIG_DIR=/root/.config/opencode
WORKDIR /workspace

# Only entrypoint.sh is baked into the image.
# wks and other scripts are available via bind mount (/workspace_root/scripts/)
# and symlinked into PATH at container startup by entrypoint.sh.
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
