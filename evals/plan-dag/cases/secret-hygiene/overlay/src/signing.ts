import { createHmac } from "node:crypto";

const key = process.env.EXPORT_SIGNING_KEY ?? "";

export function signExport(body: string): string {
  return createHmac("sha256", key).update(body).digest("hex");
}
