const express = require('express');
const { MongoClient } = require('mongodb');

const PORT = process.env.PORT || 3000;
const MONGODB_URI = process.env.MONGODB_URI;

// Fail fast and loudly if the connection string isn't there, rather than
// starting up in a broken state. Kubernetes injects this in the next
// stage — it is never hardcoded here.
if (!MONGODB_URI) {
  console.error('MONGODB_URI environment variable is required');
  process.exit(1);
}

const app = express();
app.use(express.urlencoded({ extended: false }));

let todosCollection;

function escapeHtml(str) {
  return str
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}

function renderPage(todos) {
  const items = todos
    .map((todo) => `<li>${escapeHtml(todo.text)}</li>`)
    .join('\n');

  return `<!DOCTYPE html>
<html>
<head>
  <title>Todo List</title>
  <style>
    body { font-family: sans-serif; max-width: 500px; margin: 40px auto; }
    li { padding: 4px 0; }
  </style>
</head>
<body>
  <h1>Todo List</h1>
  <form method="POST" action="/todos">
    <input type="text" name="text" placeholder="What needs doing?" required />
    <button type="submit">Add</button>
  </form>
  <ul>
    ${items || '<li><em>No todos yet</em></li>'}
  </ul>
</body>
</html>`;
}

app.get('/', async (req, res) => {
  const todos = await todosCollection.find().sort({ createdAt: -1 }).toArray();
  res.send(renderPage(todos));
});

app.post('/todos', async (req, res) => {
  const text = (req.body.text || '').trim();
  if (text) {
    await todosCollection.insertOne({ text, createdAt: new Date() });
  }
  res.redirect('/');
});

async function start() {
  const client = new MongoClient(MONGODB_URI);
  await client.connect();
  todosCollection = client.db('appdb').collection('todos');
  console.log('Connected to MongoDB');

  app.listen(PORT, () => {
    console.log(`Todo app listening on port ${PORT}`);
  });
}

start().catch((err) => {
  console.error('Failed to start app:', err);
  process.exit(1);
});
