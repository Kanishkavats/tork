-- PostgreSQL Database & Schema Setup for Torkk Backend

-- 1. Create the Database (Run this while connected to the default 'postgres' database)
-- CREATE DATABASE torkk_db;

-- 2. Connect to 'torkk_db' database and run the following queries to create tables:

-- Users Table
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    phone VARCHAR(20) UNIQUE NOT NULL,
    full_name VARCHAR(100),
    email VARCHAR(100),
    gender VARCHAR(10),
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- OTP Verifications Table
CREATE TABLE IF NOT EXISTS otp_verifications (
    phone VARCHAR(20) PRIMARY KEY,
    otp_code VARCHAR(6) NOT NULL,
    expires_at TIMESTAMP NOT NULL,
    verified BOOLEAN DEFAULT FALSE,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
