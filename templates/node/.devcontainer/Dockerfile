ARG NODE_VERSION=22
FROM mcr.microsoft.com/devcontainers/javascript-node:${NODE_VERSION}-bullseye

# Install safe-npm globally
RUN npm install -g @dendronhq/safe-npm

# Replace npm with safe-npm via symlink so it works in scripts, not just interactive shells
RUN ln -sf "$(which safe-npm)" /usr/local/bin/npm

# Verify the wrapper is in place
RUN npm --version
