-- Add columns to track pickup and drop status in rides table
-- Run this SQL query on your PostgreSQL database

ALTER TABLE rides 
ADD COLUMN IF NOT EXISTS is_picked_up INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS is_dropped INTEGER DEFAULT 0;

-- Update existing completed rides to mark them as picked up and dropped
UPDATE rides 
SET is_picked_up = 1, is_dropped = 1 
WHERE status = 'completed';

-- Update existing in_progress rides to mark them as not picked up yet
UPDATE rides 
SET is_picked_up = 0, is_dropped = 0 
WHERE status IN ('accepted', 'in_progress');

-- Verification query
SELECT id, status, is_picked_up, is_dropped 
FROM rides 
ORDER BY created_at DESC 
LIMIT 10;
