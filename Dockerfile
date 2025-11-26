FROM n8nio/n8n

USER root

# Install axios, node-fetch, and iso8601-duration globally
RUN npm install -g axios node-fetch iso8601-duration

USER node
