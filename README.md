# Mustache Bash Development Environment

Uses git submodules and docker compose to provision a local development environment for the Mustache Bash suite of microservices

### HTTPS Setup
1. Visit [this page](https://medium.freecodecamp.org/how-to-get-https-working-on-your-local-development-environment-in-5-minutes-7af615770eec) and generate the certs you need for `localhost`
2. Place the three files you created in the root of this repo named `server.key`, `server.crt`, and `rootCA.pem` (for the private key, cert, and CA respectively). They are git ignored, so don't worry about accidentally committing them to the repo.
