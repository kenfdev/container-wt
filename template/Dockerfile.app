# =============================================================================
# Default app Dockerfile. Inherits from the team-shared base image.
#
# CUSTOMIZE: Add project-specific dependencies here (language runtimes,
# build tools, client libraries, etc.)
#
# The base image (devbase) is provided via additional_contexts in
# docker-compose.app.yml. Do not change the FROM line.
# =============================================================================

FROM devbase

# Examples:
#   RUN sudo apt-get update && sudo apt-get install -y postgresql-client && sudo rm -rf /var/lib/apt/lists/*
#   RUN curl -fsSL https://deb.nodesource.com/setup_20.x | sudo bash - && sudo apt-get install -y nodejs
