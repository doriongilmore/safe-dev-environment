#!/bin/bash
set -e

# Setup git safety for cross-container permission handling
git config --global --add safe.directory "*"

# Apply identity if provided
if [ -n "$GIT_AUTHOR_NAME" ]; then
    git config --global user.name "$GIT_AUTHOR_NAME"
fi
if [ -n "$GIT_AUTHOR_EMAIL" ]; then
    git config --global user.email "$GIT_AUTHOR_EMAIL"
fi

TARGET_DIR="/workspace/${REPO_NAME:-project}"
TEMPLATE_TYPE="${TEMPLATE_TYPE:-default}"

echo "Starting Dev Environment Orchestrator..."

# Clone or Update
if [ -d "$TARGET_DIR/.git" ]; then
    echo "Existing repository found. Pulling latest..."
    cd "$TARGET_DIR"
    # git pull
else
    if [ -z "$GIT_URL" ]; then
        echo "Error: No GIT_URL provided and no existing project found."
        exit 1
    fi
    echo "Cloning $GIT_URL..."
    git clone "$GIT_URL" "$TARGET_DIR"
    cd "$TARGET_DIR"
fi

# Determine the effective workspace path
# If SUBFOLDER is "apps/api", the devcontainer runs in /workspace/project/apps/api
RELATIVE_PATH="${SUBFOLDER:-.}"
WORKSPACE_PATH="$TARGET_DIR/$RELATIVE_PATH"

# Template Logic
if [ ! -d "$WORKSPACE_PATH/.devcontainer" ]; then
    echo "Applying template to subfolder: $RELATIVE_PATH"
    mkdir -p "$WORKSPACE_PATH"
    
    if [ -d "/templates/${TEMPLATE_TYPE}" ]; then
        cp -r "/templates/${TEMPLATE_TYPE}/.devcontainer" "$WORKSPACE_PATH/"
    else
        echo "Template '${TEMPLATE_TYPE}' not found. Using basic fallback."
        cp -r "/templates/default/.devcontainer" "$WORKSPACE_PATH/"
    fi
fi

echo "Waiting for Docker daemon to wake up..."
until docker version > /dev/null 2>&1; do
  sleep 1
done
echo "Docker daemon is ready!"


# Spin up and Enter
echo "Building/Starting Dev Container..."
devcontainer up --workspace-folder "$WORKSPACE_PATH"

# Optional: Reset permissions so your host user can read/write the volumes easily
chown -R 1000:1000 "$TARGET_DIR"

# echo "Dropping you into the container. Type 'exit' to return to management layer."
# devcontainer exec --workspace-folder "$WORKSPACE_PATH" /bin/bash -i || true

echo "Interactive session ended. Management container idling..."
tail -f /dev/null
