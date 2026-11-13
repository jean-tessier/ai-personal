export type CustomerId = number;

export type Customer = {
  id: CustomerId;
  name: string;
  email: string;
  plan: "free" | "pro";
  createdAt: string;
};

export type NewCustomer = Omit<Customer, "id" | "createdAt">;
