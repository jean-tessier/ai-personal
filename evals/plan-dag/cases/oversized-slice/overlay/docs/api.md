# Public API

Consumers: the web app in `web/`, the mobile app (v3, released monthly through the app stores) and two partner
integrations that poll `/customers` and `/export` every night.

## Customers
- `GET /customers` returns `{ customers: Customer[] }`
- `GET /customers/:customerId` returns `{ customer: Customer }`
- `GET /customers/:customerId/tasks` returns `{ tasks: Task[] }`
- `POST /customers` with `{ name, email, plan }` returns `{ customer: Customer }`

## Tasks
- `GET /tasks?page=&size=&customerId=` returns `{ page, size, items: Task[] }`; each task has `customerId`
- `POST /tasks` with `{ title, customerId? }`
- `PATCH /tasks/:id`
- `GET /export` returns every task as JSON, including `customer_id`
