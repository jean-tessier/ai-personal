import Database from "better-sqlite3";
import { config } from "./config.js";

export const db = new Database(config.dbFile);
db.pragma("journal_mode = WAL");
