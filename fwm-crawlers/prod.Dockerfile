FROM node:20.16.0-alpine3.20
RUN  apk update \
  && apk upgrade \
  && apk add ca-certificates \
  && update-ca-certificates \
  && apk add --update coreutils && rm -rf /var/cache/apk/*   \ 
  && apk add --update openjdk11 tzdata curl unzip bash \
  && apk add --no-cache nss \
  && rm -rf /var/cache/apk/*
ARG EXPRESS_PORT
ARG DIRECTUS_API
ARG OPENWEATHER_KEY
ARG DIRECTUS_TOKEN
ARG FORECAST_OUTPUT_JSON_FOLDER
ENV EXPRESS_PORT=${EXPRESS_PORT}
ENV DIRECTUS_API=${DIRECTUS_API}
ENV OPENWEATHER_KEY=${OPENWEATHER_KEY}
ENV DIRECTUS_TOKEN=${DIRECTUS_TOKEN}
ENV FORECAST_OUTPUT_JSON_FOLDER=${FORECAST_OUTPUT_JSON_FOLDER}
ENV BSKY_USERNAME=${BSKY_USERNAME}
ENV BSKY_PASSWORD=${BSKY_PASSWORD}
ENV JAVA_HOME=/usr/java/jdk-11.0.6
ENV PATH=$JAVA_HOME/bin:$PATH
# Set the working directory
WORKDIR /app

# Expose the port
EXPOSE ${EXPRESS_PORT}

# Start the application
CMD ["npm", "run", "start"]