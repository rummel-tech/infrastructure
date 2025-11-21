# Workout Planner - Phase 1 Implementation Plan

**Priority**: HIGH
**Timeline**: 2 weeks
**Status**: In Progress

## Overview

Workout Planner is the most mature application (60% production ready). Phase 1 focuses on infrastructure hardening to achieve 85% production readiness.

## Phase 1 Objectives

1. ✅ Infrastructure setup (ALB, SSL, networking)
2. ✅ Monitoring & alerting (CloudWatch alarms)
3. ✅ Backup & disaster recovery
4. ✅ Rate limiting & security
5. ✅ Auto-scaling
6. ✅ Update deployment workflows

## Current State

### What's Working
- ✅ PostgreSQL database with migrations
- ✅ JWT authentication system
- ✅ Structured JSON logging
- ✅ Prometheus metrics endpoint
- ✅ Error handling & correlation IDs
- ✅ Docker containerization
- ✅ ECR image repository
- ✅ Basic ECS task definition
- ✅ Health check endpoints

### What's Missing
- ❌ Application Load Balancer
- ❌ SSL/TLS termination
- ❌ CloudWatch alarms
- ❌ Automated backups
- ❌ Rate limiting
- ❌ Auto-scaling
- ❌ Multi-AZ deployment
- ❌ Production database (using SQLite in dev)

---

## Task Breakdown

### Task 1: Provision RDS PostgreSQL Database

**Priority**: CRITICAL
**Effort**: 3 hours
**Dependencies**: None

**Objective**: Replace SQLite with production PostgreSQL database

**Steps**:

1. Create RDS PostgreSQL instance
   - Instance class: db.t3.micro (1 vCPU, 1 GB RAM)
   - Storage: 20 GB SSD (gp3)
   - Multi-AZ: Yes (for HA)
   - Backup retention: 7 days
   - Maintenance window: Sunday 3-4 AM ET

2. Configure security group
   - Allow inbound PostgreSQL (5432) from ECS security group only
   - No public access

3. Create database and user
   ```sql
   CREATE DATABASE workout_planner;
   CREATE USER workout_app WITH PASSWORD 'SecurePassword123!';
   GRANT ALL PRIVILEGES ON DATABASE workout_planner TO workout_app;
   ```

4. Store credentials in AWS Secrets Manager
   ```json
   {
     "username": "workout_app",
     "password": "SecurePassword123!",
     "host": "workout-planner.xxxxx.us-east-1.rds.amazonaws.com",
     "port": 5432,
     "database": "workout_planner"
   }
   ```

5. Update ECS task definition to inject DATABASE_URL from Secrets Manager

**Configuration File**: `infrastructure/terraform/rds.tf`

**Validation**:
- [ ] Can connect to RDS from ECS task
- [ ] Database schema created successfully
- [ ] Application starts without errors
- [ ] Health check passes

---

### Task 2: Application Load Balancer Setup

**Priority**: CRITICAL
**Effort**: 4 hours
**Dependencies**: None

**Objective**: Set up ALB with SSL for high availability and secure connections

**Architecture**:
```
Internet → ALB (HTTPS:443) → Target Group → ECS Tasks (HTTP:8000)
```

**Steps**:

1. Create ALB
   - Name: `workout-planner-alb`
   - Scheme: Internet-facing
   - IP address type: IPv4
   - Subnets: 2+ public subnets in different AZs
   - Security group: Allow 443 (HTTPS), 80 (HTTP redirect)

2. Request SSL certificate via ACM
   - Domain: `api.workout-planner.yourdomain.com`
   - Validation: DNS (add CNAME record)
   - Wait for validation (5-30 minutes)

3. Create target group
   - Name: `workout-planner-tg`
   - Target type: IP
   - Protocol: HTTP
   - Port: 8000
   - Health check path: `/health`
   - Healthy threshold: 2
   - Unhealthy threshold: 3
   - Timeout: 5 seconds
   - Interval: 30 seconds
   - Success codes: 200

4. Configure listeners
   - **HTTPS:443** → Forward to target group
   - **HTTP:80** → Redirect to HTTPS

5. Update ECS service to register with target group

6. Update DNS to point to ALB
   - Create CNAME: `api.workout-planner` → `workout-planner-alb-xxx.us-east-1.elb.amazonaws.com`

**Configuration File**: `infrastructure/terraform/alb.tf`

**Validation**:
- [ ] HTTPS connection successful
- [ ] HTTP redirects to HTTPS
- [ ] Health check passing
- [ ] API accessible via domain
- [ ] SSL certificate valid

---

### Task 3: CloudWatch Alarms

**Priority**: CRITICAL
**Effort**: 2 hours
**Dependencies**: Task 2 (ALB)

**Objective**: Set up monitoring and alerting for production issues

**Alarms to Create**:

1. **High Error Rate** (5xx responses)
   - Metric: `HTTPCode_Target_5XX_Count`
   - Threshold: > 5 errors in 2 minutes
   - Action: Send SNS notification

2. **No Healthy Targets**
   - Metric: `HealthyHostCount`
   - Threshold: < 1
   - Action: Send SNS notification (CRITICAL)

3. **High Latency**
   - Metric: `TargetResponseTime`
   - Threshold: > 1 second (P95)
   - Action: Send SNS notification

4. **High CPU Utilization**
   - Metric: `CPUUtilization`
   - Threshold: > 80%
   - Action: Send SNS notification + trigger auto-scaling

5. **High Memory Utilization**
   - Metric: `MemoryUtilization`
   - Threshold: > 80%
   - Action: Send SNS notification + trigger auto-scaling

6. **Database Connection Errors**
   - Metric: Custom metric from application logs
   - Threshold: > 5 in 5 minutes
   - Action: Send SNS notification (CRITICAL)

**SNS Topic Setup**:
```bash
# Create SNS topic
aws sns create-topic --name workout-planner-alerts

# Subscribe email
aws sns subscribe \
  --topic-arn arn:aws:sns:us-east-1:901746942632:workout-planner-alerts \
  --protocol email \
  --notification-endpoint alerts@yourdomain.com
```

**Configuration File**: `infrastructure/terraform/cloudwatch.tf`

**Validation**:
- [ ] All alarms created
- [ ] SNS topic configured
- [ ] Email subscription confirmed
- [ ] Test alarm triggers successfully
- [ ] Alerts received via email

---

### Task 4: Backup & Disaster Recovery

**Priority**: CRITICAL
**Effort**: 1 hour
**Dependencies**: Task 1 (RDS)

**Objective**: Protect against data loss and enable disaster recovery

**Backup Strategy**:

1. **Automated Backups** (RDS feature)
   - Enabled: Yes
   - Retention: 7 days
   - Backup window: 3:00-4:00 AM ET
   - Point-in-time recovery: Enabled

2. **Manual Snapshots** (AWS Backup)
   - Frequency: Daily at 2:00 AM ET
   - Retention: 30 days
   - Copy to different region: Optional (for DR)

3. **Application Data Export** (Optional)
   - Weekly export to S3
   - Format: SQL dump
   - Retention: 90 days

**Recovery Testing**:
- RTO (Recovery Time Objective): < 1 hour
- RPO (Recovery Point Objective): < 15 minutes

**Configuration File**: `infrastructure/terraform/backup.tf`

**Validation**:
- [ ] Automated backups enabled
- [ ] Manual snapshot created successfully
- [ ] Restore test successful
- [ ] Recovery time < RTO
- [ ] Data integrity verified

---

### Task 5: Rate Limiting

**Priority**: HIGH
**Effort**: 2 hours
**Dependencies**: None

**Objective**: Prevent API abuse and DoS attacks

**Implementation**:

1. Add `slowapi` dependency
   ```bash
   cd /home/shawn/APP_DEV/workout-planner/applications/backend/python_fastapi_server
   echo "slowapi==0.1.9" >> requirements.txt
   pip install slowapi
   ```

2. Configure rate limiter in `main.py`:
   ```python
   from slowapi import Limiter, _rate_limit_exceeded_handler
   from slowapi.util import get_remote_address
   from slowapi.errors import RateLimitExceeded

   limiter = Limiter(key_func=get_remote_address, default_limits=["100/minute"])
   app.state.limiter = limiter
   app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

   # Apply to specific endpoints
   @app.post("/auth/register")
   @limiter.limit("5/minute")  # Stricter for registration
   async def register(request: Request, ...):
       pass

   @app.post("/auth/login")
   @limiter.limit("10/minute")  # Stricter for login
   async def login(request: Request, ...):
       pass

   # General API endpoints
   @app.get("/workouts/{user_id}")
   @limiter.limit("100/minute")
   async def get_workouts(request: Request, ...):
       pass
   ```

3. Add rate limit headers to responses:
   - `X-RateLimit-Limit`: Maximum requests
   - `X-RateLimit-Remaining`: Remaining requests
   - `X-RateLimit-Reset`: Time when limit resets

4. Update API documentation with rate limits

**Configuration File**: Update `main.py`

**Validation**:
- [ ] Rate limiting works for all endpoints
- [ ] Headers present in responses
- [ ] 429 error returned when exceeded
- [ ] Limits documented in API docs
- [ ] Monitor rate limit hits in CloudWatch

---

### Task 6: Auto-Scaling Configuration

**Priority**: HIGH
**Effort**: 2 hours
**Dependencies**: Task 2 (ALB), Task 3 (CloudWatch)

**Objective**: Automatically scale capacity based on demand

**Configuration**:

1. **Target Tracking Scaling** (CPU-based)
   - Min capacity: 2 tasks
   - Max capacity: 10 tasks
   - Target CPU: 70%
   - Scale-out cooldown: 60 seconds
   - Scale-in cooldown: 300 seconds

2. **Target Tracking Scaling** (Memory-based)
   - Target Memory: 80%

3. **Target Tracking Scaling** (Request-based)
   - Target: 1000 requests per target per minute

**Scaling Behavior**:
```
Load Level   | Tasks | CPU Usage
-------------|-------|----------
Low          | 2     | 30-40%
Medium       | 4     | 60-70%
High         | 8     | 70-75%
Peak         | 10    | 70-80%
```

**Configuration File**: `infrastructure/terraform/autoscaling.tf`

**Validation**:
- [ ] Auto-scaling policy created
- [ ] Minimum tasks running (2)
- [ ] Scale-out test: Load test triggers scaling
- [ ] Scale-in test: Tasks reduced after load decreases
- [ ] CloudWatch metrics showing scaling events

---

### Task 7: Update Deployment Workflow

**Priority**: MEDIUM
**Effort**: 1 hour
**Dependencies**: Task 2 (ALB)

**Objective**: Automate ECS service updates after image push

**Current Workflow** (Manual):
1. Build Docker image
2. Push to ECR
3. **Manual**: Update ECS service

**Updated Workflow** (Automated):
1. Build Docker image
2. Push to ECR
3. **Automated**: Update ECS service
4. **Automated**: Wait for deployment to complete
5. **Automated**: Run health check verification

**Workflow Updates**:

Add to `infrastructure/.github/workflows/deploy-workout-planner-backend.yml`:

```yaml
- name: Update ECS service
  run: |
    aws ecs update-service \
      --cluster app-cluster \
      --service workout-planner-service \
      --force-new-deployment \
      --region us-east-1

- name: Wait for service stability
  run: |
    aws ecs wait services-stable \
      --cluster app-cluster \
      --services workout-planner-service \
      --region us-east-1

- name: Verify deployment
  run: |
    TASK_ARN=$(aws ecs list-tasks \
      --cluster app-cluster \
      --service-name workout-planner-service \
      --desired-status RUNNING \
      --query 'taskArns[0]' \
      --output text)

    TASK_DEF=$(aws ecs describe-tasks \
      --cluster app-cluster \
      --tasks $TASK_ARN \
      --query 'tasks[0].taskDefinitionArn' \
      --output text)

    echo "✅ Deployed task definition: $TASK_DEF"

    # Health check
    ALB_DNS="workout-planner-alb-xxx.us-east-1.elb.amazonaws.com"
    curl -f https://$ALB_DNS/health || exit 1
    echo "✅ Health check passed"
```

**Configuration File**: Update workflow files

**Validation**:
- [ ] Workflow runs successfully
- [ ] ECS service updates automatically
- [ ] Health check verification passes
- [ ] Rollback works on failure

---

## Implementation Timeline

### Week 1: Infrastructure Foundation

**Days 1-2**: Database & ALB
- [ ] Monday: Provision RDS PostgreSQL
- [ ] Monday: Configure RDS security group
- [ ] Monday: Store credentials in Secrets Manager
- [ ] Tuesday: Create Application Load Balancer
- [ ] Tuesday: Request and validate SSL certificate
- [ ] Tuesday: Configure target groups and listeners

**Days 3-4**: Monitoring & Backups
- [ ] Wednesday: Set up CloudWatch alarms
- [ ] Wednesday: Configure SNS notifications
- [ ] Wednesday: Test alarm triggers
- [ ] Thursday: Enable automated backups
- [ ] Thursday: Create backup plan
- [ ] Thursday: Test disaster recovery

**Day 5**: Testing & Validation
- [ ] Friday: End-to-end testing
- [ ] Friday: Load testing
- [ ] Friday: Security testing
- [ ] Friday: Documentation updates

### Week 2: Optimization & Automation

**Days 1-2**: Rate Limiting & Auto-Scaling
- [ ] Monday: Implement rate limiting
- [ ] Monday: Test rate limiting behavior
- [ ] Tuesday: Configure auto-scaling
- [ ] Tuesday: Test scaling behavior

**Days 3-4**: Workflow Automation
- [ ] Wednesday: Update deployment workflows
- [ ] Wednesday: Test automated deployments
- [ ] Thursday: Blue-green deployment setup (optional)
- [ ] Thursday: Rollback testing

**Day 5**: Production Deployment
- [ ] Friday: Final pre-production checks
- [ ] Friday: Deploy to production
- [ ] Friday: Monitor for 24 hours
- [ ] Friday: Post-deployment validation

---

## Success Criteria

### Technical Metrics

- [x] Database: PostgreSQL running on RDS Multi-AZ
- [ ] SSL: Valid certificate on ALB
- [ ] Availability: 99.5% uptime (measured over 1 week)
- [ ] Latency: P95 < 500ms, P99 < 1s
- [ ] Error Rate: < 0.1%
- [ ] Auto-scaling: 2-10 tasks based on load
- [ ] Backups: Daily automated backups with 7-day retention
- [ ] Alarms: 6+ critical alarms configured and tested
- [ ] Rate Limiting: Working on all endpoints

### Operational Metrics

- [ ] MTTD (Mean Time To Detection): < 5 minutes
- [ ] MTTR (Mean Time To Recovery): < 30 minutes
- [ ] Deployment: Fully automated with health checks
- [ ] Monitoring: Real-time dashboard available
- [ ] Documentation: All runbooks updated

---

## Cost Impact

### Before Phase 1
- ECS Fargate: $20/month (1 task, 0.25 vCPU)
- CloudWatch: $5/month (basic logs)
- **Total**: $25/month

### After Phase 1
- RDS PostgreSQL (db.t3.micro, Multi-AZ): $30/month
- ECS Fargate (2-10 tasks, 0.5 vCPU): $40-200/month
- Application Load Balancer: $16/month
- CloudWatch (enhanced): $15/month
- **Total**: $101-261/month

**Average Expected**: ~$150/month (4 tasks average)

**Cost Optimization Opportunities**:
- Reserved instances for predictable workloads
- Fargate Spot for non-critical tasks
- S3 lifecycle policies for old backups
- CloudWatch log retention policies

---

## Risk Assessment

### High Risks

1. **Database Migration**
   - Risk: Data loss during migration
   - Mitigation: Test migration in staging first
   - Rollback: Keep SQLite backup for 30 days

2. **SSL Certificate Validation**
   - Risk: DNS validation timeout
   - Mitigation: Prepare DNS access in advance
   - Rollback: Use self-signed cert temporarily

3. **ALB Configuration**
   - Risk: Downtime during cutover
   - Mitigation: Blue-green deployment
   - Rollback: Keep old ECS service running

### Medium Risks

4. **Auto-Scaling Behavior**
   - Risk: Aggressive scaling = cost overrun
   - Mitigation: Set max task limit (10)
   - Monitoring: CloudWatch cost alerts

5. **Rate Limiting**
   - Risk: Legitimate users blocked
   - Mitigation: Generous limits initially
   - Adjustment: Monitor and tune based on usage

### Low Risks

6. **CloudWatch Alarms**
   - Risk: Alert fatigue from false positives
   - Mitigation: Tune thresholds based on baseline
   - Adjustment: Weekly review and refinement

---

## Rollback Plan

### Scenario: Critical Issue Discovered

**Immediate Actions**:
1. Stop all traffic to ALB
2. Revert ECS service to previous task definition
3. Update DNS to point to old endpoint (if needed)
4. Communicate status to stakeholders

**Recovery Steps**:
1. Identify root cause
2. Fix in staging environment
3. Test thoroughly
4. Deploy fix to production
5. Post-mortem analysis

**Data Recovery**:
- RDS: Restore from latest automated backup
- Application: Deploy previous container image
- Logs: Review CloudWatch logs for troubleshooting

---

## Next Steps After Phase 1

### Phase 2: Testing & Quality (Week 3-4)
- Comprehensive test suite (80% coverage)
- Load testing with realistic traffic
- Security testing (OWASP Top 10)
- Performance optimization

### Phase 3: Advanced Features (Week 5-6)
- APM integration (AWS X-Ray)
- Distributed tracing
- Enhanced metrics dashboards
- Multi-region deployment (optional)

---

## Resources & Documentation

**Terraform Files**:
- `infrastructure/terraform/rds.tf` - Database configuration
- `infrastructure/terraform/alb.tf` - Load balancer setup
- `infrastructure/terraform/cloudwatch.tf` - Alarms and monitoring
- `infrastructure/terraform/autoscaling.tf` - Auto-scaling policies
- `infrastructure/terraform/backup.tf` - Backup configuration

**Application Updates**:
- `workout-planner/backend/main.py` - Rate limiting
- `workout-planner/backend/requirements.txt` - New dependencies
- `workout-planner/backend/Dockerfile` - Updated build

**Workflow Updates**:
- `infrastructure/.github/workflows/deploy-workout-planner-backend.yml` - Automated deployment

**Runbooks**:
- Database failover procedure
- ECS service rollback
- SSL certificate renewal
- Backup restoration

---

**Status**: Ready to begin implementation
**Next Action**: Task 1 - Provision RDS PostgreSQL Database
