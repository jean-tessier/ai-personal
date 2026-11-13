import { customerEvents } from "../events/customerEvents.js";

customerEvents.on("customer.created", ({ customerId, email }) => {
  console.log(`welcome mail queued for customer ${customerId} <${email}>`);
});
