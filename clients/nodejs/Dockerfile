FROM node:22-bookworm

WORKDIR /repo
COPY . .

RUN apt-get update && apt-get install -y --no-install-recommends build-essential python3 make && rm -rf /var/lib/apt/lists/*
RUN make clean && make all

WORKDIR /repo/clients/nodejs
RUN npm install --no-save node-gyp
RUN npx node-gyp rebuild

ENV FLAGS2ENV_NODE_ADDON=/repo/clients/nodejs/build/Release/flags2env.node
CMD node test.mjs && node test.cjs
