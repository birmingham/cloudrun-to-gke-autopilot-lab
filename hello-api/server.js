const http = require("http");

const port = process.env.PORT || 8080;
let ready = false;

// Simulate startup work: not ready for the first 3 seconds.
setTimeout(() => { ready = true; }, 3000);

const server = http.createServer((req, res) => {
  if (req.url === "/healthz") {
    res.writeHead(200);
    return res.end("ok");
  }
  if (req.url === "/readyz") {
    res.writeHead(ready ? 200 : 503);
    return res.end(ready ? "ready" : "starting");
  }
  res.writeHead(200, { "Content-Type": "application/json" });
  res.end(JSON.stringify({ message: "hello", host: process.env.HOSTNAME || "local" }));
});

server.listen(port, () => console.log(`listening on ${port}`));

// Graceful shutdown: stop reporting ready, finish in-flight requests, then exit.
process.on("SIGTERM", () => {
  console.log("SIGTERM received, draining");
  ready = false;
  setTimeout(() => server.close(() => process.exit(0)), 5000);
});
