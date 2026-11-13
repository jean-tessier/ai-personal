import express from "express";
import { config } from "./config.js";
import { tasksRouter } from "./routes/tasks.js";
import { exportRouter } from "./routes/export.js";
import { billingRouter } from "./billing/index.js";

export const app = express();

app.use(express.json());
app.use("/tasks", tasksRouter);
app.use("/export", exportRouter);
app.use("/billing", billingRouter);

if (process.env.NODE_ENV !== "test") {
  app.listen(config.port, () => console.log(`tasks-api listening on ${config.port}`));
}
