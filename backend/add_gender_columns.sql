-- Add columns to track male and female passenger count in rides table
-- Run this SQL query on your PostgreSQL database

ALTER TABLE rides 
ADD COLUMN IF NOT EXISTS male_passengers INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS female_passengers INTEGER DEFAULT 0;

-- Update existing rides with default values (1 male passenger for backward compatibility)
UPDATE rides 
SET male_passengers = 1, female_passengers = 0
WHERE male_passengers = 0 AND female_passengers = 0;

-- Verification query
SELECT id, vehicle_type, male_passengers, female_passengers, status, created_at
FROM rides 
ORDER BY created_at DESC 
LIMIT 10;
