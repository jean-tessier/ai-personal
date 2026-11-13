# tasks-api

A small HTTP API for team task lists, built with Express.

## Run

    npm install
    npm run build && npm start

## Configuration

Settings live in `config/default.json`, overridden per environment by `config/<NODE_ENV>.json`.
Config files ship with each deploy.

## Endpoints

- `GET /tasks?page=&size=` returns a page of tasks
- `POST /tasks` creates a task
- `PATCH /tasks/:id` marks a task done or not done
- `GET /export` downloads every task as JSON

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Architecture decisions are recorded in [docs/adrs/](docs/adrs/INDEX.md).
