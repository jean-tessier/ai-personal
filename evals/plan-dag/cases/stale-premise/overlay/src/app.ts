import express from "express";
import { config } from "./config.js";
import { throttle } from "./middleware/throttle.js";
import { tasksRouter } from "./routes/tasks.js";
import { exportRouter } from "./routes/export.js";

export const app = express();

app.use(express.json());
app.use("/export", exportRouter);
app.use(throttle({ windowMs: 60_000, max: 100 }));
app.use("/tasks", tasksRouter);

if (process.env.NODE_ENV !== "test") {
  app.listen(config.port, () => console.log(`tasks-api listening on ${config.port}`));
}
