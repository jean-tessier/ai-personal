# Multi-tenant support (draft)

Goal: several customer organisations ("tenants") use one tasks-api deployment, with their data kept apart.

## Scope
Schema, authentication, API and the web UI.

## Open decisions
1. TBD: Isolation model. A tenant_id column on every table (row-level), or one database file per tenant.
2. TBD: How a request identifies its tenant. Subdomain (acme.tasks.example), an X-Tenant header, or a claim in the
   auth token.
3. TBD: Existing data. Move every current task into a "default" tenant, or have an admin assign each one.
4. TBD: Cross-tenant access. Do support staff get a super-admin role that can see every tenant?
5. TBD: Per-tenant limits. Separate rate limits and storage quotas per tenant, or one global limit.
6. TBD: Offboarding. Hard-delete a tenant's data when it leaves, or keep it for 30 days and then delete it.

## Out of scope
Billing per tenant.
