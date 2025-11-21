# Production Readiness Assessment & Roadmap

**Date**: 2025-11-20
**Applications**: Workout Planner, Meal Planner, Home Manager, Vehicle Manager

## Executive Summary

This document outlines the current production readiness state across all 4 applications and provides a prioritized roadmap for achieving production-grade deployment.

### Current State Overview

| Application | Status | Production Ready | Critical Gaps |
|-------------|--------|------------------|---------------|
| **Workout Planner** | 🟡 Advanced | 60% | Testing, Load Balancer, Alarms |
| **Meal Planner** | 🔴 Prototype | 20% | Database, Auth, Monitoring |
| **Home Manager** | 🔴 Prototype | 20% | Database, Auth, Monitoring |
| **Vehicle Manager** | 🔴 Prototype | 20% | Database, Auth, Monitoring |

---

## Critical Production Blockers

### 🔴 SEVERITY 1: Data & Security (Deploy Blockers)

#### 1. Database Persistence (Simple Apps)

**Issue**: All data stored in memory, lost on every restart/deployment

**Current State**:
```python
# Data lost on restart
_MEAL_PLANS = {
    "user-123": {"monday": [...]}  # Gone after deployment
}
```

**Impact**:
- Complete data loss on deployment
- No user data persistence
- Cannot scale horizontally
- No data recovery possible

**Solution**:
```python
# Add PostgreSQL with proper ORM
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

DATABASE_URL = os.getenv("DATABASE_URL")
engine = create_engine(DATABASE_URL, pool_size=10)
SessionLocal = sessionmaker(bind=engine)
```

**Action Items**:
- [ ] Provision RDS PostgreSQL instance (db.t3.micro)
- [ ] Create database schemas for each app
- [ ] Migrate hardcoded data to database tables
- [ ] Add connection pooling (SQLAlchemy)
- [ ] Update Docker to include database connection
- [ ] Configure environment variables in ECS

**Effort**: 2-3 days per app
**Priority**: 🔴 CRITICAL

---

#### 2. Authentication & Authorization (Simple Apps)

**Issue**: No authentication - anyone can access/modify any user's data

**Current State**:
```python
@app.get("/meals/weekly-plan/{user_id}")
async def get_weekly_plan(user_id: str):
    # No validation of user_id!
    # Anyone can request any user's data
    return _MEAL_PLANS.get(user_id, {})
```

**Impact**:
- Zero security
- Privacy violations (GDPR/CCPA)
- Data manipulation risk
- No audit trail

**Solution** (Copy from Workout Planner):
```python
# 1. Add JWT authentication
from fastapi import Depends, HTTPException
from fastapi.security import HTTPBearer

security = HTTPBearer()

async def get_current_user(token: str = Depends(security)):
    payload = verify_jwt_token(token.credentials)
    return payload["sub"]

# 2. Protect endpoints
@app.get("/meals/weekly-plan")
async def get_weekly_plan(user_id: str = Depends(get_current_user)):
    return await get_user_meals(user_id)

# 3. Add user registration/login
@app.post("/auth/register")
async def register(email: str, password: str):
    hashed = bcrypt.hashpw(password.encode(), bcrypt.gensalt())
    user = create_user(email, hashed)
    token = create_jwt_token(user.id)
    return {"access_token": token}
```

**Action Items**:
- [ ] Add `python-jose[cryptography]` and `passlib[bcrypt]` dependencies
- [ ] Create users table in database
- [ ] Implement JWT token generation/validation
- [ ] Add `/auth/register` and `/auth/login` endpoints
- [ ] Protect all user-specific endpoints
- [ ] Update frontend to include auth headers
- [ ] Add token refresh mechanism

**Effort**: 1-2 days per app
**Priority**: 🔴 CRITICAL

---

#### 3. CORS Security (All Simple Apps)

**Issue**: CORS wide open to all origins

**Current State**:
```python
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # DANGEROUS!
    allow_credentials=True,  # With wildcard = CRITICAL VULNERABILITY
    allow_methods=["*"],
    allow_headers=["*"],
)
```

**Impact**:
- CSRF attacks
- Unauthorized cross-origin requests
- Session hijacking risk

**Solution**:
```python
# Environment-based CORS
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    environment: str = "development"
    cors_origins: list[str] = [
        "https://yourdomain.com",
        "https://www.yourdomain.com"
    ]

settings = Settings()

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins if settings.environment == "production" else ["*"],
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE"],
    allow_headers=["Authorization", "Content-Type"],
)
```

**Action Items**:
- [ ] Create settings.py with environment configuration
- [ ] Configure production CORS origins
- [ ] Update ECS task definition with environment variables
- [ ] Test CORS with production domains

**Effort**: 1 hour per app
**Priority**: 🔴 CRITICAL

---

#### 4. Structured Logging (Simple Apps)

**Issue**: No structured logging, cannot debug production issues

**Current State**:
- Default uvicorn logs only
- No correlation IDs
- No context tracking
- No error aggregation

**Impact**:
- Cannot troubleshoot production issues
- No request tracing
- Cannot identify patterns
- Blind to errors

**Solution** (Copy from Workout Planner):
```python
import logging
import json
from contextvars import ContextVar

correlation_id_var = ContextVar("correlation_id", default="")

class JSONFormatter(logging.Formatter):
    def format(self, record):
        log_obj = {
            "timestamp": self.formatTime(record),
            "level": record.levelname.lower(),
            "logger": record.name,
            "message": record.getMessage(),
            "correlation_id": correlation_id_var.get(),
        }
        if record.exc_info:
            log_obj["exception"] = self.formatException(record.exc_info)
        return json.dumps(log_obj)

# Middleware to add correlation ID
@app.middleware("http")
async def add_correlation_id(request: Request, call_next):
    correlation_id = request.headers.get("X-Correlation-ID", str(uuid.uuid4()))
    correlation_id_var.set(correlation_id)

    logger.info("request_started", extra={
        "method": request.method,
        "path": request.url.path,
    })

    try:
        response = await call_next(request)
        response.headers["X-Correlation-ID"] = correlation_id
        return response
    except Exception as e:
        logger.error("request_error", exc_info=True)
        raise
```

**Action Items**:
- [ ] Create logging_config.py
- [ ] Add JSON formatter
- [ ] Add correlation ID middleware
- [ ] Update all print() statements to logger calls
- [ ] Configure log levels per environment

**Effort**: 1 day per app
**Priority**: 🔴 CRITICAL

---

#### 5. Monitoring & Metrics (Simple Apps)

**Issue**: No application metrics, cannot detect issues

**Current State**:
- No metrics collection
- No /metrics endpoint
- No alerting
- No performance tracking

**Impact**:
- Cannot detect outages
- No performance visibility
- Manual capacity planning
- No SLA tracking

**Solution**:
```python
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST

# Define metrics
REQUEST_COUNT = Counter(
    "app_request_total",
    "Total requests",
    ["method", "path", "status_code"]
)

REQUEST_LATENCY = Histogram(
    "app_request_latency_seconds",
    "Request latency",
    ["method", "path"]
)

ERROR_COUNT = Counter(
    "app_error_total",
    "Total errors",
    ["error_type"]
)

# Middleware to collect metrics
@app.middleware("http")
async def metrics_middleware(request: Request, call_next):
    start_time = time.time()
    response = await call_next(request)
    duration = time.time() - start_time

    REQUEST_COUNT.labels(
        method=request.method,
        path=request.url.path,
        status_code=response.status_code
    ).inc()

    REQUEST_LATENCY.labels(
        method=request.method,
        path=request.url.path
    ).observe(duration)

    return response

# Expose metrics endpoint
@app.get("/metrics")
async def metrics():
    return Response(content=generate_latest(), media_type=CONTENT_TYPE_LATEST)
```

**Action Items**:
- [ ] Add `prometheus-client` dependency
- [ ] Create metrics.py module
- [ ] Add metrics middleware
- [ ] Expose /metrics endpoint
- [ ] Configure Prometheus scraping (or CloudWatch Container Insights)

**Effort**: 1 day per app
**Priority**: 🔴 CRITICAL

---

### 🔴 SEVERITY 1: Infrastructure (All Apps)

#### 6. Application Load Balancer

**Issue**: No load balancer, single point of failure

**Current State**:
- Direct connection to ECS tasks
- No SSL/TLS termination
- No health-based routing
- No high availability

**Impact**:
- Single point of failure
- No SSL (insecure connections)
- Manual failover
- Cannot scale horizontally

**Solution**:
```hcl
# Terraform configuration
resource "aws_lb" "app" {
  name               = "app-cluster-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnets

  enable_deletion_protection = true
  enable_http2              = true
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.app.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01"
  certificate_arn   = aws_acm_certificate.cert.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

resource "aws_lb_target_group" "meal_planner" {
  name     = "meal-planner-tg"
  port     = 8010
  protocol = "HTTP"
  vpc_id   = var.vpc_id
  target_type = "ip"

  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
  }
}
```

**Action Items**:
- [ ] Create Application Load Balancer
- [ ] Configure target groups for each app (ports 8000, 8010, 8020, 8030)
- [ ] Set up health check paths
- [ ] Configure listener rules for path-based routing
- [ ] Request SSL certificate via ACM
- [ ] Update DNS to point to ALB
- [ ] Configure security groups (ALB → ECS)
- [ ] Update ECS services to register with target groups

**Effort**: 2 days
**Priority**: 🔴 CRITICAL

---

#### 7. CloudWatch Alarms

**Issue**: No alerting, silent failures

**Current State**:
- No alarms configured
- Outages not detected
- No automated notifications
- Reactive troubleshooting only

**Impact**:
- Long mean time to detection (MTTD)
- Customer-reported issues
- Revenue loss during outages
- Poor user experience

**Solution**:
```hcl
# Critical alarms for each service
resource "aws_cloudwatch_metric_alarm" "high_error_rate" {
  alarm_name          = "meal-planner-high-error-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = "60"
  statistic           = "Average"
  threshold           = "5"
  alarm_description   = "Error rate above 5%"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    TargetGroup  = aws_lb_target_group.meal_planner.arn_suffix
    LoadBalancer = aws_lb.app.arn_suffix
  }
}

resource "aws_cloudwatch_metric_alarm" "health_check_failed" {
  alarm_name          = "meal-planner-unhealthy"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "HealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = "60"
  statistic           = "Average"
  threshold           = "1"
  alarm_description   = "No healthy instances"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "high_latency" {
  alarm_name          = "meal-planner-high-latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = "300"
  statistic           = "Average"
  threshold           = "1.0"
  alarm_description   = "Response time above 1 second"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}
```

**Action Items**:
- [ ] Create SNS topic for alerts
- [ ] Configure alarm for each service:
  - High error rate (>5%)
  - No healthy instances
  - High latency (>1s)
  - High CPU (>80%)
  - High memory (>80%)
- [ ] Subscribe email/Slack to SNS topic
- [ ] Test alarm triggering
- [ ] Create runbooks for each alarm

**Effort**: 1 day
**Priority**: 🔴 CRITICAL

---

#### 8. Backup & Disaster Recovery

**Issue**: No backup strategy, data loss risk

**Current State**:
- No automated backups
- No point-in-time recovery
- No disaster recovery plan
- RTO/RPO undefined

**Impact**:
- Permanent data loss risk
- Cannot recover from failures
- Compliance violations
- Business continuity risk

**Solution**:
```hcl
# RDS automated backups
resource "aws_db_instance" "main" {
  identifier = "app-postgres"

  # Backup configuration
  backup_retention_period = 7    # 7 days of backups
  backup_window          = "03:00-04:00"
  maintenance_window     = "Mon:04:00-Mon:05:00"

  # Point-in-time recovery
  enabled_cloudwatch_logs_exports = ["postgresql"]

  # Multi-AZ for HA
  multi_az = true

  # Deletion protection
  deletion_protection = true
  skip_final_snapshot = false
  final_snapshot_identifier = "app-postgres-final-snapshot"
}

# Manual snapshot automation
resource "aws_backup_plan" "db_backup" {
  name = "database-backup-plan"

  rule {
    rule_name         = "daily_backup"
    target_vault_name = aws_backup_vault.main.name
    schedule          = "cron(0 2 * * ? *)"  # 2 AM daily

    lifecycle {
      delete_after = 30  # Keep for 30 days
    }
  }
}
```

**Action Items**:
- [ ] Enable automated RDS backups (7-day retention)
- [ ] Configure backup window (off-peak hours)
- [ ] Test restore procedure
- [ ] Document recovery steps
- [ ] Define RTO (Recovery Time Objective): < 1 hour
- [ ] Define RPO (Recovery Point Objective): < 15 minutes
- [ ] Create disaster recovery runbook
- [ ] Schedule quarterly DR drills

**Effort**: 1 day
**Priority**: 🔴 CRITICAL

---

## High Priority Improvements

### 🟡 SEVERITY 2: Scalability & Performance

#### 9. Auto-Scaling

**Issue**: Manual capacity management

**Solution**:
```hcl
resource "aws_appautoscaling_target" "ecs_target" {
  max_capacity       = 10
  min_capacity       = 2
  resource_id        = "service/${var.cluster_name}/${var.service_name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "ecs_policy_cpu" {
  name               = "cpu-autoscaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_target.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value = 70.0
  }
}
```

**Action Items**:
- [ ] Configure ECS auto-scaling (2-10 tasks)
- [ ] Set CPU target (70%)
- [ ] Set memory target (80%)
- [ ] Test scaling behavior
- [ ] Monitor scaling events

**Effort**: 1 day
**Priority**: 🟡 HIGH

---

#### 10. Rate Limiting

**Issue**: API abuse risk

**Solution**:
```python
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded

limiter = Limiter(key_func=get_remote_address)
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

@app.get("/meals/weekly-plan")
@limiter.limit("100/minute")
async def get_weekly_plan(request: Request, user_id: str = Depends(get_current_user)):
    return await get_meals(user_id)
```

**Action Items**:
- [ ] Add `slowapi` dependency
- [ ] Configure rate limits per endpoint
- [ ] Add rate limit headers to responses
- [ ] Document rate limits in API docs
- [ ] Monitor rate limit hits

**Effort**: 2 days
**Priority**: 🟡 HIGH

---

#### 11. Connection Pooling

**Issue**: Database connection overhead

**Solution**:
```python
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import QueuePool

DATABASE_URL = os.getenv("DATABASE_URL")

engine = create_engine(
    DATABASE_URL,
    poolclass=QueuePool,
    pool_size=10,
    max_overflow=20,
    pool_pre_ping=True,  # Verify connections
    pool_recycle=3600,   # Recycle after 1 hour
)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
```

**Action Items**:
- [ ] Migrate from raw psycopg2 to SQLAlchemy
- [ ] Configure connection pool (10 connections)
- [ ] Add pool monitoring
- [ ] Test under load

**Effort**: 1 day
**Priority**: 🟡 HIGH

---

#### 12. Testing Coverage

**Issue**: No tests for simple apps

**Solution**:
```python
import pytest
from fastapi.testclient import TestClient
from main import app

@pytest.fixture
def client():
    return TestClient(app)

@pytest.fixture
def auth_headers():
    # Login and get token
    client = TestClient(app)
    response = client.post("/auth/login", json={
        "email": "test@example.com",
        "password": "Password123!"
    })
    token = response.json()["access_token"]
    return {"Authorization": f"Bearer {token}"}

def test_get_weekly_plan_authenticated(client, auth_headers):
    response = client.get("/meals/weekly-plan", headers=auth_headers)
    assert response.status_code == 200
    assert "monday" in response.json()

def test_get_weekly_plan_unauthenticated(client):
    response = client.get("/meals/weekly-plan")
    assert response.status_code == 401
```

**Action Items**:
- [ ] Add pytest dependencies
- [ ] Create tests/ directory
- [ ] Write tests for all endpoints (80% coverage goal)
- [ ] Add tests to CI pipeline
- [ ] Configure code coverage reporting

**Effort**: 3-5 days per app
**Priority**: 🟡 HIGH

---

## Medium Priority Improvements

### 🟢 SEVERITY 3: Operational Excellence

#### 13. Database Migration Tool

**Current**: Manual schema changes
**Solution**: Alembic for versioned migrations

```bash
pip install alembic
alembic init alembic
alembic revision --autogenerate -m "initial schema"
alembic upgrade head
```

**Effort**: 2 days
**Priority**: 🟢 MEDIUM

---

#### 14. APM Integration

**Current**: Limited observability
**Solution**: AWS X-Ray or DataDog

**Effort**: 2 days
**Priority**: 🟢 MEDIUM

---

#### 15. Multi-AZ Deployment

**Current**: Single AZ
**Solution**: Multi-AZ RDS + ECS across 2+ AZs

**Effort**: 1 day
**Priority**: 🟢 MEDIUM

---

#### 16. CDN for Static Assets

**Current**: Direct GitHub Pages
**Solution**: CloudFront distribution

**Effort**: 1 day
**Priority**: 🟢 MEDIUM

---

## Implementation Roadmap

### Phase 1: Critical Security & Data (2 weeks)

**Week 1**:
- [ ] Day 1-3: Add PostgreSQL to all 3 simple apps
- [ ] Day 4-5: Implement authentication (Meal Planner)

**Week 2**:
- [ ] Day 6-7: Implement authentication (Home + Vehicle Manager)
- [ ] Day 8-10: Add structured logging + monitoring to all apps

### Phase 2: Infrastructure & Reliability (2 weeks)

**Week 3**:
- [ ] Day 11-12: Configure ALB with SSL/TLS
- [ ] Day 13: Set up CloudWatch alarms
- [ ] Day 14: Implement backup strategy

**Week 4**:
- [ ] Day 15: Configure auto-scaling
- [ ] Day 16-17: Add rate limiting
- [ ] Day 18-20: Connection pooling + performance testing

### Phase 3: Testing & Observability (2 weeks)

**Week 5**:
- [ ] Day 21-25: Write tests for all apps (80% coverage)

**Week 6**:
- [ ] Day 26-28: APM integration + distributed tracing
- [ ] Day 29-30: Load testing + optimization

---

## Cost Estimate

### AWS Monthly Costs (Production)

| Service | Configuration | Cost |
|---------|---------------|------|
| RDS PostgreSQL | db.t3.micro (single AZ) | $15 |
| ECS Fargate | 4 services × 2 tasks × 0.25 vCPU | $40 |
| Application Load Balancer | Standard | $16 |
| CloudWatch | Logs + Metrics + Alarms | $10 |
| ACM Certificate | Free | $0 |
| **Total** | | **$81/month** |

### High Availability Configuration

| Service | Configuration | Cost |
|---------|---------------|------|
| RDS PostgreSQL | db.t3.small (Multi-AZ) | $60 |
| ECS Fargate | 4 services × 3 tasks × 0.5 vCPU | $120 |
| Application Load Balancer | Standard | $16 |
| CloudWatch | Enhanced monitoring | $20 |
| **Total** | | **$216/month** |

---

## Success Metrics

### Service Level Objectives (SLOs)

- **Availability**: 99.5% uptime (3.6 hours downtime/month)
- **Latency**: P95 < 500ms, P99 < 1s
- **Error Rate**: < 0.1%
- **Recovery Time**: < 1 hour (RTO)
- **Data Loss**: < 15 minutes (RPO)

### Key Performance Indicators (KPIs)

- **MTTD** (Mean Time To Detection): < 5 minutes
- **MTTR** (Mean Time To Recovery): < 30 minutes
- **Deployment Frequency**: Daily
- **Change Failure Rate**: < 5%
- **Test Coverage**: > 80%

---

## Conclusion

### Current State:
- **Workout Planner**: 60% production ready (needs load balancer, alarms, testing)
- **Simple Apps**: 20% production ready (needs database, auth, monitoring)

### After Phase 1 (2 weeks):
- All apps: 70% production ready
- Critical security & data gaps closed
- Basic monitoring in place

### After Phase 2 (4 weeks):
- All apps: 85% production ready
- Infrastructure hardened
- High availability configured

### After Phase 3 (6 weeks):
- All apps: 95% production ready
- Comprehensive testing
- Full observability

**Total Effort**: 30-40 developer days (6-8 weeks at 1 developer)
**Total Cost**: $81-216/month (depending on HA requirements)

---

**Next Steps**:
1. Review and prioritize recommendations
2. Assign resources to Phase 1 tasks
3. Set up project tracking for roadmap items
4. Begin with highest priority: Database + Authentication
