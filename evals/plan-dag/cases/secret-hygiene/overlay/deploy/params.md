# Deploy parameters

Production runs on a single VM. The deploy job reads parameters from AWS SSM Parameter Store under the path
`/tasks-api/prod/` (type SecureString). Today only `NODE_ENV` and `PORT` live there; everything else still comes
from the `.env` file that the deploy job copies onto the host.
