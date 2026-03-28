const request = require('supertest');
const app = require('../index');

describe('Health Check', () => {
  test('GET /health returns 200 with status healthy', async () => {
    const res = await request(app).get('/health');
    expect(res.statusCode).toBe(200);
    expect(res.body.status).toBe('healthy');
    expect(res.body.version).toBeDefined();
  });
});

describe('Root Endpoint', () => {
  test('GET / returns welcome message', async () => {
    const res = await request(app).get('/');
    expect(res.statusCode).toBe(200);
    expect(res.body.message).toContain('CI/CD Demo App');
  });
});

describe('Items API', () => {
  test('GET /api/items returns list of items', async () => {
    const res = await request(app).get('/api/items');
    expect(res.statusCode).toBe(200);
    expect(res.body.items).toHaveLength(3);
    expect(res.body.total).toBe(3);
  });

  test('GET /api/items/:id returns single item', async () => {
    const res = await request(app).get('/api/items/1');
    expect(res.statusCode).toBe(200);
    expect(res.body.id).toBe(1);
  });

  test('GET /api/items/:id returns 404 for invalid id', async () => {
    const res = await request(app).get('/api/items/99');
    expect(res.statusCode).toBe(404);
    expect(res.body.error).toBe('Item not found');
  });
});
