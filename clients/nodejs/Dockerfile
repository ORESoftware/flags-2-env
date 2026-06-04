FROM node:22-bookworm

WORKDIR /repo
COPY Makefile ./
COPY package.json ./
COPY src ./src
COPY tests ./tests
COPY clients/nodejs ./clients/nodejs

RUN apt-get update && apt-get install -y --no-install-recommends build-essential python3 make && rm -rf /var/lib/apt/lists/*
RUN mkdir -p tests/fixtures/nested/deeper && make clean && make all

WORKDIR /repo/clients/nodejs
RUN npm install --prefix /repo --ignore-scripts --no-save --package-lock=false node-gyp typescript@latest @types/node@latest
RUN /repo/node_modules/.bin/node-gyp rebuild
RUN useradd --create-home --shell /bin/sh flags2env && \
  mkdir -p /tmp/flags2env-cache && \
  chown -R flags2env:flags2env /repo /tmp/flags2env-cache

ENV HOME=/home/flags2env
ENV XDG_CACHE_HOME=/tmp/flags2env-cache
ENV FLAGS2ENV_NODE_ADDON=/repo/clients/nodejs/build/Release/flags2env.node
USER flags2env

CMD node test.mjs && node test.cjs && /repo/node_modules/.bin/tsc --noEmit --module ESNext --moduleResolution Bundler --target ES2022 --allowImportingTsExtensions --types node --skipLibCheck test.ts && node --experimental-strip-types test.ts
