const express = require('express');
const app = express();

app.use(express.json());

const PORT = process.env.PORT || 3000;
const APP_VERSION = process.env.APP_VERSION || '1.0.0';
const APP_ENV = process.env.APP_ENV || 'local';

// Health check — used by K8s liveness/readiness probes
app.get('/health', (req, res) => {
  res.json({
    status: 'healthy',
    version: APP_VERSION,
    environment: APP_ENV,
    timestamp: new Date().toISOString()
  });
});

// Root
app.get('/', (req, res) => {
  res.json({
    message: 'Welcome to CI/CD Demo App',
    version: APP_VERSION,
    environment: APP_ENV
  });
});

// Sample REST endpoint
app.get('/api/items', (req, res) => {
  res.json({
    items: [
      { id: 1, name: 'Item One', category: 'demo' },
      { id: 2, name: 'Item Two', category: 'demo' },
      { id: 3, name: 'Item Three', category: 'demo' }
    ],
    total: 3
  });
});

app.get('/api/items/:id', (req, res) => {
  const id = parseInt(req.params.id);
  if (id < 1 || id > 3) {
    return res.status(404).json({ error: 'Item not found' });
  }
  res.json({ id, name: `Item ${id}`, category: 'demo' });
});

// Only start server if not imported for testing
if (require.main === module) {
  app.listen(PORT, () => {
    console.log(`Server running on port ${PORT} | env=${APP_ENV} | version=${APP_VERSION}`);
  });
}

module.exports = app;
