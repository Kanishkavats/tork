# Ride Status Flow Documentation

## Database Columns

### rides table new columns:
- `is_picked_up` (INTEGER, default: 0)
  - 0 = Customer not picked up yet
  - 1 = Customer picked up

- `is_dropped` (INTEGER, default: 0)
  - 0 = Customer not dropped yet
  - 1 = Customer dropped (completed)

## Ride Flow States

1. **Customer Books Ride**
   - `status` = 'requested'
   - `is_picked_up` = 0
   - `is_dropped` = 0

2. **Driver Accepts Ride**
   - API: `/api/driver/accept-ride`
   - `status` = 'accepted'
   - `driver_id` = assigned
   - `is_picked_up` = 0
   - `is_dropped` = 0

3. **Driver Starts Navigation**
   - API: `/api/driver/start-ride`
   - `status` = 'in_progress'
   - `is_picked_up` = 0
   - `is_dropped` = 0
   - Driver navigating to pickup location

4. **Driver Picks Up Customer**
   - API: `/api/driver/pickup-customer`
   - `status` = 'in_progress' (unchanged)
   - `is_picked_up` = 1 ✓
   - `is_dropped` = 0
   - Driver navigating to drop location

5. **Driver Completes Ride**
   - API: `/api/driver/complete-ride`
   - `status` = 'completed'
   - `is_picked_up` = 1 ✓
   - `is_dropped` = 1 ✓
   - Earnings credited to driver wallet

## API Endpoints

### POST /api/driver/pickup-customer
Updates `is_picked_up` to 1

**Request:**
```json
{
  "ride_id": 123,
  "driver_phone": "9876543210"
}
```

**Response:**
```json
{
  "status": "success",
  "message": "Customer picked up, heading to drop location"
}
```

### POST /api/driver/complete-ride
Updates `is_dropped` to 1 and `status` to 'completed'

**Request:**
```json
{
  "ride_id": 123,
  "driver_phone": "9876543210"
}
```

**Response:**
```json
{
  "status": "success",
  "message": "Trip completed, earnings credited to wallet",
  "driver_earnings": 120.00,
  "fare": 150.00
}
```

## Queries

### Check pickup/drop status
```sql
SELECT id, status, is_picked_up, is_dropped, 
       pickup_address, drop_address, estimated_fare
FROM rides 
WHERE driver_id = ?
ORDER BY created_at DESC;
```

### Get rides where customer is picked but not dropped
```sql
SELECT * FROM rides 
WHERE is_picked_up = 1 
  AND is_dropped = 0 
  AND status = 'in_progress';
```

### Get completed rides
```sql
SELECT * FROM rides 
WHERE is_picked_up = 1 
  AND is_dropped = 1 
  AND status = 'completed';
```
