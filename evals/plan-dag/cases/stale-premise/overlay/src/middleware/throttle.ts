import type { NextFunction, Request, Response } from "express";

type Options = { windowMs: number; max: number };

// Fixed-window request throttle keyed by client IP. In-memory, so it covers one process only.
export function throttle({ windowMs, max }: Options) {
  const hits = new Map<string, { count: number; resetAt: number }>();
  return (req: Request, res: Response, next: NextFunction) => {
    const key = req.ip ?? "unknown";
    const now = Date.now();
    const entry = hits.get(key);
    if (!entry || entry.resetAt <= now) {
      hits.set(key, { count: 1, resetAt: now + windowMs });
      return next();
    }
    if (entry.count >= max) {
      res.setHeader("Retry-After", Math.ceil((entry.resetAt - now) / 1000));
      return res.status(429).json({ error: "too many requests" });
    }
    entry.count += 1;
    next();
  };
}
