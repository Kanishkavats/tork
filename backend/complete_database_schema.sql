-- ============================================
-- TORKK COMPLETE DATABASE SCHEMA
-- PostgreSQL Database Setup Script
-- ============================================

-- Drop existing tables (CAUTION: This will delete all data!)
-- Uncomment below lines if you want to start fresh
-- DROP TABLE IF EXISTS emergency_contacts CASCADE;
-- DROP TABLE IF EXISTS sos_events CASCADE;
-- DROP TABLE IF EXISTS rides CASCADE;
-- DROP TABLE IF EXISTS driver_wallets CASCADE;
-- DROP TABLE IF EXISTS driver_documents CASCADE;
-- DROP TABLE IF EXISTS driver_locations CASCADE;
-- DROP TABLE IF EXISTS vehicles CASCADE;
-- DROP TABLE IF EXISTS drivers CASCADE;
-- DROP TABLE IF EXISTS users CASCADE;

-- ============================================
-- TABLE: users (Customers/Riders)
-- ============================================
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    phone VARCHAR(20) UNIQUE NOT NULL,
    full_name VARCHAR(100),
    gender VARCHAR(20),
    profile_photo_url TEXT,
    dob VARCHAR(50),
    aadhaar_number VARCHAR(30),
    has_biometric BOOLEAN DEFAULT FALSE,
    biometric_type VARCHAR(20),
    email VARCHAR(255),
    current_latitude DECIMAL(10, 8),
    current_longitude DECIMAL(11, 8),
    current_location_address TEXT,
    current_location_updated_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Add phone unique constraint if not exists
DO $$ 
BEGIN 
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'phone_unique') THEN 
        ALTER TABLE users ADD CONSTRAINT phone_unique UNIQUE (phone); 
    END IF; 
END $$;

-- Create index for faster lookups
CREATE INDEX IF NOT EXISTS idx_users_phone ON users(phone);

-- ============================================
-- TABLE: drivers
-- ============================================
CREATE TABLE IF NOT EXISTS drivers (
    id SERIAL PRIMARY KEY,
    full_name VARCHAR(100),
    phone VARCHAR(20) UNIQUE NOT NULL,
    email VARCHAR(100),
    gender VARCHAR(20),
    dob VARCHAR(50),
    aadhaar_number VARCHAR(30) UNIQUE,
    driving_licence_number VARCHAR(50) UNIQUE,
    profile_photo_url TEXT,
    is_verified BOOLEAN DEFAULT FALSE,
    rating DECIMAL(2,1) DEFAULT 5.0,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for drivers
CREATE INDEX IF NOT EXISTS idx_drivers_phone ON drivers(phone);
CREATE INDEX IF NOT EXISTS idx_drivers_verified ON drivers(is_verified);
CREATE INDEX IF NOT EXISTS idx_drivers_active ON drivers(is_active);

-- ============================================
-- TABLE: vehicles
-- ============================================
CREATE TABLE IF NOT EXISTS vehicles (
    id SERIAL PRIMARY KEY,
    driver_id INTEGER REFERENCES drivers(id) ON DELETE CASCADE,
    vehicle_type VARCHAR(50) NOT NULL,
    plate_number VARCHAR(30) UNIQUE NOT NULL,
    model VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create index
CREATE INDEX IF NOT EXISTS idx_vehicles_driver ON vehicles(driver_id);

-- ============================================
-- TABLE: driver_locations
-- ============================================
CREATE TABLE IF NOT EXISTS driver_locations (
    driver_id INTEGER PRIMARY KEY REFERENCES drivers(id) ON DELETE CASCADE,
    latitude DECIMAL(10, 8),
    longitude DECIMAL(11, 8),
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================
-- TABLE: driver_documents
-- ============================================
CREATE TABLE IF NOT EXISTS driver_documents (
    doc_id SERIAL PRIMARY KEY,
    driver_id INT REFERENCES drivers(id) ON DELETE CASCADE,
    doc_type VARCHAR(50), -- 'AADHAAR' or 'DRIVING_LICENCE'
    extracted_data JSONB,
    verification_status VARCHAR(20) DEFAULT 'PENDING',
    uploaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create index
CREATE INDEX IF NOT EXISTS idx_driver_docs_driver ON driver_documents(driver_id);

-- ============================================
-- TABLE: driver_wallets
-- ============================================
CREATE TABLE IF NOT EXISTS driver_wallets (
    wallet_id SERIAL PRIMARY KEY,
    driver_id INT UNIQUE REFERENCES drivers(id) ON DELETE CASCADE,
    balance DECIMAL(10,2) DEFAULT 0.00,
    total_earnings DECIMAL(10,2) DEFAULT 0.00,
    last_settled_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create index
CREATE INDEX IF NOT EXISTS idx_driver_wallets_driver ON driver_wallets(driver_id);

-- ============================================
-- TABLE: rides (Core table for all bookings)
-- ============================================
CREATE TABLE IF NOT EXISTS rides (
    id SERIAL PRIMARY KEY,
    customer_phone VARCHAR(20) REFERENCES users(phone),
    driver_id INTEGER REFERENCES drivers(id),
    pickup_lat DECIMAL(10, 8),
    pickup_lng DECIMAL(11, 8),
    pickup_address TEXT,
    drop_lat DECIMAL(10, 8),
    drop_lng DECIMAL(11, 8),
    drop_address TEXT,
    vehicle_type VARCHAR(50),
    distance_km DECIMAL(6,2),
    estimated_fare DECIMAL(8,2),
    driver_earnings DECIMAL(8,2),
    status VARCHAR(50) DEFAULT 'requested',
    -- New columns for pickup/drop tracking
    is_picked_up INTEGER DEFAULT 0,
    is_dropped INTEGER DEFAULT 0,
    -- New columns for passenger gender count
    male_passengers INTEGER DEFAULT 0,
    female_passengers INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for rides
CREATE INDEX IF NOT EXISTS idx_rides_status ON rides(status);
CREATE INDEX IF NOT EXISTS idx_rides_customer ON rides(customer_phone);
CREATE INDEX IF NOT EXISTS idx_rides_driver ON rides(driver_id);
CREATE INDEX IF NOT EXISTS idx_rides_created ON rides(created_at);

-- ============================================
-- TABLE: sos_events (Emergency alerts)
-- ============================================
CREATE TABLE IF NOT EXISTS sos_events (
    id SERIAL PRIMARY KEY,
    ride_id INTEGER REFERENCES rides(id),
    customer_phone VARCHAR(20),
    lat DECIMAL(10, 8),
    lng DECIMAL(11, 8),
    status VARCHAR(50) DEFAULT 'active',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_sos_ride ON sos_events(ride_id);
CREATE INDEX IF NOT EXISTS idx_sos_status ON sos_events(status);

-- ============================================
-- TABLE: emergency_contacts
-- ============================================
CREATE TABLE IF NOT EXISTS emergency_contacts (
    id SERIAL PRIMARY KEY,
    customer_phone VARCHAR(20) REFERENCES users(phone) ON DELETE CASCADE,
    contact_phone VARCHAR(20),
    contact_name VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(customer_phone, contact_phone)
);

-- Create index
CREATE INDEX IF NOT EXISTS idx_emergency_contacts_customer ON emergency_contacts(customer_phone);

-- ============================================
-- SAMPLE DATA INSERTS
-- ============================================

-- Insert Sample Users (Customers)
INSERT INTO users (phone, full_name, gender, email) VALUES
('8310501036', 'Arihant Kochar', 'Male', 'arihant@example.com'),
('9876543210', 'Priya Sharma', 'Female', 'priya@example.com'),
('9743446504', 'Rahul Kumar', 'Male', 'rahul@example.com'),
('8765432109', 'Sneha Patel', 'Female', 'sneha@example.com'),
('9876545896', 'Vikram Singh', 'Male', 'vikram@example.com')
ON CONFLICT (phone) DO NOTHING;

-- Insert Sample Drivers
INSERT INTO drivers (full_name, phone, email, gender, dob, aadhaar_number, driving_licence_number, is_verified, rating, is_active) VALUES
('Rajesh Kumar', '9876543211', 'rajesh.driver@torkk.com', 'Male', '1990-05-15', '123456789012', 'DL1234567890', TRUE, 4.8, TRUE),
('Amit Patel', '9876543212', 'amit.driver@torkk.com', 'Male', '1988-08-22', '123456789013', 'DL1234567891', TRUE, 4.9, TRUE),
('Sunita Devi', '9876543213', 'sunita.driver@torkk.com', 'Female', '1992-03-10', '123456789014', 'DL1234567892', TRUE, 5.0, TRUE),
('Mohammed Ali', '9876543214', 'ali.driver@torkk.com', 'Male', '1985-12-05', '123456789015', 'DL1234567893', TRUE, 4.7, TRUE),
('Lakshmi Naidu', '9876543215', 'lakshmi.driver@torkk.com', 'Female', '1995-07-18', '123456789016', 'DL1234567894', TRUE, 4.9, TRUE)
ON CONFLICT (phone) DO NOTHING;

-- Insert Sample Vehicles
INSERT INTO vehicles (driver_id, vehicle_type, plate_number, model) VALUES
(1, 'Auto', 'KA01AB1234', 'Bajaj RE Auto'),
(2, 'Cab', 'KA02CD5678', 'Maruti Swift Dzire'),
(3, 'Bike', 'KA03EF9012', 'Honda Activa'),
(4, 'Cab', 'KA04GH3456', 'Hyundai i10'),
(5, 'Auto', 'KA05IJ7890', 'Piaggio Ape')
ON CONFLICT (plate_number) DO NOTHING;

-- Insert Sample Driver Locations
INSERT INTO driver_locations (driver_id, latitude, longitude, updated_at) VALUES
(1, 14.4633, 75.9237, NOW()),
(2, 14.4673, 75.9287, NOW()),
(3, 14.4693, 75.9307, NOW()),
(4, 14.4713, 75.9327, NOW()),
(5, 14.4653, 75.9257, NOW())
ON CONFLICT (driver_id) DO UPDATE SET 
    latitude = EXCLUDED.latitude,
    longitude = EXCLUDED.longitude,
    updated_at = EXCLUDED.updated_at;

-- Initialize Driver Wallets
INSERT INTO driver_wallets (driver_id, balance, total_earnings) VALUES
(1, 2500.00, 15000.00),
(2, 3200.00, 22000.00),
(3, 1800.00, 8500.00),
(4, 2900.00, 18000.00),
(5, 2100.00, 12000.00)
ON CONFLICT (driver_id) DO NOTHING;

-- Insert Sample Rides (Completed)
INSERT INTO rides (customer_phone, driver_id, pickup_lat, pickup_lng, pickup_address, drop_lat, drop_lng, drop_address, vehicle_type, distance_km, estimated_fare, driver_earnings, status, is_picked_up, is_dropped, male_passengers, female_passengers, created_at) VALUES
('8310501036', 1, 14.4633, 75.9237, 'MCC B Block, Davangere', 14.4693, 75.9307, 'Saraswathipuram, Davangere', 'cab', 5.2, 120.00, 96.00, 'completed', 1, 1, 1, 0, NOW() - INTERVAL '2 hours'),
('9876543210', 2, 14.4673, 75.9287, 'PJ Extension, Davangere', 14.4733, 75.9347, 'Vidyanagar, Davangere', 'auto', 3.5, 45.00, 36.00, 'completed', 1, 1, 0, 1, NOW() - INTERVAL '3 hours'),
('9743446504', 3, 14.4653, 75.9257, 'Kondajji Road, Davangere', 14.4713, 75.9327, 'Bathi Bus Stand, Davangere', 'auto', 4.1, 55.00, 44.00, 'completed', 1, 1, 1, 0, NOW() - INTERVAL '1 hour'),
('8765432109', 4, 14.4693, 75.9307, 'SS Layout, Davangere', 14.4753, 75.9367, 'University of Davangere, Davangere', 'cab', 6.0, 150.00, 120.00, 'completed', 1, 1, 2, 1, NOW() - INTERVAL '4 hours'),
('9876545896', 5, 14.4713, 75.9327, 'Shamanur Road, Davangere', 14.4643, 75.9247, 'City Hospital, Davangere', 'bike', 2.5, 80.00, 64.00, 'completed', 1, 1, 1, 0, NOW() - INTERVAL '30 minutes');

-- Insert Sample Rides (In Progress)
INSERT INTO rides (customer_phone, driver_id, pickup_lat, pickup_lng, pickup_address, drop_lat, drop_lng, drop_address, vehicle_type, distance_km, estimated_fare, status, is_picked_up, is_dropped, male_passengers, female_passengers) VALUES
('8310501036', 1, 14.4633, 75.9237, 'Railway Station, Davangere', 14.4693, 75.9307, 'Bus Stand, Davangere', 'auto', 3.8, 50.00, 'in_progress', 1, 0, 1, 0),
('9876543210', NULL, 14.4673, 75.9287, 'JP Nagar, Davangere', 14.4733, 75.9347, 'Mall Road, Davangere', 'cab', 5.5, 130.00, 'requested', 0, 0, 2, 1);

-- Insert Sample Emergency Contacts
INSERT INTO emergency_contacts (customer_phone, contact_phone, contact_name) VALUES
('8310501036', '9876543220', 'Ramesh Kochar (Father)'),
('8310501036', '9876543221', 'Sunita Kochar (Mother)'),
('9876543210', '9876543222', 'Rajesh Sharma (Husband)'),
('9743446504', '9876543223', 'Kavita Kumar (Sister)')
ON CONFLICT (customer_phone, contact_phone) DO NOTHING;

-- ============================================
-- VERIFICATION QUERIES
-- ============================================

-- Check all tables
SELECT 'users' as table_name, COUNT(*) as row_count FROM users
UNION ALL
SELECT 'drivers', COUNT(*) FROM drivers
UNION ALL
SELECT 'vehicles', COUNT(*) FROM vehicles
UNION ALL
SELECT 'driver_locations', COUNT(*) FROM driver_locations
UNION ALL
SELECT 'driver_wallets', COUNT(*) FROM driver_wallets
UNION ALL
SELECT 'rides', COUNT(*) FROM rides
UNION ALL
SELECT 'sos_events', COUNT(*) FROM sos_events
UNION ALL
SELECT 'emergency_contacts', COUNT(*) FROM emergency_contacts;

-- ============================================
-- USEFUL QUERIES FOR TESTING
-- ============================================

-- Get all active drivers with their current location
SELECT d.id, d.full_name, d.phone, d.rating, d.is_active,
       dl.latitude, dl.longitude, dl.updated_at
FROM drivers d
LEFT JOIN driver_locations dl ON d.id = dl.driver_id
WHERE d.is_active = TRUE AND d.is_verified = TRUE;

-- Get all completed rides with earnings
SELECT r.id, r.customer_phone, u.full_name as customer_name,
       d.full_name as driver_name, r.vehicle_type,
       r.pickup_address, r.drop_address,
       r.distance_km, r.estimated_fare, r.driver_earnings,
       r.male_passengers, r.female_passengers,
       r.is_picked_up, r.is_dropped, r.status,
       r.created_at
FROM rides r
LEFT JOIN users u ON r.customer_phone = u.phone
LEFT JOIN drivers d ON r.driver_id = d.id
WHERE r.status = 'completed'
ORDER BY r.created_at DESC;

-- Get driver wallet balances
SELECT d.full_name, d.phone, 
       dw.balance, dw.total_earnings, dw.last_settled_at
FROM drivers d
INNER JOIN driver_wallets dw ON d.id = dw.driver_id
ORDER BY dw.total_earnings DESC;

-- Get rides by status
SELECT status, COUNT(*) as count, SUM(estimated_fare) as total_fare
FROM rides
GROUP BY status;

-- Get passenger gender distribution by vehicle type
SELECT vehicle_type,
       SUM(male_passengers) as total_male,
       SUM(female_passengers) as total_female,
       COUNT(*) as total_rides
FROM rides
WHERE status = 'completed'
GROUP BY vehicle_type;

-- ============================================
-- END OF SCHEMA
-- ============================================
