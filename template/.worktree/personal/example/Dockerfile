# =============================================================================
# Example personal Dockerfile — copy and customize for your own setup.
#
# 1. Create your own directory: .worktree/personal/<your-name>/Dockerfile
# 2. Add your personal tools (editors, CLIs, etc.)
# 3. Create docker-compose.local.yml from docker-compose.local.example.yml
#    and point it to your Dockerfile
#
# BASE_IMAGE is provided as a build arg by docker-compose.local.yml.
# Do not change the ARG/FROM lines.
# =============================================================================

ARG BASE_IMAGE
FROM ${BASE_IMAGE}

# Example: install neovim
# RUN sudo apt-get update && sudo apt-get install -y neovim && sudo rm -rf /var/lib/apt/lists/*
