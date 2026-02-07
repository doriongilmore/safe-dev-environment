# 🛡️ Dev-Environment Orchestrator

An automated, containerized system to provision isolated, pre-configured development environments. It bridges the gap between raw source code and a fully functional, secure developer workspace using Docker-in-Docker (DinD) and Dev Containers.

# 🎯 Project Goal

To allow developers to go from a repository URL to a safe, language-specific development environment in a single command, without polluting their host machine with toolchains (Node, PHP, etc.) or exposing the host's Docker socket directly to untrusted code.
# 🏗️ Architectural Decisions
1) The "Management Layer" (Orchestrator)

    The dev service (built from the Dockerfile) acts as a smart controller. It handles Git operations, identity configuration, and template injection. It never runs your application code itself; it only manages the lifecycle of the environment that does.

2) Sidecar Docker Daemon (Isolation)

    We use a docker:dind sidecar (daemon service) instead of mounting the host's /var/run/docker.sock.

    - Security: If a malicious package (e.g., via a compromised npm library) tries to escape the container, it only sees the isolated sidecar environment, not your host machine's images or other containers.

    - Cleanliness: All images pulled for your dev environments live in a dedicated volume (docker_cache), keeping your host machine clean.

3) SSH Agent Forwarding

    Private repositories are cloned using your host's SSH agent via a socket mount. Your private keys never touch the container's file system, ensuring your credentials remain secure on your host hardware.

4) Template-Driven Provisioning

    If a repository lacks a .devcontainer configuration, the orchestrator detects the project type (via TEMPLATE_TYPE) and injects a standardized, secure template (including safety wrappers like safe-npm) before spinning up the environment.

# 🚀 Getting Started
## Prerequisites

- Git, Docker and Docker Compose installed.

- An active SSH agent on your host (ssh-add -l should show your keys).

## Setup

- Clone this orchestrator to your local machine.

- Configure your environment:
    ```
    cp .env.sample .env && mkdir workspace
    ```

    - Edit .env to set your GIT_URL, name, and the SSH_AUTH_SOCK path.

    - Prepare local folder: Ensure the `workspace` directory exists.

## Execution

- Run the orchestrator:

    `docker compose up --build`

- The orchestrator will:

    - Clone the repository into ./workspace/REPO_NAME.

    - Apply the selected template if no .devcontainer exists.

    - Trigger `devcontainer up` to build the inner environment.

## Entering the Workspace

Since the management container idles after setup, you can enter your newly minted environment by running:

`docker exec -it <inner_container_name> /bin/bash -i`

# 📂 Project Structure

- Dockerfile: Defines the orchestrator with Git, Docker CLI, and Dev Container CLI.

- bootstrap.sh: The "brain" of the project; handles cloning, identity, and template injection.

- compose.yaml: Orchestrates the manager and the isolated Docker daemon.

- templates/: Contains language-specific .devcontainer setups (e.g., Node.js with safe-npm).

# 🛠️ Possible Improvements

- Multi-Subfolder Support: Extend bootstrap.sh to loop through a comma-separated list of SUBFOLDERS to spin up microservices simultaneously.

- Automatic Tech Detection: Replace the TEMPLATE_TYPE env var with a logic block in bootstrap.sh that detects package.json (Node), composer.json (PHP), or requirements.txt (Python) to select the template automatically.

- GPG Signing: Implement GPG agent forwarding to allow for signed commits within the dev environment.

- Health Checks: Implement a more robust wait-for-it check between the manager and the daemon to ensure zero-fail startups.

- Custom CLI: Wrap the docker compose commands into a simple shell script (e.g., ./start-dev git@github...) for a smoother UX.

- More Templates
