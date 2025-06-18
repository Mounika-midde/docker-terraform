const express = require("express");
const app = express();
const port = 5000;

app.get("/", (req, res) => {
  res.send("Hello from Dockerized Node.js App!");
});

app.listen(port, () => {
  console.log(`App is running on http://localhost:${port}`);
});
