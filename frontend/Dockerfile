# syntax=docker/dockerfile:1
# --- build stage ---
FROM node:22-alpine AS build
WORKDIR /app

COPY package*.json ./
RUN npm ci

# Vite inlines env vars at BUILD time, so VITE_API_URL must be present here.
# Railway passes service variables to the build as ARGs automatically.
ARG VITE_API_URL
ENV VITE_API_URL=$VITE_API_URL

COPY . .
RUN npm run build

# --- runtime stage ---
FROM nginx:1.27-alpine
# Railway injects $PORT; the nginx entrypoint runs envsubst on this template.
# Default to 80 for plain `docker run` without -e PORT.
ENV PORT=80
COPY --from=build /app/dist /usr/share/nginx/html
COPY nginx.conf.template /etc/nginx/templates/default.conf.template
EXPOSE 80
