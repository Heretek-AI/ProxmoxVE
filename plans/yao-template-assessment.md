# Yao Template Minimum Install Assessment

## Executive Summary

This assessment compares the current `install/yao-install.sh` script against the official Yao documentation requirements for a minimum viable installation. The analysis identifies gaps and provides recommendations for improvement.

---

## Current Install Script Analysis

### What the Script Currently Creates

| Directory/File | Status | Notes |
|----------------|--------|-------|
| `/opt/yao/data` | ✅ Created | Correct |
| `/opt/yao/etc` | ⚠️ Created | Not standard per docs |
| `/opt/yao/connectors` | ✅ Created | Correct for AI connectors |
| `/opt/yao/scripts` | ✅ Created | Correct for custom processes |
| `/opt/yao/suis` | ✅ Created | Correct for SUI widgets |
| `/opt/yao/agent` | ❌ Wrong name | Should be `agents/` or `neo/` |
| `/opt/yao/openapi` | ❌ Non-standard | APIs should be in `apis/` |
| `/opt/yao/db` | ✅ Created | Correct for database |
| `/opt/yao/app.yao` | ⚠️ Minimal | Missing key configuration |
| `/opt/yao/.env` | ⚠️ Minimal | Missing key variables |

---

## Documentation Requirements

### Required Directory Structure

Based on the official documentation, a proper Yao application should have:

```
/opt/yao/
├── app.yao              # Main application config (REQUIRED)
├── tsconfig.json        # TypeScript config (RECOMMENDED)
├── .env                 # Environment variables (REQUIRED)
├── db/                  # Database files (REQUIRED)
│   └── yao.db
├── models/              # Data models (.mod.yao files)
├── apis/                # REST API definitions (.http.yao files)
├── scripts/             # Custom processes (.ts files)
├── forms/               # Form widgets (.form.yao files)
├── tables/              # Table widgets (.tab.yao files)
├── flows/               # Flow processes (.flow.yao files)
├── schedules/           # Scheduled tasks (.sch.yao files)
├── connectors/          # AI connectors (.conn.yao files)
├── suis/                # SUI widget configuration
├── neo/                 # Neo chatbot configuration
├── data/                # Data storage
│   └── templates/       # Web page templates
│       └── default/
├── public/              # Static files (built from SUI)
└── logs/                # Application logs
```

---

## Missing Directories

| Directory | Purpose | Priority |
|-----------|---------|----------|
| `models/` | Data model definitions (.mod.yao) | **HIGH** |
| `apis/` | REST API definitions (.http.yao) | **HIGH** |
| `forms/` | Form widgets for admin panel | MEDIUM |
| `tables/` | Table widgets for admin panel | MEDIUM |
| `flows/` | Flow processes (e.g., menu.flow.yao) | MEDIUM |
| `schedules/` | Scheduled tasks (.sch.yao) | LOW |
| `neo/` | Neo chatbot configuration | LOW |
| `data/templates/default/` | Web page templates | MEDIUM |
| `public/` | Static files directory | MEDIUM |
| `logs/` | Application logs | **HIGH** |

---

## Environment Variables Analysis

### Current `.env` File
```bash
YAO_PORT=5099
YAO_STUDIO_PORT=5077
```

### Required/Recommended Variables (per documentation)

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `YAO_ENV` | ✅ Yes | `production` | Application mode |
| `YAO_PORT` | ✅ Yes | `5099` | HTTP server port |
| `YAO_HOST` | Recommended | `0.0.0.0` | Server listen address |
| `YAO_DB_DRIVER` | ✅ Yes | `sqlite3` | Database driver |
| `YAO_DB_PRIMARY` | ✅ Yes | `./db/yao.db` | Database path/DSN |
| `YAO_LOG` | Recommended | `./logs/application.log` | Log file path |
| `YAO_LOG_MODE` | Recommended | `TEXT` | Log format (TEXT/JSON) |
| `YAO_JWT_SECRET` | ✅ Yes | - | JWT authentication secret |
| `YAO_SESSION_STORE` | Recommended | `file` | Session storage type |
| `YAO_SESSION_FILE` | If file session | `./db/.session` | Session file path |
| `YAO_LANG` | Optional | `en-us` | Default language |
| `YAO_TIMEZONE` | Optional | - | Timezone |
| `YAO_DATA_ROOT` | Optional | `./data` | Data storage path |
| `YAO_STUDIO_PORT` | Optional | `5077` | Studio port (dev) |

### Recommended `.env` File
```bash
# Application Settings
YAO_ENV=production
YAO_HOST=0.0.0.0
YAO_PORT=5099
YAO_LANG=en-us

# Database Settings
YAO_DB_DRIVER=sqlite3
YAO_DB_PRIMARY=./db/yao.db

# Logging Settings
YAO_LOG=./logs/application.log
YAO_LOG_MODE=TEXT
YAO_LOG_MAX_SIZE=100
YAO_LOG_MAX_AGE=7
YAO_LOG_MAX_BACKUPS=3

# Security Settings
YAO_JWT_SECRET=change-me-in-production

# Session Settings
YAO_SESSION_STORE=file
YAO_SESSION_FILE=./db/.session
```

---

## `app.yao` Configuration Analysis

### Current `app.yao`
```json
{
  "name": "yao-app",
  "version": "1.0.0",
  "description": "Yao Autonomous Agent Engine"
}
```

### Recommended Minimum `app.yao`
```json
{
  "name": "Yao Application",
  "short": "Yao",
  "description": "Yao Autonomous Agent Engine",
  "version": "1.0.0",
  "adminRoot": "admin",
  "menu": {
    "process": "flows.menu",
    "args": []
  },
  "optional": {
    "remoteCache": false,
    "menu": {
      "layout": "2-columns",
      "showName": true
    }
  }
}
```

### Key Missing Fields

| Field | Purpose | Required |
|-------|---------|----------|
| `short` | Short name for app | Recommended |
| `adminRoot` | Admin panel path | **Required** for admin |
| `menu` | Menu configuration | **Required** for admin |
| `public` | HTTP server rewrite rules | For web pages |
| `optional` | Optional features | Recommended |

---

## `tsconfig.json` Configuration

### Missing File

The `tsconfig.json` file is **required** for TypeScript script development. It should be created:

```json
{
  "compilerOptions": {
    "target": "es6",
    "paths": {
      "@yao/*": ["./.types/*"],
      "@scripts/*": ["./scripts/*"]
    },
    "lib": ["es2017", "dom"]
  }
}
```

---

## Issues Found

### Critical Issues

1. **Wrong Directory Name**: `agent/` should be `agents/` (per AI Integration docs)
2. **Non-standard Directory**: `openapi/` is not standard - APIs should be in `apis/`
3. **Missing `app.yao` Fields**: Missing `adminRoot` and `menu` configuration
4. **Missing `tsconfig.json`**: Required for TypeScript development
5. **Missing Critical Environment Variables**: `YAO_ENV`, `YAO_DB_DRIVER`, `YAO_DB_PRIMARY`, `YAO_JWT_SECRET`

### Medium Priority Issues

1. **Missing `models/` directory**: Required for data models
2. **Missing `apis/` directory**: Required for REST APIs
3. **Missing `logs/` directory**: Required for application logging
4. **Missing `neo/` directory**: Required for chatbot configuration
5. **Missing `data/templates/default/`**: Required for web pages

### Low Priority Issues

1. **Missing `forms/` directory**: For admin panel forms
2. **Missing `tables/` directory**: For admin panel tables
3. **Missing `flows/` directory**: For flow processes
4. **Missing `schedules/` directory**: For scheduled tasks
5. **Missing `public/` directory**: For static files

---

## Recommended Changes to Install Script

### 1. Fix Directory Structure

```bash
msg_info "Creating Application Directories"
mkdir -p /opt/yao/db
mkdir -p /opt/yao/data/templates/default
mkdir -p /opt/yao/public
mkdir -p /opt/yao/logs
mkdir -p /opt/yao/models
mkdir -p /opt/yao/apis
mkdir -p /opt/yao/scripts
mkdir -p /opt/yao/forms
mkdir -p /opt/yao/tables
mkdir -p /opt/yao/flows
mkdir -p /opt/yao/schedules
mkdir -p /opt/yao/connectors
mkdir -p /opt/yao/suis
mkdir -p /opt/yao/neo
msg_ok "Created Application Directories"
```

### 2. Update `app.yao`

```bash
msg_info "Creating Application Configuration"
cat <<EOF >/opt/yao/app.yao
{
  "name": "Yao Application",
  "short": "Yao",
  "description": "Yao Autonomous Agent Engine",
  "version": "1.0.0",
  "adminRoot": "admin",
  "menu": {
    "process": "flows.menu",
    "args": []
  },
  "optional": {
    "remoteCache": false,
    "menu": {
      "layout": "2-columns",
      "showName": true
    }
  }
}
EOF
msg_ok "Created Application Configuration"
```

### 3. Update `.env` File

```bash
msg_info "Creating Environment File"
cat <<EOF >/opt/yao/.env
# Application Settings
YAO_ENV=production
YAO_HOST=0.0.0.0
YAO_PORT=5099
YAO_LANG=en-us

# Database Settings
YAO_DB_DRIVER=sqlite3
YAO_DB_PRIMARY=./db/yao.db

# Logging Settings
YAO_LOG=./logs/application.log
YAO_LOG_MODE=TEXT

# Security Settings
YAO_JWT_SECRET=$(openssl rand -hex 32)

# Session Settings
YAO_SESSION_STORE=file
YAO_SESSION_FILE=./db/.session
EOF
msg_ok "Created Environment File"
```

### 4. Create `tsconfig.json`

```bash
msg_info "Creating TypeScript Configuration"
cat <<EOF >/opt/yao/tsconfig.json
{
  "compilerOptions": {
    "target": "es6",
    "paths": {
      "@yao/*": ["./.types/*"],
      "@scripts/*": ["./scripts/*"]
    },
    "lib": ["es2017", "dom"]
  }
}
EOF
msg_ok "Created TypeScript Configuration"
```

### 5. Create Default Menu Flow

```bash
msg_info "Creating Default Menu Flow"
mkdir -p /opt/yao/flows
cat <<EOF >/opt/yao/flows/menu.flow.yao
{
  "name": "Menu",
  "nodes": [],
  "output": {
    "items": [
      {
        "name": "Dashboard",
        "path": "/x/Table/dashboard",
        "icon": { "name": "material-dashboard", "size": 22 }
      }
    ],
    "setting": [
      {
        "icon": { "name": "material-settings", "size": 22 },
        "name": "Settings",
        "path": "/x/Table/setting"
      }
    ]
  }
}
EOF
msg_ok "Created Default Menu Flow"
```

### 6. Create Default Neo Configuration

```bash
msg_info "Creating Neo Chatbot Configuration"
mkdir -p /opt/yao/neo
cat <<EOF >/opt/yao/neo/neo.yml
conversation:
  connector: default
  table: yao_neo_conversation
  max_size: 10
  ttl: 3600

connector: "default"

option:
  temperature: 0.6

allows:
  - "http://127.0.0.1:5099"
  - "http://localhost:5099"
EOF
msg_ok "Created Neo Chatbot Configuration"
```

### 7. Create Default SUI Widget

```bash
msg_info "Creating Default SUI Widget"
mkdir -p /opt/yao/suis
cat <<EOF >/opt/yao/suis/web.sui.yao
{
  "name": "Web",
  "description": "Default web template engine",
  "root": "/data/templates",
  "templates": ["default"]
}
EOF
msg_ok "Created Default SUI Widget"
```

### 8. Create Default Document Template

```bash
msg_info "Creating Default Document Template"
mkdir -p /opt/yao/data/templates/default
cat <<EOF >/opt/yao/data/templates/default/__document.html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Yao Application</title>
</head>
<body>
  {% __content__ %}
</body>
</html>
EOF
msg_ok "Created Default Document Template"
```

---

## Summary

### Current Status: ⚠️ Partially Compliant

The current install script creates a basic Yao installation but is missing several critical components required for a fully functional minimum installation:

| Category | Status | Missing Items |
|----------|--------|---------------|
| Directory Structure | ⚠️ Partial | `models/`, `apis/`, `logs/`, `neo/` |
| Environment Variables | ⚠️ Partial | `YAO_ENV`, `YAO_DB_*`, `YAO_JWT_SECRET` |
| app.yao Configuration | ⚠️ Partial | `adminRoot`, `menu` |
| tsconfig.json | ❌ Missing | Entire file |
| Default Configurations | ❌ Missing | Menu flow, Neo config, SUI widget |

### Recommended Actions

1. **HIGH PRIORITY**: Add missing environment variables (`YAO_ENV`, `YAO_DB_DRIVER`, `YAO_DB_PRIMARY`, `YAO_JWT_SECRET`)
2. **HIGH PRIORITY**: Update `app.yao` with `adminRoot` and `menu` configuration
3. **HIGH PRIORITY**: Create `tsconfig.json` for TypeScript support
4. **HIGH PRIORITY**: Create `logs/` directory
5. **MEDIUM PRIORITY**: Create `models/` and `apis/` directories
6. **MEDIUM PRIORITY**: Create default menu flow (`flows/menu.flow.yao`)
7. **MEDIUM PRIORITY**: Create default Neo configuration (`neo/neo.yml`)
8. **LOW PRIORITY**: Create default SUI widget and document template

---

## References

- [Yao Installation Documentation](https://yaoapps.com/docs/documentation/en-us/getting-started/installation)
- [Yao App Configuration](https://yaoapps.com/docs/documentation/en-us/building-your-application/app-configuration)
- [Yao Data Model](https://yaoapps.com/docs/documentation/en-us/building-your-application/data-model)
- [Yao REST API](https://yaoapps.com/docs/documentation/en-us/building-your-application/rest-api)
- [Yao Admin Panel](https://yaoapps.com/docs/documentation/en-us/building-your-application/admin-panel)
- [Yao AI Integration](https://yaoapps.com/docs/documentation/en-us/building-your-application/ai-integration)
- [Yao Web Page](https://yaoapps.com/docs/documentation/en-us/building-your-application/web-page)
- [Yao CLI](https://yaoapps.com/docs/documentation/en-us/building-your-application/cli)
- [Yao Debug Guide](https://yaoapps.com/docs/documentation/en-us/building-your-application/debug-guide)
- [Yao Command](https://yaoapps.com/docs/documentation/en-us/building-your-application/yao-command)