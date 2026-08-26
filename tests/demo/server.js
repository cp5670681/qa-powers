// 依赖：Node 18+、sqlite3 CLI（macOS 自带）。仅供 qa-powers 冒烟测试用。
const http = require("http");
const { execFileSync } = require("child_process");
const fs = require("fs");
const path = require("path");

const PORT = 8899;
const DB = path.join(__dirname, "..", "demo-db.sqlite");
const exec = (sql) => execFileSync("sqlite3", [DB, sql], { encoding: "utf8" });

// 初始化表与测试商品（幂等）
exec("CREATE TABLE IF NOT EXISTS orders (id INTEGER PRIMARY KEY AUTOINCREMENT, product TEXT, amount INTEGER, status TEXT)");
exec("CREATE TABLE IF NOT EXISTS products (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, stock INTEGER)");
if (exec("SELECT COUNT(*) FROM products").trim() === "0") {
  exec("INSERT INTO products (name, stock) VALUES ('测试商品A', 10)");
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url, `http://localhost:${PORT}`);
  if (req.method === "POST" && url.pathname === "/api/order") {
    let body = "";
    req.on("data", (c) => (body += c));
    req.on("end", () => {
      let parsed;
      try {
        parsed = JSON.parse(body || "{}");
      } catch {
        res.writeHead(400, { "Content-Type": "application/json" });
        return res.end(JSON.stringify({ error: "参数错误" }));
      }
      const { product, amount } = parsed;
      if (!product || !Number.isInteger(amount) || amount < 1) {
        res.writeHead(400, { "Content-Type": "application/json" });
        return res.end(JSON.stringify({ error: "参数错误" }));
      }
      const id = exec(
        `INSERT INTO orders (product, amount, status) VALUES ('${product.replace(/'/g, "''")}', ${amount}, 'pending'); SELECT last_insert_rowid();`
      ).trim();
      exec(`UPDATE products SET stock = stock - ${amount} WHERE name = '${product.replace(/'/g, "''")}'`);
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ ok: true, orderId: id }));
    });
    return;
  }
  const file = url.pathname === "/" ? "index.html" : url.pathname.replace(/\.\./g, "");
  try {
    const content = fs.readFileSync(path.join(__dirname, "public", file));
    res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
    res.end(content);
  } catch {
    res.writeHead(404);
    res.end("not found");
  }
});

server.listen(PORT, "127.0.0.1", () => console.log(`demo: http://localhost:${PORT}  db: ${DB}`));
