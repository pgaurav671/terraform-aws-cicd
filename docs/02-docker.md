# 02 — Docker

## What is Docker?

Docker packages your application and all its dependencies into a **container** — a
lightweight, isolated unit that runs the same way on every machine (your laptop, CI runner,
Kubernetes node).

Think of it like this:
- Without Docker: "Works on my machine" — different OS, Node versions, library versions
- With Docker: The container carries its own OS slice, Node version, and libraries

---

## File: `app/Dockerfile`

### Stage 1 — Builder

```dockerfile
FROM node:20-alpine AS builder
WORKDIR /app
```

- `FROM node:20-alpine` — start from an official Node.js 20 image
  - `alpine` = Alpine Linux — a tiny Linux distro (~5MB vs ~300MB for full Ubuntu)
  - Smaller image = faster pulls, less attack surface, lower storage cost
- `AS builder` — names this stage "builder" so we can reference it later
- `WORKDIR /app` — all subsequent commands run inside `/app` directory

```dockerfile
COPY package*.json ./
RUN npm ci --only=production
```

- `COPY package*.json ./` — copies `package.json` AND `package-lock.json`
- **Why copy these BEFORE the source code?**
  Docker builds in layers and caches each layer. If `package.json` hasn't changed,
  Docker skips `npm ci` on the next build and reuses the cache.
  This makes rebuilds much faster — `npm ci` only re-runs when dependencies change.
- `npm ci` = clean install — faster and stricter than `npm install`, designed for CI/CD
- `--only=production` — skip devDependencies (jest, nodemon, supertest) in the final image

### Stage 2 — Runtime

```dockerfile
FROM node:20-alpine AS runtime
WORKDIR /app
```

Fresh start. This second stage does NOT inherit anything from the builder stage —
so all the build tools, npm cache, and intermediate files are gone from the final image.

```dockerfile
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
```

- Creates a **non-root user** `appuser` inside the container
- Containers run as root by default — if your app gets exploited, the attacker has root
- Running as non-root limits the blast radius

```dockerfile
COPY --from=builder /app/node_modules ./node_modules
COPY src ./src
COPY package.json ./
```

- `--from=builder` — copies from the named builder stage, not from your host machine
- We only copy what the app needs to run: `node_modules`, `src/`, `package.json`
- Everything else (tests, coverage reports, .env files) stays out

```dockerfile
RUN chown -R appuser:appgroup /app
USER appuser
```

- `chown` — give ownership of `/app` to our non-root user
- `USER appuser` — all subsequent commands (including CMD) run as this user

```dockerfile
ENV PORT=3000
ENV NODE_ENV=production
EXPOSE 3000
```

- `ENV` — sets default environment variables inside the container
  - These can be overridden at runtime (`docker run -e PORT=8080 ...`)
- `EXPOSE 3000` — documents which port the app listens on (informational, doesn't actually open the port)

```dockerfile
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://localhost:3000/health || exit 1
```

- Docker checks the app's health every 30 seconds
- `--start-period=10s` — wait 10s before first check (app needs time to start)
- `--retries=3` — mark unhealthy only after 3 consecutive failures
- `wget -qO-` — silent HTTP GET, prints response body
- `|| exit 1` — if wget fails (non-200 or connection refused), exit with code 1 = unhealthy

```dockerfile
CMD ["node", "src/index.js"]
```

- The command that runs when the container starts
- Using array form `["node", "src/index.js"]` (exec form) — does NOT start a shell,
  so signals (SIGTERM for graceful shutdown) go directly to node

---

## Why Multi-Stage Builds?

Single stage (bad):
```
Final image = Node.js + ALL npm packages (including devDeps) + build tools
Size: ~400MB
```

Multi-stage (what we use):
```
Builder stage = Node.js + devDeps + build tools  (discarded)
Runtime stage = Node.js + only production deps
Size: ~80MB
```

Smaller images = faster ECR pushes, faster Kubernetes pod starts, less cost.

---

## File: `app/.dockerignore`

```
node_modules
coverage
*.test.js
__tests__
.env
```

Like `.gitignore` but for Docker. Files listed here are NOT sent to the Docker build context.

- `node_modules` — never copy your local node_modules; the Dockerfile installs its own
- `.env` — never bake secrets into images
- Test files — not needed in production images

---

## File: `docker-compose.yml`

```yaml
services:
  app:
    build:
      context: ./app
      dockerfile: Dockerfile
    ports:
      - "3000:3000"    # host:container
    environment:
      - APP_ENV=local
      - APP_VERSION=1.0.0
```

- `context: ./app` — Docker build context is the `app/` directory
- `ports: "3000:3000"` — map host port 3000 to container port 3000
  - Format: `"HOST_PORT:CONTAINER_PORT"`
  - You visit `localhost:3000`, it reaches the container's port 3000

---

## Docker Commands

```bash
# Build an image
docker build -t cicd-demo-app:local ./app

# Run a container
docker run -p 3000:3000 cicd-demo-app:local

# Run with environment variables
docker run -p 3000:3000 -e APP_ENV=staging cicd-demo-app:local

# Run in background (detached)
docker run -d -p 3000:3000 --name myapp cicd-demo-app:local

# See running containers
docker ps

# See logs
docker logs myapp
docker logs myapp -f   # follow (like tail -f)

# Stop and remove
docker stop myapp
docker rm myapp

# Get a shell inside running container
docker exec -it myapp sh

# See image size
docker images cicd-demo-app

# Remove image
docker rmi cicd-demo-app:local
```

## Docker Compose Commands

```bash
# Build and start
docker-compose up

# Build and start in background
docker-compose up -d

# Force rebuild (use when Dockerfile or source changed)
docker-compose up --build

# Stop and remove containers
docker-compose down

# See logs
docker-compose logs -f

# Get a shell into the app container
docker-compose exec app sh
```

---

## ECR (AWS Container Registry)

ECR is AWS's private Docker registry — like Docker Hub but in your AWS account.

```bash
# Authenticate Docker to ECR
aws ecr get-login-password --region ap-south-1 | \
  docker login --username AWS --password-stdin \
  340529310701.dkr.ecr.ap-south-1.amazonaws.com

# Tag your local image for ECR
docker tag cicd-demo-app:local \
  340529310701.dkr.ecr.ap-south-1.amazonaws.com/cicd-demo-app:latest

# Push to ECR
docker push 340529310701.dkr.ecr.ap-south-1.amazonaws.com/cicd-demo-app:latest

# Pull from ECR
docker pull 340529310701.dkr.ecr.ap-south-1.amazonaws.com/cicd-demo-app:latest
```

In CI/CD, the GitHub Actions workflow does all of this automatically using the
`aws-actions/amazon-ecr-login` and `docker/build-push-action` actions.
