# Passenger Seat Limits & Gender Count Updates

## Summary
1. Removed "Same Gender Ride" option from ALL vehicles (Bike, Auto, Cab, EV Cab, XL Cab)
2. All vehicles now save male and female passenger counts to database
3. Added seat capacity validation - passengers cannot exceed vehicle max seats

## Vehicle Seat Capacities

| Vehicle | Max Seats |
|---------|-----------|
| Bike    | 1         |
| Auto    | 3         |
| Cab     | 4         |
| EV Cab  | 4         |
| XL Cab  | 6         |

## Changes Made

### UI Changes

#### Bike (Special Case)
- Gender selection buttons (Male/Female icons)
- Only 1 passenger allowed
- No counter - just select Male or Female

#### All Other Vehicles (Auto, Cab, EV Cab, XL Cab)
- Male and Female passenger counters
- **Removed "Same Gender Ride" toggle completely**
- Max seat indicator showing: "Max X passengers • Currently: Y"
- Cannot add passengers beyond vehicle capacity
- Validation on proceed button

### Frontend Validation

#### Passenger Count Validation
```dart
// When adding passengers
int totalPassengers = malePassengers + femalePassengers;
if (totalPassengers <= maxSeats) {
  // Allow increment
} else {
  // Block increment - capacity reached
}
```

#### Proceed Validation
- Minimum 1 passenger required
- Maximum cannot exceed vehicle capacity
- Shows error message if validation fails

### Database
All passenger counts saved to database:
- `male_passengers` (INTEGER)
- `female_passengers` (INTEGER)

### Backend
`POST /api/ride/request` saves both male and female counts for all vehicles.

## Example Scenarios

### Bike - 1 Passenger Max
- User selects "Bike"
- Clicks "Female" button
- Saved: `male: 0, female: 1` ✓
- Cannot add more passengers (capacity: 1)

### Auto - 3 Seats Max
- User selects "Auto"
- Sets: Male: 2, Female: 1
- Total: 3 ✓
- Trying to add more shows capacity info
- Saved: `male: 2, female: 1`

### Cab - 4 Seats Max
- User selects "Cab"
- Sets: Male: 2, Female: 3
- Total: 5 ❌ (exceeds limit)
- Counter blocks at: Male: 2, Female: 2 (total: 4)
- Saved: `male: 2, female: 2`

### XL Cab - 6 Seats Max
- User selects "XL Cab"
- Sets: Male: 3, Female: 3
- Total: 6 ✓
- Saved: `male: 3, female: 3`

## Removed Features
- ❌ "Same Gender Ride" toggle (from ALL vehicles)
- ❌ "Same Gender" badge on Bike

## User Experience
1. Select vehicle → See max seat capacity
2. Set passengers → Counter shows current/max
3. Try to exceed → Counter blocks, visual feedback
4. Proceed with 0 passengers → Error message
5. Proceed with valid count → Success, data saved

## Validation Messages

### No Passengers
"Please select at least 1 passenger"

### Exceeds Capacity
"Maximum X passengers allowed for [Vehicle Name]"

## Analytics Queries

### Passenger distribution by vehicle
```sql
SELECT vehicle_type,
       AVG(male_passengers) as avg_male,
       AVG(female_passengers) as avg_female,
       AVG(male_passengers + female_passengers) as avg_total_passengers,
       COUNT(*) as ride_count
FROM rides
GROUP BY vehicle_type;
```

### Capacity utilization
```sql
SELECT vehicle_type,
       CASE vehicle_type
         WHEN 'Bike' THEN 1
         WHEN 'Auto' THEN 3
         WHEN 'Cab' THEN 4
         WHEN 'EV Cab' THEN 4
         WHEN 'XL Cab' THEN 6
       END as max_capacity,
       AVG(male_passengers + female_passengers) as avg_passengers_used,
       ROUND(AVG(male_passengers + female_passengers)::numeric / 
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
