# SLMS Local Setup Guide

## ✅ Current Status

### Completed:
- ✅ Dependencies installed (pnpm install)
- ✅ Shared package built
- ✅ Docker infrastructure running:
  - PostgreSQL (port 5544)
  - Redis (port 6379)
  - Mailhog (ports 8025, 1025)
- ✅ Environment files exist (api, web)
- ✅ Database connection verified

### ⚠️ Action Required:

#### 1. Run Database Migrations (Interactive - Run in your terminal)

Prisma migrations require an interactive terminal. Run this command in your terminal:

```powershell
cd "d:\Project\Sustainability Certification and Licensing Management System\Frontend\slms\apps\api"
pnpm prisma migrate dev --name init
```

This will:
- Create the initial migration
- Apply it to create Prisma tables (users, roles, permissions, etc.)
- Generate the Prisma client

#### 2. Seed the Database

After migrations complete, run:

```powershell
cd "d:\Project\Sustainability Certification and Licensing Management System\Frontend\slms"
pnpm db:seed
```

This creates:
- Default roles (SustainabilityAdmin, Legal, Auditor, PublicReader)
- Permissions
- Notification rules
- Default users (admin@slms.local, auditor@slms.local)

#### 3. Configure JWT Secrets (Optional but Recommended)

For production-like setup, generate secure secrets:

**For API (`apps/api/.env`):**
```powershell
# Generate JWT secrets
openssl rand -base64 64
```
Update `JWT_SECRET` and `JWT_REFRESH_SECRET` in `apps/api/.env`

#### 4. Start All Services

Once migrations and seeding are complete:

```powershell
cd "d:\Project\Sustainability Certification and Licensing Management System\Frontend\slms"
pnpm dev
```

This starts:
- **API** on http://localhost:3001
- **Web Portal** on http://localhost:3000

## 🌐 Service URLs

| Service | URL | Description |
|---------|-----|-------------|
| **Web Portal** | http://localhost:3000 | Public sustainability portal |
| **API Swagger** | http://localhost:3001/docs | API documentation |
| **API Endpoint** | http://localhost:3001/api/v1 | REST API |
| **Strapi Admin** | http://localhost:1337/admin | CMS admin panel |
| **Mailhog** | http://localhost:8025 | Email testing UI |

## 🔧 Quick Commands

### Start individual services:
```powershell
pnpm dev:api    # Start only API
pnpm dev:web    # Start only Web Portal
```

### Infrastructure:
```powershell
pnpm dev:infra        # Start Docker services
pnpm dev:infra:logs   # View logs
pnpm dev:infra:down   # Stop services
pnpm dev:infra:reset  # Reset everything (removes data!)
```

### Database:
```powershell
pnpm db:migrate   # Run migrations
pnpm db:seed      # Seed database
pnpm db:studio    # Open Prisma Studio
pnpm db:reset     # Reset database (WARNING: drops all data!)
```

## 🐛 Troubleshooting

### Port Conflicts
Check if ports are in use:
```powershell
netstat -ano | findstr :3000
netstat -ano | findstr :3001
```

Kill a process:
```powershell
taskkill /PID <PID> /F
```

### Database Connection Issues
```powershell
# Check if PostgreSQL is running
docker ps | Select-String postgres

# Test connection
docker exec slms-postgres psql -U slms -d slms -c "SELECT 1"
```

### Prisma Migration Issues
If migrations fail:
```powershell
cd apps/api
pnpm prisma generate
pnpm prisma migrate dev
```

### Reset Everything
```powershell
pnpm dev:infra:reset
pnpm clean
pnpm install
pnpm build:shared
pnpm dev:infra
# Wait 10 seconds
pnpm db:migrate
pnpm db:seed
pnpm dev
```

## 📝 Notes

- Default credentials for local development are in the README
- MinIO bucket `slms-docs` is created automatically on startup
- Email testing uses Mailhog - all emails are captured in the UI
