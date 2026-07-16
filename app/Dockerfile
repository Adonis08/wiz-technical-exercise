# Small, official Node.js base image (Alpine Linux) — smaller attack
# surface and faster pulls than the default node image.
FROM node:20-alpine

WORKDIR /app

# Dependencies are installed in their own layer, separate from the app
# code below. Docker caches each instruction as a layer: as long as
# package.json/package-lock.json don't change, this layer is reused on
# rebuilds instead of re-running npm install every time server.js changes.
COPY package*.json ./
RUN npm install --omit=dev

# Now copy the actual application code.
COPY server.js ./

# ASSESSED REQUIREMENT: copies wizexercise.txt (created locally, containing
# your name) into the image at /app/wizexercise.txt.
#
# How it gets in: COPY only ever reads from the "build context" — the
# directory you point `docker build` at (here, this app/ folder) — never
# from anywhere else on disk. So wizexercise.txt must exist in this same
# folder, next to this Dockerfile, *before* you run `docker build`; this
# instruction then copies it into the image as its own explicit layer.
# To prove it's really in there: `docker run --rm <image> cat wizexercise.txt`.
COPY wizexercise.txt ./

# node:alpine ships a built-in non-root "node" user — running as it
# instead of root is a basic container hardening step.
USER node

EXPOSE 3000

CMD ["node", "server.js"]
