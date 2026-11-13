import type { CustomerId } from "./customer.js";

export type Task = {
  id: number;
  title: string;
  done: boolean;
  createdAt: string;
  customerId: CustomerId | null;
};
