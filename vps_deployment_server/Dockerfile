FROM dart:3.3.0 AS build

# Accept the GITHUB_PAT and GITHUB_USER as an argument
ARG GITHUB_PAT
ARG GITHUB_USER

WORKDIR /app
COPY . .

# Conditionally configure Git to use the provided GitHub token
RUN if [ -n "$GITHUB_PAT" ] && [ -n "$GITHUB_USER" ]; then \
        echo "Configuring Git to use provided GitHub token..."; \
        # Add GitHub's public SSH key to known_hosts for security
        mkdir -p -m 0600 ~/.ssh && ssh-keyscan github.com >> ~/.ssh/known_hosts; \
        git config --global credential.helper 'store'; \
        echo "url=https://github.com/.insteadOf git://github.com/" >> ~/.gitconfig; \
        echo "https://$GITHUB_USER:$GITHUB_PAT@github.com" > ~/.git-credentials; \
    else \
        echo "No GitHub token provided. Skipping Git configuration..."; \
    fi

RUN dart pub get
RUN dart compile exe bin/main.dart -o bin/server

FROM alpine:latest

# Correcting the source directory for runtime dependencies
COPY --from=build /runtime/ /
COPY --from=build /app/bin/server server
COPY --from=build /app/config/ config/
COPY --from=build /app/web/ web/
COPY --from=build /app/migrations/ migrations/

# Create an empty passwords.yaml file in the config directory
RUN mkdir -p config 
RUN touch config/passwords.yaml 
# This will just add the line it the bottom of the file and will not break any existing yaml structure
# Currently this is necessary if you do not supply a passwords.yaml file in the config directory
RUN echo "prevent_yaml_package_breaking: serverpod_startup" >> config/passwords.yaml

# Set appropriate permissions for config directory and passwords.yaml file
RUN chmod 644 config/passwords.yaml

EXPOSE 8080
EXPOSE 8081
EXPOSE 8082

ENTRYPOINT ["/server"]
CMD ["--mode", "production", "--server-id", "default", "--logging", "normal", "--role", "monolith"]
