FROM debian:bullseye-slim

ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies (No sudo for better security)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    git \
    openssh-client \
    && rm -rf /var/lib/apt/lists/*

# Install Docker CLI
RUN mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" \
    | tee /etc/apt/sources.list.d/docker.list > /dev/null \
    && apt-get update && apt-get install -y docker-ce-cli

# Install Node.js & Dev Container CLI
RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
    && apt-get install -y nodejs \
    && npm install -g @devcontainers/cli

# Install opencode
RUN curl -fsSL https://opencode.ai/install | bash - 

# Pre-trust common git hosts to prevent SSH prompts
RUN mkdir -p -m 0700 ~/.ssh && \
    ssh-keyscan github.com gitlab.com bitbucket.org >> ~/.ssh/known_hosts

ENV OPENCODE_CONFIG_DIR=/root/.config/opencode
WORKDIR /workspace

# Copy and set up the bootstrap script
COPY bootstrap.sh /usr/local/bin/bootstrap.sh
RUN chmod +x /usr/local/bin/bootstrap.sh

ENTRYPOINT ["/usr/local/bin/bootstrap.sh"]

