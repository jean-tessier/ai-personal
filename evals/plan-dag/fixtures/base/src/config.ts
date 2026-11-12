import { existsSync, readFileSync } from "node:fs";

type Config = {
  port: number;
  dbFile: string;
  features: Record<string, boolean>;
};

function load(name: string): Partial<Config> {
  const path = `config/${name}.json`;
  return existsSync(path) ? JSON.parse(readFileSync(path, "utf8")) : {};
}

const env = process.env.NODE_ENV ?? "development";
const base = load("default");
const override = load(env);

export const config = {
  ...base,
  ...override,
  features: { ...(base.features ?? {}), ...(override.features ?? {}) },
} as Config;
