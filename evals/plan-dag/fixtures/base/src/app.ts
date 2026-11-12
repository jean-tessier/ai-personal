import express from "express";
import { config } from "./config.js";
import { tasksRouter } from "./routes/tasks.js";
import { exportRouter } from "./routes/export.js";

export const app = express();

app.use(express.json());
app.use("/tasks", tasksRouter);
app.use("/export", exportRouter);

if (process.env.NODE_ENV !== "test") {
  app.listen(config.port, () => console.log(`tasks-api listening on ${config.port}`));
}
