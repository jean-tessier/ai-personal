import { Router } from "express";
import { createInvoice } from "./invoice.js";

export const billingRouter = Router();

billingRouter.post("/invoices", (req, res) => {
  res.status(201).json(createInvoice(String(req.body.month)));
});
