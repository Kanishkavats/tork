# AWS Deployment Guide - Torkk Backend & Database

## Overview
This guide covers deploying your Go API backend and PostgreSQL database to AWS.

---

## Architecture Options

### Option 1: Simple & Cost-Effective (Recommended for Start)
- **EC2 Instance** (t3.small or t3.medium) - Run Go API
- **RDS PostgreSQL** (db.t3.micro) - Managed database
- **Elastic IP** - Static IP for API
- **Estimated Cost**: $30-50/month

### Option 2: Production-Ready with Load Balancing
- **EC2 Auto Scaling Group** - Multiple API instances
- **Application Load Balancer** - Distribute traffic
- **RDS PostgreSQL** (Multi-AZ) - High availability
- **Route 53** - Custom domain
- **Estimated Cost**: $100-200/month

### Option 3: Containerized (Modern Approach)
- **ECS Fargate** or **EKS** - Container orchestration
- **RDS PostgreSQL** - Managed database
- **Application Load Balancer**
- **Estimated Cost**: $80-150/month

---

## Recommended: Option 1 - Simple Deployment

### Step 1: Setup RDS PostgreSQL Database

#### 1.1 Create RDS Instance
1. Go to AWS Console → RDS → Create database
2. Choose:
   - **Engine**: PostgreSQL 15.x or 16.x
   - **Template**: Free tier (or Production if needed)
   - **DB Instance Class**: db.t3.micro (free tier) or db.t3.small
   - **Storage**: 20 GB SSD (can auto-scale)
   - **DB Instance Identifier**: `torkk-postgres-db`
   - **Master Username**: `torkk_admin`
   - **Master Password**: `[Create a strong password]`

#### 1.2 Database Configuration
- **VPC**: Default VPC (or create new)
- **Public Access**: Yes (for initial setup, restrict later)
- **VPC Security Group**: Create new → `torkk-db-sg`
- **Database Port**: 5432
- **Initial Database Name**: `torkk`

#### 1.3 Security Group Rules (torkk-db-sg)
**Inbound Rules:**
- Type: PostgreSQL
- Protocol: TCP
- Port: 5432
- Source: Your EC2 security group (will create later)
- Description: Allow from API server

**For initial setup only (remove later):**
- Source: Your IP address (to run migrations)

#### 1.4 Get Connection Details
After creation, note:
- **Endpoint**: `torkk-postgres-db.xxxxx.ap-south-1.rds.amazonaws.com`
- **Port**: 5432
- **Database**: torkk
- **Username**: torkk_admin
- **Password**: [your password]

---

### Step 2: Setup EC2 Instance for Go API

#### 2.1 Launch EC2 Instance
1. Go to EC2 → Launch Instance
2. Choose:
   - **Name**: `torkk-api-server`
   - **AMI**: Ubuntu Server 22.04 LTS
   - **Instance Type**: t3.small (2 vCPU, 2GB RAM)
   - **Key Pair**: Create new or use existing (download .pem file)
   - **Storage**: 20 GB gp3

#### 2.2 Network Settings
- **VPC**: Same as RDS
- **Auto-assign Public IP**: Enable
- **Security Group**: Create new → `torkk-api-sg`

**Security Group Rules (torkk-api-sg):**

**Inbound:**
- SSH (Port 22) from Your IP
- HTTP (Port 80) from Anywhere (0.0.0.0/0)
- HTTPS (Port 443) from Anywhere (0.0.0.0/0)
- Custom TCP (Port 8080) from Anywhere (for API)

**Outbound:**
- All traffic to Anywhere (default)

#### 2.3 Allocate Elastic IP (Static IP)
1. EC2 → Elastic IPs → Allocate Elastic IP
2. Associate with your `torkk-api-server` instance
3. Note the Elastic IP (e.g., `13.127.45.123`)

---

### Step 3: Connect to EC2 and Install Dependencies

#### 3.1 Connect via SSH
```bash
# Windows (use Git Bash or PowerShell)
ssh -i "your-key.pem" ubuntu@13.127.45.123

# If permission error on Windows:
icacls "your-key.pem" /inheritance:r
icacls "your-key.pem" /grant:r "%username%:R"
```

#### 3.2 Install Go
```bash
# Update system
sudo apt update
sudo apt upgrade -y

# Install Go
cd ~
wget https://go.dev/dl/go1.22.0.linux-amd64.tar.gz
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf go1.22.0.linux-amd64.tar.gz

# Add to PATH
echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
echo 'export PATH=$PATH:~/go/bin' >> ~/.bashrc
source ~/.bashrc

# Verify
go version
```

#### 3.3 Install PostgreSQL Client (for testing)
```bash
sudo apt install postgresql-client -y
```

#### 3.4 Install Git
```bash
sudo apt install git -y
```

---

### Step 4: Deploy Your Go Application

#### 4.1 Upload Your Code
**Option A: Using Git (Recommended)**
```bash
# On EC2
cd ~
git clone https://github.com/yourusername/torkk-backend.git
cd torkk-backend/backend
```

**Option B: Using SCP (from your local machine)**
```bash
# From your Windows machine
scp -i "your-key.pem" -r D:\AndroidStudioProjects\android-app\backend ubuntu@13.127.45.123:~/torkk-backend
```

#### 4.2 Update Database Connection
```bash
cd ~/torkk-backend/backend

# Edit main.go or use environment variables
nano main.go
```

Update the database connection string to your RDS endpoint:
```go
dbHost := "torkk-postgres-db.xxxxx.ap-south-1.rds.amazonaws.com"
dbPort := "5432"
dbUser := "torkk_admin"
dbPassword := "your-password"
dbName := "torkk"

connStr := fmt.Sprintf("host=%s port=%s user=%s password=%s dbname=%s sslmode=require",
    dbHost, dbPort, dbUser, dbPassword, dbName)
```

#### 4.3 Install Dependencies
```bash
go mod tidy
go mod download
```

#### 4.4 Build the Application
```bash
go build -o torkk-api main.go
```

---

### Step 5: Setup Database Schema

#### 5.1 Connect to RDS from EC2
```bash
psql -h torkk-postgres-db.xxxxx.ap-south-1.rds.amazonaws.com \
     -U torkk_admin \
     -d torkk \
     -p 5432
```

#### 5.2 Run SQL Scripts
```sql
-- Run your table creation scripts
\i create_tables.sql

-- Run migrations
\i add_pickup_drop_columns.sql
\i add_gender_columns.sql

-- Verify
\dt
\q
```

---

### Step 6: Run Application as a Service

#### 6.1 Create Systemd Service
```bash
sudo nano /etc/systemd/system/torkk-api.service
```

Add this content:
```ini
[Unit]
Description=Torkk Go API Server
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/home/ubuntu/torkk-backend/backend
ExecStart=/home/ubuntu/torkk-backend/backend/torkk-api
Restart=always
RestartSec=5
StandardOutput=append:/var/log/torkk-api.log
StandardError=append:/var/log/torkk-api-error.log

Environment="DB_HOST=torkk-postgres-db.xxxxx.ap-south-1.rds.amazonaws.com"
Environment="DB_PORT=5432"
Environment="DB_USER=torkk_admin"
Environment="DB_PASSWORD=your-password"
Environment="DB_NAME=torkk"
Environment="MSG91_AUTH_KEY=your-msg91-key"
Environment="MSG91_TEMPLATE_ID=your-template-id"
Environment="MSG91_SENDER=TORKKK"

[Install]
WantedBy=multi-user.target
```

#### 6.2 Enable and Start Service
```bash
# Set permissions
sudo chmod 644 /etc/systemd/system/torkk-api.service

# Reload systemd
sudo systemctl daemon-reload

# Enable service (start on boot)
sudo systemctl enable torkk-api

# Start service
sudo systemctl start torkk-api

# Check status
sudo systemctl status torkk-api

# View logs
sudo journalctl -u torkk-api -f
```

#### 6.3 Verify API is Running
```bash
curl http://localhost:8080/api/check-phone?phone=1234567890
```

---

### Step 7: Setup Nginx Reverse Proxy (Optional but Recommended)

#### 7.1 Install Nginx
```bash
sudo apt install nginx -y
```

#### 7.2 Configure Nginx
```bash
sudo nano /etc/nginx/sites-available/torkk-api
```

Add:
```nginx
server {
    listen 80;
    server_name 13.127.45.123;  # Your Elastic IP or domain

    location / {
        proxy_pass http://localhost:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

#### 7.3 Enable Site
```bash
sudo ln -s /etc/nginx/sites-available/torkk-api /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx
```

Now your API is accessible at: `http://13.127.45.123/api/...`

---

### Step 8: Setup SSL Certificate (Optional - for HTTPS)

#### 8.1 Get a Domain (if you have one)
Point your domain to the Elastic IP in your DNS provider.

#### 8.2 Install Certbot
```bash
sudo apt install certbot python3-certbot-nginx -y
```

#### 8.3 Get SSL Certificate
```bash
sudo certbot --nginx -d api.torkk.com
```

---

### Step 9: Update Flutter App API URL

Update your Flutter app to use the new API URL:

**lib/customer/services/api_service.dart:**
```dart
class RideService {
  static const String baseUrl = 'http://13.127.45.123:8080/api';
  // or with domain and SSL:
  // static const String baseUrl = 'https://api.torkk.com/api';
```

**lib/driver/services/driver_api_service.dart:**
```dart
class DriverApiService {
  static const String baseUrl = 'http://13.127.45.123:8080/api';
  // or with domain and SSL:
  // static const String baseUrl = 'https://api.torkk.com/api';
```

---

## Monitoring & Maintenance

### View Logs
```bash
# API logs
sudo journalctl -u torkk-api -f

# Nginx logs
sudo tail -f /var/log/nginx/access.log
sudo tail -f /var/log/nginx/error.log
```

### Restart Services
```bash
# Restart API
sudo systemctl restart torkk-api

# Restart Nginx
sudo systemctl restart nginx
```

### Update Application
```bash
cd ~/torkk-backend/backend
git pull origin main
go build -o torkk-api main.go
sudo systemctl restart torkk-api
```

### Database Backup
```bash
# Create backup
pg_dump -h torkk-postgres-db.xxxxx.ap-south-1.rds.amazonaws.com \
        -U torkk_admin \
        -d torkk \
        -F c \
        -f backup_$(date +%Y%m%d).dump

# Restore backup
pg_restore -h torkk-postgres-db.xxxxx.ap-south-1.rds.amazonaws.com \
           -U torkk_admin \
           -d torkk \
           -F c backup_20260708.dump
```

---

## Cost Estimation (Mumbai Region)

### Option 1 - Basic Setup
- **EC2 t3.small** (On-Demand): ~$15/month
- **RDS db.t3.micro** (Free tier eligible): $0-15/month
- **Storage (40GB total)**: ~$5/month
- **Data Transfer**: ~$5-10/month
- **Elastic IP**: Free if attached
- **Total**: ~$25-45/month

### Cost Saving Tips
1. Use **Reserved Instances** (1-year commitment) - Save 30-40%
2. Use **Savings Plans** - Save up to 72%
3. Enable **RDS Auto Scaling** - Pay only for what you use
4. Use **CloudWatch** alarms to monitor costs
5. Schedule EC2 stop/start for non-production environments

---

## Security Best Practices

### 1. Database Security
- [ ] Change RDS master password regularly
- [ ] Disable public access after setup
- [ ] Use VPC peering or AWS PrivateLink
- [ ] Enable encryption at rest
- [ ] Enable automated backups (7-day retention)

### 2. EC2 Security
- [ ] Keep system updated: `sudo apt update && sudo apt upgrade`
- [ ] Use SSH key authentication only (disable password)
- [ ] Restrict SSH to your IP only
- [ ] Install fail2ban: `sudo apt install fail2ban`
- [ ] Enable AWS CloudWatch monitoring

### 3. Application Security
- [ ] Store secrets in AWS Secrets Manager (not in code)
- [ ] Use environment variables for sensitive data
- [ ] Enable HTTPS with SSL certificate
- [ ] Implement rate limiting
- [ ] Add API authentication/authorization

### 4. Network Security
- [ ] Use Security Groups as firewalls
- [ ] Enable VPC Flow Logs
- [ ] Use AWS WAF for DDoS protection
- [ ] Restrict outbound traffic

---

## Troubleshooting

### API Not Accessible
```bash
# Check if API is running
sudo systemctl status torkk-api

# Check if port is listening
sudo netstat -tulpn | grep 8080

# Check firewall
sudo ufw status
```

### Database Connection Failed
```bash
# Test connection from EC2
psql -h [RDS-ENDPOINT] -U torkk_admin -d torkk

# Check security group allows EC2
# Check RDS is in same VPC
# Verify connection string
```

### High CPU/Memory Usage
```bash
# Monitor resources
htop
# or
top

# Check API logs for errors
sudo journalctl -u torkk-api --since "1 hour ago"
```

---

## Alternative: Using AWS Amplify/App Runner (Simpler)

### AWS App Runner (Easiest for Go)
1. Push code to GitHub
2. AWS App Runner → Create Service
3. Connect GitHub repository
4. Auto-deploys on git push
5. No server management needed
6. Cost: ~$25-50/month

### Benefits:
- Automatic scaling
- Built-in CI/CD
- Zero server management
- Auto SSL certificates

---

## Quick Start Checklist

- [ ] Create RDS PostgreSQL instance
- [ ] Note down RDS endpoint and credentials
- [ ] Launch EC2 instance (Ubuntu)
- [ ] Allocate and attach Elastic IP
- [ ] Configure security groups (EC2 & RDS)
- [ ] SSH into EC2
- [ ] Install Go, Git, PostgreSQL client
- [ ] Upload/clone your code
- [ ] Update database connection in code
- [ ] Build Go application
- [ ] Run database migrations
- [ ] Create systemd service
- [ ] Start and enable service
- [ ] Test API endpoints
- [ ] (Optional) Setup Nginx
- [ ] (Optional) Setup SSL with Certbot
- [ ] Update Flutter app with new API URL
- [ ] Test end-to-end

---

## Support Resources

- **AWS Documentation**: https://docs.aws.amazon.com/
- **AWS Free Tier**: https://aws.amazon.com/free/
- **RDS Pricing**: https://aws.amazon.com/rds/postgresql/pricing/
- **EC2 Pricing**: https://aws.amazon.com/ec2/pricing/
- **AWS Calculator**: https://calculator.aws/

---

## Need Help?

Common issues and solutions are available in AWS documentation. For specific errors, check:
1. CloudWatch Logs
2. Application logs (`/var/log/torkk-api.log`)
3. System logs (`journalctl -xe`)
