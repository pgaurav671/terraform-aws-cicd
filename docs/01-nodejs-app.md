# 01 — Node.js Application

## What it is

A simple **REST API** built with Express.js. This is the application that gets containerized,
pushed to ECR, and deployed to Kubernetes. Kept deliberately simple so the focus stays on
the CI/CD pipeline rather than the app itself.

## File: `app/src/index.js`

### Setting up Express

```js
const express = require('express');
const app = express();
app.use(express.json());
```

- `express` is a web framework for Node.js — handles routing, middleware, HTTP
- `app.use(express.json())` — tells Express to automatically parse JSON request bodies

### Environment variables

```js
const PORT    = process.env.PORT    || 3000;
const APP_VERSION = process.env.APP_VERSION || '1.0.0';
const APP_ENV     = process.env.APP_ENV     || 'local';
```

- `process.env.X` reads an environment variable named X
- `|| 'default'` — fallback value if the variable is not set
- In Kubernetes, these are injected via `env:` in the Deployment manifest

### Health endpoint

```js
app.get('/health', (req, res) => {
  res.json({
    status: 'healthy',
    version: APP_VERSION,
    environment: APP_ENV,
    timestamp: new Date().toISOString()
  });
});
```

- `app.get(path, handler)` — registers a GET route
- `(req, res)` — request object (incoming) and response object (outgoing)
- `res.json(...)` — sends a JSON response with status 200

**Why /health matters:**
Kubernetes sends a request to this endpoint every few seconds. If it gets back a non-200
response (or no response), it marks the pod as unhealthy and restarts it. This is called
a **liveness probe**.

### REST endpoints

```js
app.get('/api/items', (req, res) => {
  res.json({ items: [...], total: 3 });
});

app.get('/api/items/:id', (req, res) => {
  const id = parseInt(req.params.id);
  if (id < 1 || id > 3) {
    return res.status(404).json({ error: 'Item not found' });
  }
  res.json({ id, name: `Item ${id}` });
});
```

- `:id` is a **URL parameter** — the value is available in `req.params.id`
- `res.status(404).json(...)` — sets HTTP status code before sending the response
- `return` before the 404 response exits the function early (prevents "headers already sent" error)

### Conditional server start

```js
if (require.main === module) {
  app.listen(PORT, () => {
    console.log(`Server running on port ${PORT}`);
  });
}
module.exports = app;
```

- `require.main === module` is `true` when you run `node src/index.js` directly
- It is `false` when another file does `require('./index')` — like in tests
- This pattern lets tests import the app **without starting the HTTP server**
- `module.exports = app` makes the app available to tests and other files

---

## File: `app/src/__tests__/app.test.js`

### What supertest does

```js
const request = require('supertest');
const app = require('../index');
```

- `supertest` wraps your Express app and lets you make **in-memory HTTP requests**
- No real server starts, no real network — just function calls that behave like HTTP

### Writing a test

```js
describe('Health Check', () => {
  test('GET /health returns 200', async () => {
    const res = await request(app).get('/health');
    expect(res.statusCode).toBe(200);
    expect(res.body.status).toBe('healthy');
  });
});
```

- `describe(...)` — groups related tests together
- `test(...)` — a single test case
- `async/await` — HTTP calls are async; we wait for the response before asserting
- `expect(actual).toBe(expected)` — assertion; if this fails, Jest marks the test as failed
- The CI pipeline runs all tests and **stops if any fail** — nothing gets deployed

### Running tests

```bash
cd cicd-k8s-project/app

npm install          # install dependencies first
npm test             # runs all tests once
npm test -- --watch  # re-runs on file save (dev mode)
npm test -- --coverage  # also generates a coverage report in coverage/
```

---

## File: `app/package.json`

```json
{
  "scripts": {
    "start": "node src/index.js",
    "dev":   "nodemon src/index.js",
    "test":  "jest --coverage"
  },
  "dependencies": {
    "express": "^4.18.2"
  },
  "devDependencies": {
    "jest":      "^29.7.0",
    "supertest": "^6.3.4",
    "nodemon":   "^3.0.2"
  }
}
```

- `dependencies` — needed at runtime (in production)
- `devDependencies` — only needed during development/testing; not installed with `npm ci --only=production`
- `^4.18.2` means "4.18.2 or higher, but less than 5.0.0" (semver)
- `nodemon` watches files and auto-restarts the server on save — useful in dev

---

## API Endpoints Summary

| Method | Path | Response |
|--------|------|----------|
| GET | `/` | Welcome message + version |
| GET | `/health` | `{ status: "healthy", version, environment, timestamp }` |
| GET | `/api/items` | Array of 3 items |
| GET | `/api/items/:id` | Single item (404 if id > 3) |

---

## Run locally (without Docker)

```bash
cd cicd-k8s-project/app
npm install
npm start          # starts on http://localhost:3000
```

Test with curl:
```bash
curl http://localhost:3000/health
curl http://localhost:3000/api/items
curl http://localhost:3000/api/items/1
curl http://localhost:3000/api/items/99   # returns 404
```
