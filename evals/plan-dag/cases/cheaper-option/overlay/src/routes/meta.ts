import { Router } from "express";
import { config } from "../config.js";

export const metaRouter = Router();

// The web client shows the beta banner when betaBanner is true.
metaRouter.get("/", (_req, res) => {
  res.json({ betaBanner: config.features.betaBanner === true });
});
