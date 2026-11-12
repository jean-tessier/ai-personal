import { Router } from "express";
import { createCustomer, getCustomer, listCustomers } from "../services/customerService.js";
import { customerRepository } from "../repositories/customerRepository.js";

export const customersRouter = Router();

customersRouter.get("/", (_req, res) => res.json({ customers: listCustomers() }));

customersRouter.get("/:customerId", (req, res) => {
  const customer = getCustomer(Number(req.params.customerId));
  if (!customer) return res.status(404).json({ error: "customer not found" });
  res.json({ customer });
});

customersRouter.get("/:customerId/tasks", (req, res) => {
  res.json({ tasks: customerRepository.tasksForCustomer(Number(req.params.customerId)) });
});

customersRouter.post("/", (req, res) => {
  const customer = createCustomer(req.body);
  res.status(201).json({ customer });
});
