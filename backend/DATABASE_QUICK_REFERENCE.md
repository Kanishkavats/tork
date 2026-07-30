# Database Quick Reference Guide

## Database Setup Files

### Main Files
1. **complete_database_schema.sql** - Complete database setup with sample data
2. **add_pickup_drop_columns.sql** - Migration for pickup/drop tracking
3. **add_gender_columns.sql** - Migration for passenger gender counts

---

## How to Setup Database

### Step 1: Create Database
```sql
CREATE DATABASE torkk_db;
```

### Step 2: Connect to Database
```bash
psql -U postgres -d torkk_db
```

### Step 3: Run Complete Schema
```bash
psql -U postgres -d torkk_db -f complete_database_schema.sql
```

Or from psql:
```sql
\i complete_database_schema.sql
```

### Step 4: Verify Setup
```sql
-- List all tables
\dt

-- Check row counts
SELECT 'users' as table_name, COUNT(*) as row_count FROM users
UNION ALL
SELECT 'drivers', COUNT(*) FROM drivers
UNION ALL
SELECT 'rides', COUNT(*) FROM rides;
```

---

## Database Tables Overview

### 1. **users** - Customer/Rider accounts
- Primary Key: `id` (Serial)
- Unique: `phone`
- Stores: Profile, location, biometric info

### 2. **drivers** - Driver accounts
- Primary Key: `id` (Serial)
- Unique: `phone`, `aadhaar_number`, `driving_licence_number`
- Stores: Profile, verification status, rating

### 3. **vehicles** - Driver vehicles
- Primary Key: `id` (Serial)
- Foreign Key: `driver_id` → drivers(id)
- Stores: Vehicle details, plate number

### 4. **driver_locations** - Real-time driver GPS
- Primary Key: `driver_id` (References drivers)
- Stores: Latitude, longitude, timestamp

### 5. **driver_wallets** - Driver earnings
- Primary Key: `wallet_id` (Serial)
- Unique: `driver_id`
- Stores: Balance, total earnings

### 6. **rides** - All ride bookings
- Primary Key: `id` (Serial)
- Foreign Keys: 
  - `customer_phone` → users(phone)
  - `driver_id` → drivers(id)
- Stores: Pickup/drop locations, fare, status, gender counts
- **Important columns:**
  - `is_picked_up` (0/1)
  - `is_dropped` (0/1)
  - `male_passengers` (count)
  - `female_passengers` (count)

### 7. **sos_events** - Emergency alerts
- Primary Key: `id` (Serial)
- Foreign Key: `ride_id` → rides(id)
- Stores: Location, status

### 8. **emergency_contacts** - User emergency contacts
- Primary Key: `id` (Serial)
- Foreign Key: `customer_phone` → users(phone)
- Unique: (customer_phone, contact_phone)

---

## Common Queries

### User Management

#### Check if user exists
```sql
SELECT * FROM users WHERE phone = '8310501036';
```

#### Register new user
```sql
INSERT INTO users (phone, full_name, gender, email)
VALUES ('9999999999', 'Test User', 'Male', 'test@example.com')
RETURNING id;
```

#### Update user profile
```sql
UPDATE users 
SET full_name = 'New Name', 
    profile_photo_url = 'https://...',
    dob = '1990-01-01'
WHERE phone = '8310501036';
```

---

### Driver Management

#### Get active drivers
```sql
SELECT d.*, dl.latitude, dl.longitude
FROM drivers d
LEFT JOIN driver_locations dl ON d.id = dl.driver_id
WHERE d.is_active = TRUE AND d.is_verified = TRUE;
```

#### Register new driver
```sql
INSERT INTO drivers (full_name, phone, email, gender, is_verified)
VALUES ('New Driver', '9888888888', 'driver@torkk.com', 'Male', FALSE)
RETURNING id;
```

#### Update driver location
```sql
INSERT INTO driver_locations (driver_id, latitude, longitude, updated_at)
VALUES (1, 14.4767, 75.8855, NOW())
ON CONFLICT (driver_id) DO UPDATE SET
    latitude = EXCLUDED.latitude,
    longitude = EXCLUDED.longitude,
    updated_at = EXCLUDED.updated_at;
```

---

### Ride Management

#### Create new ride
```sql
INSERT INTO rides (
    customer_phone, pickup_lat, pickup_lng, pickup_address,
    drop_lat, drop_lng, drop_address, vehicle_type,
    distance_km, estimated_fare, male_passengers, female_passengers, status
)
VALUES (
    '8310501036', 14.4633, 75.9237, 'MCC B Block',
    14.4693, 75.9307, 'Saraswathipuram', 'cab',
    5.2, 120.00, 1, 0, 'requested'
)
RETURNING id;
```

#### Assign driver to ride
```sql
UPDATE rides 
SET driver_id = 1, 
    status = 'accepted',
    updated_at = NOW()
WHERE id = 10 AND status = 'requested';
```

#### Mark customer picked up
```sql
UPDATE rides 
SET is_picked_up = 1,
    updated_at = NOW()
WHERE id = 10 AND driver_id = 1 AND status = 'in_progress';
```

#### Complete ride
```sql
UPDATE rides 
SET status = 'completed',
    is_dropped = 1,
    driver_earnings = estimated_fare * 0.8,
    updated_at = NOW()
WHERE id = 10 AND driver_id = 1;
```

#### Get ride details
```sql
SELECT r.*, 
       u.full_name as customer_name,
       d.full_name as driver_name,
       d.phone as driver_phone
FROM rides r
LEFT JOIN users u ON r.customer_phone = u.phone
LEFT JOIN drivers d ON r.driver_id = d.id
WHERE r.id = 10;
```

#### Get driver's trip history
```sql
SELECT r.id, r.pickup_address, r.drop_address,
       r.estimated_fare, r.driver_earnings,
       r.status, r.created_at, u.full_name as customer_name,
       r.male_passengers, r.female_passengers
FROM rides r
LEFT JOIN users u ON r.customer_phone = u.phone
WHERE r.driver_id = 1 AND r.status = 'completed'
ORDER BY r.created_at DESC;
```

---

### Wallet Management

#### Get driver wallet
```sql
SELECT * FROM driver_wallets WHERE driver_id = 1;
```

#### Update wallet after ride completion
```sql
INSERT INTO driver_wallets (driver_id, balance, total_earnings)
VALUES (1, 96.00, 96.00)
ON CONFLICT (driver_id) DO UPDATE SET
    balance = driver_wallets.balance + EXCLUDED.balance,
    total_earnings = driver_wallets.total_earnings + EXCLUDED.total_earnings,
    last_settled_at = NOW();
```

#### Get earnings summary
```sql
SELECT 
    COALESCE(SUM(driver_earnings), 0) as today_earnings,
    COUNT(*) as today_trips
FROM rides 
WHERE driver_id = 1 
  AND status = 'completed' 
  AND created_at >= CURRENT_DATE;
```

---

### Analytics Queries

#### Total rides by status
```sql
SELECT status, COUNT(*) as count, SUM(estimated_fare) as total_fare
FROM rides
GROUP BY status
ORDER BY count DESC;
```

#### Revenue by vehicle type
```sql
SELECT vehicle_type,
       COUNT(*) as rides,
       SUM(estimated_fare) as total_fare,
       AVG(estimated_fare) as avg_fare,
       SUM(driver_earnings) as driver_earnings
FROM rides
WHERE status = 'completed'
GROUP BY vehicle_type
ORDER BY total_fare DESC;
```

#### Passenger gender distribution
```sql
SELECT vehicle_type,
       SUM(male_passengers) as total_male,
       SUM(female_passengers) as total_female,
       ROUND(SUM(male_passengers)::numeric / 
             (SUM(male_passengers) + SUM(female_passengers)) * 100, 2) as male_percentage
FROM rides
WHERE status = 'completed'
GROUP BY vehicle_type;
```

#### Top earning drivers
```sql
SELECT d.full_name, d.phone, d.rating,
       dw.total_earnings, dw.balance,
       COUNT(r.id) as total_rides
FROM drivers d
INNER JOIN driver_wallets dw ON d.id = dw.driver_id
LEFT JOIN rides r ON d.id = r.driver_id AND r.status = 'completed'
GROUP BY d.id, d.full_name, d.phone, d.rating, dw.total_earnings, dw.balance
ORDER BY dw.total_earnings DESC
LIMIT 10;
```

#### Daily ride statistics
```sql
SELECT DATE(created_at) as date,
       COUNT(*) as total_rides,
       SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) as completed_rides,
       SUM(estimated_fare) as total_fare,
       SUM(driver_earnings) as total_driver_earnings
FROM rides
WHERE created_at >= CURRENT_DATE - INTERVAL '7 days'
GROUP BY DATE(created_at)
ORDER BY date DESC;
```

#### Vehicle capacity utilization
```sql
SELECT vehicle_type,
       CASE vehicle_type
         WHEN 'Bike' THEN 1
         WHEN 'Auto' THEN 3
         WHEN 'Cab' THEN 4
         WHEN 'EV Cab' THEN 4
         WHEN 'XL Cab' THEN 6
       END as max_capacity,
       AVG(male_passengers + female_passengers) as avg_passengers,
       ROUND(AVG(male_passengers + female_passengers) / 
         CASE vehicle_type
           WHEN 'Bike' THEN 1
           WHEN 'Auto' THEN 3
           WHEN 'Cab' THEN 4
           WHEN 'EV Cab' THEN 4
           WHEN 'XL Cab' THEN 6
         END * 100, 2) as utilization_percentage
FROM rides
WHERE status = 'completed'
GROUP BY vehicle_type;
```

---

## Database Maintenance

### Backup Database
```bash
pg_dump -U postgres -d torkk_db -F c -f torkk_backup_$(date +%Y%m%d).dump
```

### Restore Database
```bash
pg_restore -U postgres -d torkk_db -F c torkk_backup_20260708.dump
```

### Vacuum Database (Optimize)
```sql
VACUUM ANALYZE;
```

### Check Database Size
```sql
SELECT pg_size_pretty(pg_database_size('torkk_db'));
```

### Check Table Sizes
```sql
SELECT 
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;
```

---

## Sample Data Summary

### Default Data Included

**Users (Customers):**
- 5 sample users
- Phone: 8310501036, 9876543210, etc.

**Drivers:**
- 5 verified drivers
- All active and rated
- With vehicles and locations

**Rides:**
- 5 completed rides with earnings
- 2 in-progress/requested rides
- All in Davangere area

**Emergency Contacts:**
- Sample contacts for users

---

## Connection String Format

### Local Development
```
host=localhost port=5432 user=postgres password=YourPassword dbname=torkk_db sslmode=disable
```

### AWS RDS Production
```
host=torkk-db.xxxxx.ap-south-1.rds.amazonaws.com port=5432 user=torkk_admin password=YourPassword dbname=torkk sslmode=require
```

---

## Troubleshooting

### Can't connect to database
```sql
-- Check if PostgreSQL is running
sudo systemctl status postgresql

-- Restart PostgreSQL
sudo systemctl restart postgresql

-- Check connections
SELECT * FROM pg_stat_activity WHERE datname = 'torkk_db';
```

### Reset all data (CAUTION)
```sql
TRUNCATE users, drivers, vehicles, driver_locations, 
         driver_wallets, rides, sos_events, emergency_contacts 
RESTART IDENTITY CASCADE;
```

### Check for missing indexes
```sql
SELECT schemaname, tablename, indexname
FROM pg_indexes
WHERE schemaname = 'public'
ORDER BY tablename, indexname;
```

---

## Quick Start Commands

```bash
# 1. Create database
createdb -U postgres torkk_db

# 2. Run schema
psql -U postgres -d torkk_db -f complete_database_schema.sql

# 3. Verify
psql -U postgres -d torkk_db -c "\dt"

# 4. Check data
psql -U postgres -d torkk_db -c "SELECT COUNT(*) FROM rides;"
```

---

## Support

For issues or questions:
1. Check logs: `tail -f /var/log/postgresql/postgresql-*.log`
2. Review query plans: `EXPLAIN ANALYZE <your-query>;`
3. Monitor connections: `SELECT * FROM pg_stat_activity;`
