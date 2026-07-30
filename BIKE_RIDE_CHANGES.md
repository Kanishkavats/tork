# Bike Ride Gender Selection Changes

## Summary
Updated bike ride functionality to:
1. Remove "Same Gender" toggle for bikes
2. Add gender selection (Male/Female) for bike rides - only 1 passenger
3. Store male and female passenger counts in database

## Database Changes

### SQL Migration
Run this on your PostgreSQL database:

```sql
ALTER TABLE rides 
ADD COLUMN IF NOT EXISTS male_passengers INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS female_passengers INTEGER DEFAULT 0;
```

Location: `backend/add_gender_columns.sql`

## UI Changes

### Before (Bike):
- Showed "Same Gender Ride" badge
- Had toggle switch for same gender preference
- Passenger counter for male/female

### After (Bike):
- Shows "1 Passenger" capacity
- Gender selection buttons (Male/Female) with icons
- Only one can be selected at a time
- No same gender toggle

### Other Vehicles (Auto, Cab, etc.):
- Keep passenger counters for male/female
- Cab still has "Same Gender Ride" toggle
- No changes to functionality

## Backend Changes

### RideRequest Struct
Added fields:
- `MalePassengers int` - count of male passengers
- `FemalePassengers int` - count of female passengers

### Database Schema
New columns in `rides` table:
- `male_passengers` (INTEGER, default: 0)
- `female_passengers` (INTEGER, default: 0)

### API Changes
`POST /api/ride/request` now accepts:
```json
{
  "phone": "1234567890",
  "pickup_lat": 12.34,
  "pickup_lng": 56.78,
  "pickup_address": "Location A",
  "drop_lat": 12.35,
  "drop_lng": 56.79,
  "drop_address": "Location B",
  "vehicle": "Bike",
  "distance_km": 5.2,
  "fare": 120,
  "male_passengers": 1,
  "female_passengers": 0
}
```

## Example Scenarios

### Bike Ride - Male Passenger
- User selects "Bike"
- Clicks "Male" gender button
- Data saved: `male_passengers: 1, female_passengers: 0`

### Bike Ride - Female Passenger
- User selects "Bike"
- Clicks "Female" gender button
- Data saved: `male_passengers: 0, female_passengers: 1`

### Cab Ride - 2 Male, 1 Female
- User selects "Cab"
- Sets counters: Male: 2, Female: 1
- Optionally enables "Same Gender Ride" toggle
- Data saved: `male_passengers: 2, female_passengers: 1`

## Verification Queries

### Check gender distribution
```sql
SELECT vehicle_type, 
       SUM(male_passengers) as total_male,
       SUM(female_passengers) as total_female,
       COUNT(*) as total_rides
FROM rides 
GROUP BY vehicle_type;
```

### Check bike rides by gender
```sql
SELECT 
  CASE 
    WHEN male_passengers > 0 THEN 'Male'
    WHEN female_passengers > 0 THEN 'Female'
    ELSE 'Unknown'
  END as passenger_gender,
  COUNT(*) as ride_count
FROM rides 
WHERE vehicle_type = 'Bike'
GROUP BY passenger_gender;
```
