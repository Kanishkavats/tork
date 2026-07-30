package main

import (
	"bytes"
	"crypto/hmac"
	"crypto/sha256"
	"database/sql"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"math"
	"math/rand"
	"mime/multipart"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/joho/godotenv"
	_ "github.com/lib/pq"
)

// DB connection
var db *sql.DB

// Exotel config
var (
	exotelAPIKey     string
	exotelAPIToken   string
	exotelAccountSID string
	exotelSenderID   string
)

// MSG91 config
var (
	msg91AuthKey    string
	msg91TemplateID string
)

// Razorpay config
var (
	razorpayKeyID     string
	razorpayKeySecret string
)

// Surepass config (Face Liveness + Aadhaar name verification)
var (
	surepassAPIKey  string
	surepassBaseURL string
)


// Models
type OTPRequest struct {
	Phone string `json:"phone"`
}

type OTPResponse struct {
	Status  string `json:"status"`
	Message string `json:"message"`
}

type VerifyRequest struct {
	Phone string `json:"phone"`
	Code  string `json:"code"`
	Name  string `json:"name"`
	Email string `json:"email"`
}

type VerifyResponse struct {
	Status     string `json:"status"`
	Message    string `json:"message"`
	Token      string `json:"token,omitempty"`
	Gender     string `json:"gender,omitempty"`
	Name       string `json:"name,omitempty"`
	Email      string `json:"email,omitempty"`
	IsExisting bool   `json:"is_existing_user"`
}

type CheckPhoneRequest struct {
	Phone string `json:"phone"`
}

type CheckPhoneResponse struct {
	Status string `json:"status"`
	Exists bool   `json:"exists"`
	Gender string `json:"gender,omitempty"`
}

type RegisterRequest struct {
	Name   string `json:"name"`
	Phone  string `json:"phone"`
	Gender string `json:"gender"`
}

type RegisterResponse struct {
	Status  string `json:"status"`
	Message string `json:"message"`
}

type UpdateLocationRequest struct {
	Phone     string  `json:"phone"`
	Latitude  float64 `json:"latitude"`
	Longitude float64 `json:"longitude"`
	Address   string  `json:"address"`
}

// Ride APIs Structs
type RideEstimateRequest struct {
	PickupLat  float64 `json:"pickup_lat"`
	PickupLng  float64 `json:"pickup_lng"`
	DropLat    float64 `json:"drop_lat"`
	DropLng    float64 `json:"drop_lng"`
	Vehicle    string  `json:"vehicle"` // Cab, Auto, Moto
}

type RideRequest struct {
	Phone            string  `json:"phone"`
	PickupLat        float64 `json:"pickup_lat"`
	PickupLng        float64 `json:"pickup_lng"`
	PickupAddress    string  `json:"pickup_address"`
	DropLat          float64 `json:"drop_lat"`
	DropLng          float64 `json:"drop_lng"`
	DropAddress      string  `json:"drop_address"`
	Vehicle          string  `json:"vehicle"`
	DistanceKm       float64 `json:"distance_km"`
	Fare             float64 `json:"fare"`
	MalePassengers   int     `json:"male_passengers"`
	FemalePassengers int     `json:"female_passengers"`
}

type MatchRequest struct {
	RideID int `json:"ride_id"`
}

type SOSRequest struct {
	RideID *int    `json:"ride_id,omitempty"`
	Phone  string  `json:"phone"`
	Lat    float64 `json:"lat"`
	Lng    float64 `json:"lng"`
}

type Contact struct {
	Name  string `json:"name"`
	Phone string `json:"phone"`
}

type SaveContactsRequest struct {
	CustomerPhone string    `json:"customer_phone"`
	Contacts      []Contact `json:"contacts"`
}

// Customer Wallet Structs
type WalletAddMoneyRequest struct {
	Phone  string  `json:"phone"`
	Amount float64 `json:"amount"`
}

type WalletVerifyRequest struct {
	Phone           string  `json:"phone"`
	Amount          float64 `json:"amount"`
	RazorpayPaymentID string `json:"razorpay_payment_id"`
	Description     string  `json:"description"`
}

type WalletPayRideRequest struct {
	Phone  string  `json:"phone"`
	RideID int     `json:"ride_id"`
	Amount float64 `json:"amount"`
}

type PaymentCreateOrderRequest struct {
	RideID int     `json:"ride_id"`
	Amount float64 `json:"amount"`
}

type PaymentVerifyRequest struct {
	RideID             int    `json:"ride_id"`
	RazorpayPaymentID  string `json:"razorpay_payment_id"`
	RazorpayOrderID    string `json:"razorpay_order_id"`
	RazorpaySignature  string `json:"razorpay_signature"`
}

type FaceVerifyRequest struct {
	Phone         string `json:"phone"`
	SelfieBase64  string `json:"selfie_base64"`
}

func initDB() {
	host := getEnv("DB_HOST", "localhost")
	port := getEnv("DB_PORT", "5432")
	user := getEnv("DB_USER", "postgres")
	password := getEnv("DB_PASSWORD", "Sonal@123")
	dbname := getEnv("DB_NAME", "torkk_db")
	sslmode := getEnv("DB_SSLMODE", "disable")

	connStr := fmt.Sprintf("host=%s port=%s user=%s password=%s dbname=%s sslmode=%s", host, port, user, password, dbname, sslmode)

	var err error
	db, err = sql.Open("postgres", connStr)
	if err != nil {
		log.Fatalf("Error opening database connection: %v", err)
	}

	err = db.Ping()
	if err != nil {
		log.Printf("Warning: Database ping failed: %v. Database functionality might be limited.", err)
	} else {
		log.Println("Successfully connected to PostgreSQL database.")
	}

	// Alter users table to support DOB, Aadhaar, and biometric columns dynamically
	alterQuery := `
		ALTER TABLE users 
		ADD COLUMN IF NOT EXISTS dob VARCHAR(50), 
		ADD COLUMN IF NOT EXISTS aadhaar_number VARCHAR(30),
		ADD COLUMN IF NOT EXISTS has_biometric BOOLEAN DEFAULT FALSE,
		ADD COLUMN IF NOT EXISTS biometric_type VARCHAR(20),
		ADD COLUMN IF NOT EXISTS email VARCHAR(255),
		ADD COLUMN IF NOT EXISTS current_latitude DECIMAL(10, 8),
		ADD COLUMN IF NOT EXISTS current_longitude DECIMAL(11, 8),
		ADD COLUMN IF NOT EXISTS current_location_address TEXT,
		ADD COLUMN IF NOT EXISTS current_location_updated_at TIMESTAMP,
		ADD COLUMN IF NOT EXISTS aadhaar_photo_base64 TEXT;
	`
	_, err = db.Exec(alterQuery)
	if err != nil {
		log.Printf("Warning: Failed to execute users table schema upgrades: %v", err)
	} else {
		log.Println("Database schema upgraded with dob and aadhaar_number columns successfully.")
	}

	extendedSchemaQuery := `
		DO $$ 
		BEGIN 
		  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'phone_unique') THEN 
			ALTER TABLE users ADD CONSTRAINT phone_unique UNIQUE (phone); 
		  END IF; 
		END $$;
		
		CREATE TABLE IF NOT EXISTS drivers (
			id SERIAL PRIMARY KEY,
			full_name VARCHAR(100),
			phone VARCHAR(20) UNIQUE NOT NULL,
			email VARCHAR(100),
			gender VARCHAR(20),
			dob VARCHAR(50),
			aadhaar_number VARCHAR(30) UNIQUE,
			driving_licence_number VARCHAR(50) UNIQUE,
			rc_number VARCHAR(50) UNIQUE,
			profile_photo_url TEXT,
			is_verified BOOLEAN DEFAULT FALSE,
			rating DECIMAL(2,1) DEFAULT 5.0,
			is_active BOOLEAN DEFAULT TRUE,
			created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
		);

		-- Alter drivers table in case it was created previously with NOT NULL constraints
		ALTER TABLE drivers ALTER COLUMN full_name DROP NOT NULL;
		ALTER TABLE drivers ADD COLUMN IF NOT EXISTS email VARCHAR(100);
		ALTER TABLE drivers ADD COLUMN IF NOT EXISTS dob VARCHAR(50);
		ALTER TABLE drivers ADD COLUMN IF NOT EXISTS aadhaar_number VARCHAR(30);
		ALTER TABLE drivers ADD COLUMN IF NOT EXISTS driving_licence_number VARCHAR(50);
		ALTER TABLE drivers ADD COLUMN IF NOT EXISTS rc_number VARCHAR(50);
		ALTER TABLE drivers ADD COLUMN IF NOT EXISTS profile_photo_url TEXT;
		ALTER TABLE drivers ADD COLUMN IF NOT EXISTS is_verified BOOLEAN DEFAULT FALSE;
		ALTER TABLE drivers ADD COLUMN IF NOT EXISTS vehicle_type VARCHAR(50);

		CREATE TABLE IF NOT EXISTS vehicles (
			id SERIAL PRIMARY KEY,
			driver_id INTEGER REFERENCES drivers(id),
			vehicle_type VARCHAR(50) NOT NULL,
			plate_number VARCHAR(30) UNIQUE NOT NULL,
			model VARCHAR(100)
		);

		CREATE TABLE IF NOT EXISTS driver_locations (
			driver_id INTEGER PRIMARY KEY REFERENCES drivers(id),
			latitude DECIMAL(10, 8),
			longitude DECIMAL(11, 8),
			updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
		);

		CREATE TABLE IF NOT EXISTS driver_documents (
			doc_id SERIAL PRIMARY KEY,
			driver_id INT REFERENCES drivers(id) ON DELETE CASCADE,
			doc_type VARCHAR(50), -- 'AADHAAR' or 'DRIVING_LICENCE'
			extracted_data JSONB,
			verification_status VARCHAR(20) DEFAULT 'PENDING',
			uploaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
		);

		CREATE TABLE IF NOT EXISTS driver_wallets (
			wallet_id SERIAL PRIMARY KEY,
			driver_id INT UNIQUE REFERENCES drivers(id) ON DELETE CASCADE,
			balance DECIMAL(10,2) DEFAULT 0.00,
			total_earnings DECIMAL(10,2) DEFAULT 0.00,
			last_settled_at TIMESTAMP
		);

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
			transaction_id VARCHAR(100),
			upi_id VARCHAR(100),
			created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
			updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
		);
		
		ALTER TABLE rides ADD COLUMN IF NOT EXISTS driver_earnings DECIMAL(8,2);
		ALTER TABLE rides ADD COLUMN IF NOT EXISTS transaction_id VARCHAR(100);
		ALTER TABLE rides ADD COLUMN IF NOT EXISTS upi_id VARCHAR(100);
		ALTER TABLE rides ADD COLUMN IF NOT EXISTS pickup_otp VARCHAR(10);
		
		CREATE INDEX IF NOT EXISTS idx_rides_status ON rides(status);
		CREATE INDEX IF NOT EXISTS idx_rides_customer ON rides(customer_phone);

		CREATE TABLE IF NOT EXISTS sos_events (
			id SERIAL PRIMARY KEY,
			ride_id INTEGER REFERENCES rides(id),
			customer_phone VARCHAR(20),
			lat DECIMAL(10, 8),
			lng DECIMAL(11, 8),
			status VARCHAR(50) DEFAULT 'active',
			created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
		);
		CREATE TABLE IF NOT EXISTS emergency_contacts (
			id SERIAL PRIMARY KEY,
			customer_phone VARCHAR(20) REFERENCES users(phone),
			contact_phone VARCHAR(20),
			contact_name VARCHAR(100),
			UNIQUE(customer_phone, contact_phone)
		);

		CREATE TABLE IF NOT EXISTS otp_storage (
			phone VARCHAR(20) PRIMARY KEY,
			otp VARCHAR(10) NOT NULL,
			created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
		);
	`
	_, err = db.Exec(extendedSchemaQuery)
	if err != nil {
		log.Printf("Warning: Failed to execute extended schema upgrades: %v", err)
	} else {
		log.Println("Database extended schema upgraded successfully.")
	}

	// Print all users in database log for verification
	rows, queryErr := db.Query("SELECT id, phone, full_name, gender FROM users")
	if queryErr != nil {
		log.Printf("Aadhaar: Error querying users list: %v", queryErr)
	} else {
		defer rows.Close()
		log.Println("--- Current Users in Database ---")
		for rows.Next() {
			var id int
			var phone, name, gender sql.NullString
			rows.Scan(&id, &phone, &name, &gender)
			log.Printf("ID: %d | Phone: %q | Name: %q | Gender: %q", id, phone.String, name.String, gender.String)
		}
		log.Println("---------------------------------")
	}
}

func getEnv(key, fallback string) string {
	if value, exists := os.LookupEnv(key); exists {
		return value
	}
	return fallback
}

func cleanPhone(phone string) string {
	phone = strings.ReplaceAll(phone, " ", "")
	phone = strings.ReplaceAll(phone, "-", "")
	phone = strings.ReplaceAll(phone, "+91", "")
	return strings.TrimSpace(phone)
}

func checkPhoneHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req CheckPhoneRequest
	err := json.NewDecoder(r.Body).Decode(&req)
	if err != nil || req.Phone == "" {
		http.Error(w, "Invalid input data", http.StatusBadRequest)
		return
	}

	phone := cleanPhone(req.Phone)
	var exists bool
	var gender string
	query := "SELECT EXISTS(SELECT 1 FROM users WHERE phone = $1)"
	err = db.QueryRow(query, phone).Scan(&exists)
	if err != nil {
		log.Printf("Error checking phone: %v", err)
		exists = phone == "9876543210"
		gender = "Male"
	}
	if exists && err == nil {
		genderQuery := "SELECT gender FROM users WHERE phone = $1"
		db.QueryRow(genderQuery, phone).Scan(&gender)
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(CheckPhoneResponse{
		Status: "success",
		Exists: exists,
		Gender: gender,
	})
}

func registerHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req RegisterRequest
	err := json.NewDecoder(r.Body).Decode(&req)
	if err != nil || req.Phone == "" || req.Name == "" || req.Gender == "" {
		http.Error(w, "Invalid input data", http.StatusBadRequest)
		return
	}

	phone := cleanPhone(req.Phone)
	query := `
		INSERT INTO users (phone, full_name, gender, created_at)
		VALUES ($1, $2, $3, $4)
		ON CONFLICT (phone)
		DO UPDATE SET full_name = EXCLUDED.full_name, gender = EXCLUDED.gender;
	`
	_, err = db.Exec(query, phone, req.Name, req.Gender, time.Now())
	if err != nil {
		log.Printf("Error registering user: %v", err)
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(RegisterResponse{
			Status:  "error",
			Message: fmt.Sprintf("Failed to register user in database: %v", err),
		})
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(RegisterResponse{
		Status:  "success",
		Message: "User registered successfully",
	})
}

func sendSMSViaExotel(phone, message string) error {
	mobile := "91" + phone
	
	log.Printf("[SMS DEBUG] Attempting to send SMS to phone: %s", mobile)
	log.Printf("[SMS DEBUG] Message content: %s", message)
	log.Printf("[SMS DEBUG] Exotel Account SID: %s", exotelAccountSID)
	log.Printf("[SMS DEBUG] Exotel Sender ID: %s", exotelSenderID)
	log.Printf("[SMS DEBUG] API Key (first 10 chars): %s...", exotelAPIKey[:10])
	
	// Exotel SMS API URL
	apiURL := fmt.Sprintf("https://api.exotel.com/v1/Accounts/%s/Sms/send", exotelAccountSID)
	log.Printf("[SMS DEBUG] API URL: %s", apiURL)
	
	// Build form data
	formData := fmt.Sprintf("From=%s&To=%s&Body=%s", 
		exotelSenderID, mobile, url.QueryEscape(message))
	log.Printf("[SMS DEBUG] Form data: %s", formData)
	
	req, err := http.NewRequest("POST", apiURL, strings.NewReader(formData))
	if err != nil {
		log.Printf("[SMS DEBUG] Failed to create HTTP request: %v", err)
		return fmt.Errorf("failed to create request: %v", err)
	}
	
	req.SetBasicAuth(exotelAPIKey, exotelAPIToken)
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	log.Printf("[SMS DEBUG] Request headers set with Basic Auth")
	
	client := &http.Client{Timeout: 10 * time.Second}
	log.Printf("[SMS DEBUG] Sending HTTP request to Exotel...")
	resp, err := client.Do(req)
	if err != nil {
		log.Printf("[SMS DEBUG] HTTP request failed: %v", err)
		return fmt.Errorf("HTTP request failed: %v", err)
	}
	defer resp.Body.Close()
	
	body, _ := io.ReadAll(resp.Body)
	log.Printf("[SMS DEBUG] Exotel SMS response for %s: Status=%d Body=%s", mobile, resp.StatusCode, string(body))
	
	if resp.StatusCode != 200 {
		log.Printf("[SMS DEBUG] SMS sending FAILED with status %d", resp.StatusCode)
		return fmt.Errorf("SMS failed with status %d: %s", resp.StatusCode, string(body))
	}
	
	log.Printf("[SMS DEBUG] SMS sent SUCCESSFULLY to %s", mobile)
	return nil
}

func maskLast4(s string) string {
	if len(s) <= 4 {
		return s
	}
	return s[len(s)-4:]
}

func sendOTPViaMSG91(phone, otp string) error {
	mobile := "91" + phone

	log.Printf("[SMS DEBUG] Attempting to send OTP via MSG91 to phone: %s", mobile)
	log.Printf("[SMS DEBUG] MSG91 Template ID: %s", msg91TemplateID)

	apiURL := fmt.Sprintf(
		"https://control.msg91.com/api/v5/otp?mobile=%s&authkey=%s&template_id=%s&otp=%s",
		url.QueryEscape(mobile), url.QueryEscape(msg91AuthKey), url.QueryEscape(msg91TemplateID), url.QueryEscape(otp),
	)

	req, err := http.NewRequest("POST", apiURL, strings.NewReader("{}"))
	if err != nil {
		log.Printf("[SMS DEBUG] Failed to create HTTP request: %v", err)
		return fmt.Errorf("failed to create request: %v", err)
	}

	req.Header.Set("Content-Type", "application/json")
	log.Printf("[SMS DEBUG] AuthKey (masked): ...%s", maskLast4(msg91AuthKey))
	log.Printf("[SMS DEBUG] TemplateID: %s", msg91TemplateID)
	log.Printf("[SMS DEBUG] Sending HTTP request to MSG91...")

	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		log.Printf("[SMS DEBUG] HTTP request failed: %v", err)
		return fmt.Errorf("HTTP request failed: %v", err)
	}
	defer resp.Body.Close()

	respBody, _ := io.ReadAll(resp.Body)
	log.Printf("[SMS DEBUG] MSG91 OTP response for %s: Status=%d Body=%s", mobile, resp.StatusCode, string(respBody))

	if resp.StatusCode != http.StatusOK {
		log.Printf("[SMS DEBUG] OTP sending FAILED with status %d", resp.StatusCode)
		return fmt.Errorf("MSG91 returned status %d: %s", resp.StatusCode, string(respBody))
	}

	log.Printf("[SMS DEBUG] OTP sent SUCCESSFULLY via MSG91 to %s", mobile)
	return nil
}

func sendOTPHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req OTPRequest
	err := json.NewDecoder(r.Body).Decode(&req)
	if err != nil || req.Phone == "" {
		http.Error(w, "Invalid input data", http.StatusBadRequest)
		return
	}

	phone := cleanPhone(req.Phone)
	log.Printf("[OTP DEBUG] OTP request received for phone: %s (original: %s)", phone, req.Phone)
	
	// Generate a random 6-digit OTP
	otp := fmt.Sprintf("%06d", rand.Intn(1000000))
	log.Printf("[OTP DEBUG] Generated OTP: %s for phone: %s", otp, phone)
	
	// Send OTP via MSG91
	log.Printf("[OTP DEBUG] Attempting to send OTP via MSG91...")
	err = sendOTPViaMSG91(phone, otp)
	if err != nil {
		log.Printf("[OTP DEBUG] MSG91 OTP Error: %v", err)
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(OTPResponse{Status: "error", Message: "Failed to send OTP"})
		return
	}

	log.Printf("[OTP DEBUG] SMS sent successfully, now storing OTP in database...")
	// Store OTP in database (simplified - in production use Redis with expiry)
	_, err = db.Exec("INSERT INTO otp_storage (phone, otp, created_at) VALUES ($1, $2, $3) ON CONFLICT (phone) DO UPDATE SET otp = EXCLUDED.otp, created_at = EXCLUDED.created_at", 
		phone, otp, time.Now())
	if err != nil {
		log.Printf("[OTP DEBUG] OTP Storage Error: %v", err)
	} else {
		log.Printf("[OTP DEBUG] OTP stored successfully in database")
	}

	log.Printf("[OTP DEBUG] Sending success response to client")
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(OTPResponse{
		Status:  "success",
		Message: "OTP sent successfully",
	})
}

func verifyOTPHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req VerifyRequest
	err := json.NewDecoder(r.Body).Decode(&req)
	if err != nil || req.Phone == "" || req.Code == "" {
		http.Error(w, "Invalid input data", http.StatusBadRequest)
		return
	}

	phone := cleanPhone(req.Phone)

	// Verify OTP from database
	var storedOTP string
	var createdAt time.Time
	otpErr := db.QueryRow("SELECT otp, created_at FROM otp_storage WHERE phone = $1", phone).Scan(&storedOTP, &createdAt)

	isValid := false
	if otpErr == nil {
		// Check if OTP is valid and not expired (10 minutes)
		if time.Since(createdAt) < 10*time.Minute && storedOTP == req.Code {
			isValid = true
		}
	}

	if !isValid {
		log.Printf("OTP: Invalid or expired OTP for phone %s", phone)
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusUnauthorized)
		json.NewEncoder(w).Encode(VerifyResponse{Status: "error", Message: "Invalid or expired OTP"})
		return
	}

	// OTP verified — check if user exists and gets their gender
	var userExists bool
	var existingGender, existingName, existingEmail string
	// A user is only fully "existing" if they have a non-empty full_name.
	checkUserQuery := "SELECT EXISTS(SELECT 1 FROM users WHERE phone = $1 AND full_name IS NOT NULL AND full_name != '')"
	checkErr := db.QueryRow(checkUserQuery, phone).Scan(&userExists)
	if checkErr != nil {
		log.Printf("OTP: Error checking user existence for phone %q: %v", phone, checkErr)
	} else {
		log.Printf("OTP: User existence check for %q -> exists: %t", phone, userExists)
		if userExists {
			genderQuery := "SELECT COALESCE(gender, ''), COALESCE(full_name, ''), COALESCE(email, '') FROM users WHERE phone = $1"
			db.QueryRow(genderQuery, phone).Scan(&existingGender, &existingName, &existingEmail)
			log.Printf("OTP: Existing user: %q, %q, %q", existingName, existingGender, existingEmail)
		} else {
			// New user (or dropped-off user) — insert a placeholder row if it doesn't already exist
			insertUserQuery := `
				INSERT INTO users (phone, full_name, email, gender, created_at) 
				VALUES ($1, $2, $3, $4, $5) 
				ON CONFLICT (phone) DO NOTHING
			`
			_, insertErr := db.Exec(insertUserQuery, phone, req.Name, req.Email, "", time.Now())
			if insertErr != nil {
				log.Printf("OTP: Error inserting new user for phone %q: %v", phone, insertErr)
			} else {
				log.Printf("OTP: New user placeholder handled for phone: %q", phone)
			}
		}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(VerifyResponse{
		Status:     "success",
		Message:    "OTP verified successfully.",
		Token:      "mock-jwt-auth-token-123456",
		Gender:     existingGender,
		Name:       existingName,
		Email:      existingEmail,
		IsExisting: userExists,
	})
}

func verifyAadhaarHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	bodyBytes, err := io.ReadAll(r.Body)
	if err == nil {
		log.Printf("Aadhaar Debug: Raw JSON request body: %s", string(bodyBytes))
		r.Body = io.NopCloser(bytes.NewBuffer(bodyBytes))
	}

	// Accept JSON body with fields
	var req struct {
		Phone              string `json:"phone"`
		FullName           string `json:"full_name"`
		DOB                string `json:"dob"`
		Gender             string `json:"gender"`
		AadhaarNumber      string `json:"aadhaar_number"`
		Email              string `json:"email"`
		AadhaarPhotoBase64 string `json:"aadhaar_photo_base64"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Phone == "" {
		http.Error(w, "Invalid input data", http.StatusBadRequest)
		return
	}

	phone := cleanPhone(req.Phone)
	gender := req.Gender
	if gender != "Male" && gender != "Female" {
		if strings.Contains(strings.ToLower(gender), "female") {
			gender = "Female"
		} else {
			gender = "Male"
		}
	}

	log.Printf("Aadhaar: Received from Flutter OCR -> Name: %s, DOB: %s, Gender: %s, Aadhaar#: %s, Email: %s",
		req.FullName, req.DOB, gender, req.AadhaarNumber, req.Email)

	// Upsert user in database with extracted fields. The Aadhaar photo (when provided)
	// is kept as the reference image for later Face Match verification in the ride flow —
	// only overwritten when a new one is sent, so a blank resubmit doesn't wipe it.
	upsertQuery := `
		INSERT INTO users (phone, full_name, gender, dob, aadhaar_number, email, aadhaar_photo_base64, created_at)
		VALUES ($1, $2, $3, $4, $5, $6, NULLIF($7, ''), $8)
		ON CONFLICT (phone)
		DO UPDATE SET full_name = EXCLUDED.full_name, gender = EXCLUDED.gender, dob = EXCLUDED.dob,
			aadhaar_number = EXCLUDED.aadhaar_number, email = EXCLUDED.email,
			aadhaar_photo_base64 = COALESCE(NULLIF(EXCLUDED.aadhaar_photo_base64, ''), users.aadhaar_photo_base64);
	`
	_, err = db.Exec(upsertQuery, phone, req.FullName, gender, req.DOB, req.AadhaarNumber, req.Email, req.AadhaarPhotoBase64, time.Now())
	if err != nil {
		log.Printf("Aadhaar: Error upserting database for phone %s: %v", phone, err)
		http.Error(w, "Failed to update profile in database", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"status":         "success",
		"message":        "Details saved successfully",
		"gender":         gender,
		"name":           req.FullName,
		"dob":            req.DOB,
		"aadhaar_number": req.AadhaarNumber,
		"email":          req.Email,
	})
}

func enableBiometricHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req struct {
		Phone string `json:"phone"`
		Type  string `json:"type"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Phone == "" {
		http.Error(w, "Invalid input data", http.StatusBadRequest)
		return
	}

	phone := cleanPhone(req.Phone)
	bioType := req.Type
	if bioType == "" {
		bioType = "unknown"
	}
	
	res, err := db.Exec("UPDATE users SET has_biometric = TRUE, biometric_type = $2 WHERE phone = $1", phone, bioType)
	log.Printf("Aadhaar Debug: Attempting to update biometric for phone: '%s' with type: '%s'", phone, bioType)
	if err != nil {
		log.Printf("Aadhaar: Error enabling biometric for phone %s: %v", phone, err)
		http.Error(w, "Failed to enable biometric in database", http.StatusInternalServerError)
		return
	}
	
	rowsAffected, _ := res.RowsAffected()
	if rowsAffected == 0 {
		log.Printf("Aadhaar: No user found for phone %s to enable biometrics", phone)
		http.Error(w, "User not found", http.StatusNotFound)
		return
	}

	log.Printf("Aadhaar: Biometric successfully enabled for user %s", phone)
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"status":  "success",
		"message": "Biometric enabled successfully",
	})
}

// Ride APIs Handlers

func rideEstimateHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	var req RideEstimateRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid input data", http.StatusBadRequest)
		return
	}

	// Mock distance calculation (normally use Google Directions API here)
	distLat := req.DropLat - req.PickupLat
	distLng := req.DropLng - req.PickupLng
	distanceKm := (distLat*distLat + distLng*distLng) * 100 // Rough mock scale
	if distanceKm < 1 {
		distanceKm = 1
	}

	baseFare := 50.0
	perKmRate := 12.0
	if req.Vehicle == "Auto" {
		baseFare = 30.0
		perKmRate = 8.0
	} else if req.Vehicle == "Moto" {
		baseFare = 20.0
		perKmRate = 5.0
	}

	fare := baseFare + (distanceKm * perKmRate)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"status":      "success",
		"distance_km": distanceKm,
		"fare":        fare,
	})
}

func rideRequestHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	var req RideRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Phone == "" {
		http.Error(w, "Invalid input data", http.StatusBadRequest)
		return
	}
	phone := cleanPhone(req.Phone)

	// Ensure the user exists in the users table to satisfy the foreign key constraint on customer_phone
	_, err := db.Exec("INSERT INTO users (phone, full_name, gender, created_at) VALUES ($1, 'Mock Customer', 'Male', NOW()) ON CONFLICT (phone) DO NOTHING", phone)
	if err != nil {
		log.Printf("Ride: Warning, failed to insert mock user: %v", err)
	}

	// Generated exactly once here — this is the only copy of the pickup OTP. The customer
	// app just displays it; the driver app just submits what the customer reads out; this
	// column is the only place it's ever compared against (see driverPickupCustomerHandler).
	pickupOTP := fmt.Sprintf("%04d", rand.Intn(10000))

	var rideID int
	query := `
		INSERT INTO rides (customer_phone, pickup_lat, pickup_lng, pickup_address, drop_lat, drop_lng, drop_address, vehicle_type, distance_km, estimated_fare, male_passengers, female_passengers, status, pickup_otp)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, 'requested', $13)
		RETURNING id
	`
	err = db.QueryRow(query, phone, req.PickupLat, req.PickupLng, req.PickupAddress, req.DropLat, req.DropLng, req.DropAddress, req.Vehicle, req.DistanceKm, req.Fare, req.MalePassengers, req.FemalePassengers, pickupOTP).Scan(&rideID)
	if err != nil {
		log.Printf("Ride: Error inserting ride request: %v", err)
		http.Error(w, "Failed to create ride", http.StatusInternalServerError)
		return
	}

	log.Printf("[DEBUG RIDE REQUEST] Created ride %d - Vehicle: %s, Male: %d, Female: %d", rideID, req.Vehicle, req.MalePassengers, req.FemalePassengers)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"status":     "success",
		"ride_id":    rideID,
		"pickup_otp": pickupOTP,
	})
}

func rideMatchHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	var req MatchRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.RideID == 0 {
		http.Error(w, "Invalid input data", http.StatusBadRequest)
		return
	}

	// Mock finding a driver (normally query driver_locations)
	// For demo, we just assign driver_id = 1 if it exists, or create a fake one on the fly.
	var driverID int
	err := db.QueryRow("SELECT id FROM drivers LIMIT 1").Scan(&driverID)
	if err != nil {
		// Insert a mock driver if none exist
		db.QueryRow("INSERT INTO drivers (full_name, phone) VALUES ('Amit Kumar', '1234567890') RETURNING id").Scan(&driverID)
	}

	_, err = db.Exec("UPDATE rides SET driver_id = $1, status = 'accepted' WHERE id = $2", driverID, req.RideID)
	if err != nil {
		http.Error(w, "Failed to assign driver", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"status":    "success",
		"driver_id": driverID,
	})
}

func rideStatusHandler(w http.ResponseWriter, r *http.Request) {
	rideID := r.URL.Query().Get("ride_id")
	if rideID == "" {
		http.Error(w, "Missing ride_id", http.StatusBadRequest)
		return
	}

	var status string
	var driverID sql.NullInt64
	var isPickedUp, isDropped int
	var pickupOTP sql.NullString
	err := db.QueryRow("SELECT status, driver_id, is_picked_up, is_dropped, pickup_otp FROM rides WHERE id = $1", rideID).Scan(&status, &driverID, &isPickedUp, &isDropped, &pickupOTP)
	if err != nil {
		http.Error(w, "Ride not found", http.StatusNotFound)
		return
	}

	resp := map[string]interface{}{
		"status":       "success",
		"ride_status":  status,
		"is_picked_up": isPickedUp == 1,
		"is_dropped":   isDropped == 1,
	}
	if pickupOTP.Valid {
		resp["pickup_otp"] = pickupOTP.String
	}

	if driverID.Valid {
		var driverName, driverPhone string
		var rating sql.NullFloat64
		db.QueryRow("SELECT full_name, phone, rating FROM drivers WHERE id = $1", driverID.Int64).Scan(&driverName, &driverPhone, &rating)
		resp["driver_name"] = driverName
		resp["driver_phone"] = driverPhone
		if rating.Valid {
			resp["driver_rating"] = rating.Float64
		}

		var plateNumber, model sql.NullString
		db.QueryRow("SELECT plate_number, model FROM vehicles WHERE driver_id = $1", driverID.Int64).Scan(&plateNumber, &model)
		if plateNumber.Valid {
			resp["driver_plate_number"] = plateNumber.String
		} else {
			resp["driver_plate_number"] = ""
		}
		if model.Valid {
			resp["driver_vehicle_model"] = model.String
		} else {
			resp["driver_vehicle_model"] = ""
		}

		var lat, lng sql.NullFloat64
		db.QueryRow("SELECT latitude, longitude FROM driver_locations WHERE driver_id = $1", driverID.Int64).Scan(&lat, &lng)
		if lat.Valid && lng.Valid {
			resp["driver_lat"] = lat.Float64
			resp["driver_lng"] = lng.Float64
		}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}

func ridePaymentHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	var req struct {
		RideID        int    `json:"ride_id"`
		TransactionID string `json:"transaction_id"`
		UpiID         string `json:"upi_id"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.RideID == 0 {
		http.Error(w, "Invalid input data", http.StatusBadRequest)
		return
	}

	_, err := db.Exec("UPDATE rides SET transaction_id = $1, upi_id = $2, status = 'completed', updated_at = NOW() WHERE id = $3", req.TransactionID, req.UpiID, req.RideID)
	if err != nil {
		log.Printf("Error saving payment: %v", err)
		http.Error(w, "Failed to save payment details", http.StatusInternalServerError)
		return
	}

	log.Printf("[DEBUG PAYMENT] Saved payment for ride %d: txn=%s, upi=%s", req.RideID, req.TransactionID, req.UpiID)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{"status": "success", "message": "Payment details saved successfully"})
}

// POST /api/payments/create-order
// Returns order info so Flutter can open Razorpay for a ride payment.
func paymentsCreateOrderHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Access-Control-Allow-Origin", "*")
	if r.Method == http.MethodOptions {
		w.WriteHeader(http.StatusOK)
		return
	}
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	var req PaymentCreateOrderRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.RideID == 0 || req.Amount <= 0 {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(map[string]interface{}{"status": "error", "message": "Invalid request: ride_id and amount required"})
		return
	}

	var rideExists int
	err := db.QueryRow("SELECT id FROM rides WHERE id = $1", req.RideID).Scan(&rideExists)
	if err != nil {
		w.WriteHeader(http.StatusNotFound)
		json.NewEncoder(w).Encode(map[string]interface{}{"status": "error", "message": "Ride not found"})
		return
	}

	if razorpayKeyID == "" || razorpayKeySecret == "" {
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]interface{}{"status": "error", "message": "Payments are not configured"})
		return
	}

	amountPaise := int64(req.Amount * 100)
	orderBody, _ := json.Marshal(map[string]interface{}{
		"amount":   amountPaise,
		"currency": "INR",
		"receipt":  fmt.Sprintf("ride_%d_%d", req.RideID, time.Now().Unix()),
	})

	httpReq, err := http.NewRequest("POST", "https://api.razorpay.com/v1/orders", bytes.NewReader(orderBody))
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]interface{}{"status": "error", "message": "Failed to build order request"})
		return
	}
	httpReq.SetBasicAuth(razorpayKeyID, razorpayKeySecret)
	httpReq.Header.Set("Content-Type", "application/json")

	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(httpReq)
	if err != nil {
		log.Printf("Razorpay order creation error: %v", err)
		w.WriteHeader(http.StatusBadGateway)
		json.NewEncoder(w).Encode(map[string]interface{}{"status": "error", "message": "Failed to reach Razorpay"})
		return
	}
	defer resp.Body.Close()
	respBody, _ := io.ReadAll(resp.Body)

	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusCreated {
		log.Printf("Razorpay order creation failed (status %d): %s", resp.StatusCode, string(respBody))
		w.WriteHeader(http.StatusBadGateway)
		json.NewEncoder(w).Encode(map[string]interface{}{"status": "error", "message": "Razorpay rejected the order request"})
		return
	}

	var rzpOrder struct {
		ID       string `json:"id"`
		Amount   int64  `json:"amount"`
		Currency string `json:"currency"`
	}
	if err := json.Unmarshal(respBody, &rzpOrder); err != nil {
		log.Printf("Razorpay order response parse error: %v | body=%s", err, string(respBody))
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]interface{}{"status": "error", "message": "Invalid response from Razorpay"})
		return
	}

	log.Printf("[DEBUG PAYMENT] Created Razorpay order %s for ride %d, amount_paise=%d", rzpOrder.ID, req.RideID, rzpOrder.Amount)

	json.NewEncoder(w).Encode(map[string]interface{}{
		"status":        "success",
		"order_id":      rzpOrder.ID,
		"amount_paise":  rzpOrder.Amount,
		"amount_rupees": req.Amount,
		"currency":      rzpOrder.Currency,
		"key":           razorpayKeyID,
	})
}

// POST /api/payments/verify
// Called after Razorpay success — marks the ride as paid/completed.
func paymentsVerifyHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Access-Control-Allow-Origin", "*")
	if r.Method == http.MethodOptions {
		w.WriteHeader(http.StatusOK)
		return
	}
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	var req PaymentVerifyRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.RideID == 0 || req.RazorpayPaymentID == "" ||
		req.RazorpayOrderID == "" || req.RazorpaySignature == "" {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(map[string]interface{}{"status": "error", "message": "Invalid request: ride_id, razorpay_payment_id, razorpay_order_id and razorpay_signature required"})
		return
	}

	if razorpayKeySecret == "" {
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]interface{}{"status": "error", "message": "Payments are not configured"})
		return
	}

	payload := req.RazorpayOrderID + "|" + req.RazorpayPaymentID
	mac := hmac.New(sha256.New, []byte(razorpayKeySecret))
	mac.Write([]byte(payload))
	expectedSignature := hex.EncodeToString(mac.Sum(nil))
	if !hmac.Equal([]byte(expectedSignature), []byte(req.RazorpaySignature)) {
		log.Printf("[DEBUG PAYMENT] Signature mismatch for ride %d, order=%s, payment=%s", req.RideID, req.RazorpayOrderID, req.RazorpayPaymentID)
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(map[string]interface{}{"status": "error", "message": "Payment signature verification failed"})
		return
	}

	result, err := db.Exec(
		"UPDATE rides SET transaction_id = $1, upi_id = 'razorpay', status = 'completed', updated_at = NOW() WHERE id = $2",
		req.RazorpayPaymentID, req.RideID,
	)
	if err != nil {
		log.Printf("Error verifying payment for ride %d: %v", req.RideID, err)
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]interface{}{"status": "error", "message": "Failed to save payment"})
		return
	}
	if rows, _ := result.RowsAffected(); rows == 0 {
		w.WriteHeader(http.StatusNotFound)
		json.NewEncoder(w).Encode(map[string]interface{}{"status": "error", "message": "Ride not found"})
		return
	}

	log.Printf("[DEBUG PAYMENT] Verified ride %d payment: razorpay_payment_id=%s order_id=%s", req.RideID, req.RazorpayPaymentID, req.RazorpayOrderID)

	json.NewEncoder(w).Encode(map[string]interface{}{"status": "success", "message": "Payment verified"})
}

const surepassFaceLivenessPath = "/api/v1/ocr/face-liveness-v5"

// POST /api/kyc/verify-liveness
// Called once, right before the customer's first Confirm Ride — runs Surepass Face
// Liveness V5 (single-call, no session/SDK needed) on a live selfie to confirm a real
// person is booking. No Aadhaar reference photo needed; this only checks liveness,
// not identity match.
func livenessVerifyHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Access-Control-Allow-Origin", "*")
	if r.Method == http.MethodOptions {
		w.WriteHeader(http.StatusOK)
		return
	}
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	var req FaceVerifyRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Phone == "" || req.SelfieBase64 == "" {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(map[string]interface{}{"status": "error", "message": "Invalid request: phone and selfie_base64 required"})
		return
	}

	if surepassAPIKey == "" {
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]interface{}{"status": "error", "message": "Face verification is not configured yet"})
		return
	}

	phone := cleanPhone(req.Phone)
	selfieBytes, err := base64.StdEncoding.DecodeString(req.SelfieBase64)
	if err != nil {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(map[string]interface{}{"status": "error", "message": "Invalid selfie image data"})
		return
	}

	var formBody bytes.Buffer
	writer := multipart.NewWriter(&formBody)
	if err := writeMultipartFile(writer, "file", "selfie.jpg", selfieBytes); err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]interface{}{"status": "error", "message": "Failed to build verification request"})
		return
	}
	writer.Close()

	httpReq, err := http.NewRequest("POST", surepassBaseURL+surepassFaceLivenessPath, &formBody)
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]interface{}{"status": "error", "message": "Failed to build verification request"})
		return
	}
	httpReq.Header.Set("Authorization", "Bearer "+surepassAPIKey)
	httpReq.Header.Set("Content-Type", writer.FormDataContentType())

	client := &http.Client{Timeout: 20 * time.Second}
	resp, err := client.Do(httpReq)
	if err != nil {
		log.Printf("[DEBUG KYC] Surepass face-liveness request error for phone=%s: %v", phone, err)
		w.WriteHeader(http.StatusBadGateway)
		json.NewEncoder(w).Encode(map[string]interface{}{"status": "error", "message": "Failed to reach face verification service"})
		return
	}
	defer resp.Body.Close()
	respBody, _ := io.ReadAll(resp.Body)

	var sp struct {
		Data struct {
			ClientID string `json:"client_id"`
			Detail   struct {
				OK      bool    `json:"ok"`
				Live    bool    `json:"live"`
				Verdict string  `json:"verdict"`
				Score   float64 `json:"score"`
				Reason  string  `json:"reason"`
			} `json:"detail"`
		} `json:"data"`
		Message string `json:"message"`
		Success bool   `json:"success"`
	}
	if err := json.Unmarshal(respBody, &sp); err != nil {
		log.Printf("[DEBUG KYC] Surepass face-liveness response parse error for phone=%s: %v | body=%s", phone, err, string(respBody))
		w.WriteHeader(http.StatusBadGateway)
		json.NewEncoder(w).Encode(map[string]interface{}{"status": "error", "message": "Invalid response from face verification service"})
		return
	}

	log.Printf("[DEBUG KYC] Face liveness for phone=%s: success=%v live=%v verdict=%s score=%.3f reason=%s",
		phone, sp.Success, sp.Data.Detail.Live, sp.Data.Detail.Verdict, sp.Data.Detail.Score, sp.Data.Detail.Reason)

	if !sp.Success || !sp.Data.Detail.Live {
		w.WriteHeader(http.StatusBadRequest)
		msg := sp.Message
		if msg == "" {
			msg = "Could not confirm a live face. Please try again in good lighting."
		}
		json.NewEncoder(w).Encode(map[string]interface{}{"status": "error", "message": msg, "confidence": sp.Data.Detail.Score})
		return
	}

	json.NewEncoder(w).Encode(map[string]interface{}{"status": "success", "message": "Liveness verified", "confidence": sp.Data.Detail.Score})
}

func writeMultipartFile(writer *multipart.Writer, field, filename string, data []byte) error {
	part, err := writer.CreateFormFile(field, filename)
	if err != nil {
		return err
	}
	_, err = part.Write(data)
	return err
}

func sosHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	var req SOSRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid input data", http.StatusBadRequest)
		return
	}

	_, err := db.Exec("INSERT INTO sos_events (ride_id, customer_phone, lat, lng) VALUES ($1, $2, $3, $4)", req.RideID, req.Phone, req.Lat, req.Lng)
	if err != nil {
		log.Printf("SOS Error: %v", err)
		http.Error(w, "Failed to log SOS", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"status":  "success",
		"message": "SOS logged",
	})
}

func getContactsHandler(w http.ResponseWriter, r *http.Request) {
	phone := r.URL.Query().Get("phone")
	if phone == "" {
		http.Error(w, "Missing phone", http.StatusBadRequest)
		return
	}

	rows, err := db.Query("SELECT contact_name, contact_phone FROM emergency_contacts WHERE customer_phone = $1", phone)
	if err != nil {
		http.Error(w, "Failed to fetch contacts", http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	var contacts []map[string]interface{}
	for rows.Next() {
		var name, cPhone string
		rows.Scan(&name, &cPhone)
		contacts = append(contacts, map[string]interface{}{
			"name":  name,
			"phone": cPhone,
		})
	}
	
	if contacts == nil {
	    contacts = []map[string]interface{}{} // return empty array instead of null
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"status":   "success",
		"contacts": contacts,
	})
}

func saveContactsHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	var req SaveContactsRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid input data", http.StatusBadRequest)
		return
	}

	// Delete existing and insert new
	db.Exec("DELETE FROM emergency_contacts WHERE customer_phone = $1", req.CustomerPhone)

	for _, c := range req.Contacts {
		if c.Phone != "" {
			db.Exec("INSERT INTO emergency_contacts (customer_phone, contact_phone, contact_name) VALUES ($1, $2, $3)", req.CustomerPhone, c.Phone, c.Name)
		}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"status":  "success",
		"message": "Contacts saved",
	})
}
func rideHistoryHandler(w http.ResponseWriter, r *http.Request) {
	phone := r.URL.Query().Get("phone")
	if phone == "" {
		http.Error(w, "Missing phone", http.StatusBadRequest)
		return
	}
	phone = cleanPhone(phone)

	rows, err := db.Query("SELECT id, pickup_address, drop_address, estimated_fare, status, created_at FROM rides WHERE customer_phone = $1 ORDER BY created_at DESC", phone)
	if err != nil {
		http.Error(w, "Failed to fetch history", http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	var history []map[string]interface{}
	for rows.Next() {
		var id int
		var pickup, drop, status string
		var fare float64
		var createdAt time.Time
		rows.Scan(&id, &pickup, &drop, &fare, &status, &createdAt)
		history = append(history, map[string]interface{}{
			"id":             id,
			"pickup_address": pickup,
			"drop_address":   drop,
			"fare":           fare,
			"status":         status,
			"date":           createdAt.Format(time.RFC3339),
		})
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"status":  "success",
		"history": history,
	})
}

func haversine(lat1, lon1, lat2, lon2 float64) float64 {
	const R = 6371.0 // Earth radius in km
	dLat := (lat2 - lat1) * (math.Pi / 180.0)
	dLon := (lon2 - lon1) * (math.Pi / 180.0)

	a := math.Sin(dLat/2)*math.Sin(dLat/2) +
		math.Cos(lat1*(math.Pi/180.0))*math.Cos(lat2*(math.Pi/180.0))*
			math.Sin(dLon/2)*math.Sin(dLon/2)
	c := 2 * math.Atan2(math.Sqrt(a), math.Sqrt(1-a))

	return R * c
}

func updateLocationHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPatch {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req UpdateLocationRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Phone == "" {
		http.Error(w, "Invalid input data", http.StatusBadRequest)
		return
	}

	phone := cleanPhone(req.Phone)

	var prevLat, prevLng sql.NullFloat64
	err := db.QueryRow("SELECT current_latitude, current_longitude FROM users WHERE phone = $1", phone).Scan(&prevLat, &prevLng)
	if err != nil && err != sql.ErrNoRows {
		http.Error(w, "Database error", http.StatusInternalServerError)
		return
	}

	if err == nil && prevLat.Valid && prevLng.Valid {
		distKm := haversine(prevLat.Float64, prevLng.Float64, req.Latitude, req.Longitude)
		distMeters := distKm * 1000.0
		if distMeters < 1.0 {
			w.Header().Set("Content-Type", "application/json")
			json.NewEncoder(w).Encode(map[string]interface{}{
				"success": true,
				"updated": false,
				"message": "Location unchanged",
			})
			return
		}
	}

	_, err = db.Exec("UPDATE users SET current_latitude = $1, current_longitude = $2, current_location_address = $3, current_location_updated_at = $4 WHERE phone = $5",
		req.Latitude, req.Longitude, req.Address, time.Now(), phone)
	
	if err != nil {
		log.Printf("Location Update Error: %v", err)
		http.Error(w, "Failed to update location", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"success": true,
		"updated": true,
		"message": "Location updated",
	})
}

// --- DRIVER APIs ---

func driverVerifyOTPHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	var req VerifyRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Phone == "" || req.Code == "" {
		http.Error(w, "Invalid input data", http.StatusBadRequest)
		return
	}
	phone := cleanPhone(req.Phone)

	// Verify OTP from database
	var storedOTP string
	var createdAt time.Time
	err := db.QueryRow("SELECT otp, created_at FROM otp_storage WHERE phone = $1", phone).Scan(&storedOTP, &createdAt)

	isValid := false
	if err == nil {
		// Check if OTP is valid and not expired (10 minutes)
		if time.Since(createdAt) < 10*time.Minute && storedOTP == req.Code {
			isValid = true
		}
	}

	if !isValid {
		log.Printf("Driver OTP: Invalid or expired OTP for phone %s", phone)
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusUnauthorized)
		json.NewEncoder(w).Encode(VerifyResponse{Status: "error", Message: "Invalid or expired OTP"})
		return
	}

	var driverExists bool
	var existingGender, existingName, existingEmail string
	// Consider driver existing if they have completed registration (is_verified OR has a full_name)
	checkQuery := "SELECT EXISTS(SELECT 1 FROM drivers WHERE phone = $1 AND (is_verified = true OR (full_name IS NOT NULL AND full_name != '')))"
	db.QueryRow(checkQuery, phone).Scan(&driverExists)
	
	var driverId int
	if driverExists {
		db.QueryRow("SELECT id, COALESCE(gender, ''), COALESCE(full_name, ''), COALESCE(email, '') FROM drivers WHERE phone = $1", phone).Scan(&driverId, &existingGender, &existingName, &existingEmail)
	} else {
		err := db.QueryRow("INSERT INTO drivers (phone, created_at) VALUES ($1, $2) ON CONFLICT (phone) DO UPDATE SET phone=EXCLUDED.phone RETURNING id", phone, time.Now()).Scan(&driverId)
		if err != nil {
			log.Printf("Driver OTP Insert Error: %v", err)
		}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"status": "success",
		"message": "OTP verified successfully.",
		"token": "mock-jwt-driver-token",
		"driver_id": driverId,
		"is_existing_driver": driverExists,
		"gender": existingGender,
		"name": existingName,
		"email": existingEmail,
	})
}

func driverVerifyDLHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"status": "success",
		"extracted": map[string]string{
			"dl_number": "KA01 20260001234",
			"name": "MOCK DRIVER",
			"dob": "15-08-1990",
			"vehicle_class": "MCWG, LMV",
			"valid_till": "14-08-2035",
		},
	})
}

func driverVerifyRCHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"status": "success",
		"extracted": map[string]string{
			"rc_number": "KA01HB1234",
			"owner_name": "MOCK DRIVER",
			"vehicle_number": "KA01HB1234",
			"registration_date": "01-01-2020",
			"valid_till": "31-12-2030",
			"vehicle_class": "MCWG",
			"fuel_type": "PETROL",
			"manufacturer": "HERO",
			"model": "HONDA CBZ",
		},
	})
}

func driverRegisterHandler(w http.ResponseWriter, r *http.Request) {
	log.Printf("Driver Register Endpoint Hit: %s", r.URL.Path)
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	var req struct {
		Phone    string `json:"phone"`
		Name     string `json:"name"`
		Gender   string `json:"gender"`
		Email    string `json:"email"`
		Aadhaar  string `json:"aadhaar_number"`
		DlNumber string `json:"dl_number"`
		RcNumber string `json:"rc_number"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid input data", http.StatusBadRequest)
		return
	}
	phone := cleanPhone(req.Phone)
	// Upsert instead of a plain UPDATE: if OTP verify never ran (e.g. SMS delivery is down and
	// the driver was never inserted into `drivers`), a plain UPDATE would silently affect 0 rows
	// and the driver would never actually exist in the DB despite onboarding looking successful.
	query := `
		INSERT INTO drivers (phone, full_name, gender, email, aadhaar_number, driving_licence_number, rc_number, is_verified, created_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, true, NOW())
		ON CONFLICT (phone) DO UPDATE SET
			full_name = EXCLUDED.full_name,
			gender = EXCLUDED.gender,
			email = EXCLUDED.email,
			aadhaar_number = EXCLUDED.aadhaar_number,
			driving_licence_number = EXCLUDED.driving_licence_number,
			rc_number = EXCLUDED.rc_number,
			is_verified = true
	`
	_, err := db.Exec(query, phone, req.Name, req.Gender, req.Email, req.Aadhaar, req.DlNumber, req.RcNumber)
	if err != nil {
		log.Printf("Driver Register Error: %v", err)
		http.Error(w, "Database error", http.StatusInternalServerError)
		return
	}

	// Create wallet for driver
	var driverID int
	err = db.QueryRow("SELECT id FROM drivers WHERE phone = $1", phone).Scan(&driverID)
	if err == nil {
		_, _ = db.Exec("INSERT INTO driver_wallets (driver_id, balance, total_earnings) VALUES ($1, 0.00, 0.00) ON CONFLICT (driver_id) DO NOTHING", driverID)
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{"status": "success", "message": "Driver profile updated", "driver_id": driverID})
}

func driverCheckPhoneHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	var req struct{ Phone string `json:"phone"` }
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid input data", http.StatusBadRequest)
		return
	}
	phone := cleanPhone(req.Phone)
	var exists bool
	var gender string
	db.QueryRow("SELECT EXISTS(SELECT 1 FROM drivers WHERE phone = $1 AND full_name IS NOT NULL AND full_name != '')", phone).Scan(&exists)
	if exists {
		db.QueryRow("SELECT COALESCE(gender, 'Male') FROM drivers WHERE phone = $1", phone).Scan(&gender)
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{"exists": exists, "gender": gender})
}

func driverActiveRidesHandler(w http.ResponseWriter, r *http.Request) {
	city := r.URL.Query().Get("city")
	driverPhone := cleanPhone(r.URL.Query().Get("driver_phone"))
	var rows *sql.Rows
	var err error

	baseQuery := `
		SELECT r.id, r.customer_phone, u.full_name, r.pickup_lat, r.pickup_lng, r.pickup_address,
		       r.drop_lat, r.drop_lng, r.drop_address, r.vehicle_type, r.distance_km, r.estimated_fare,
		       r.status, r.driver_id
		FROM rides r
		LEFT JOIN users u ON r.customer_phone = u.phone
		WHERE (
			(r.status = 'requested' AND r.driver_id IS NULL)
	`

	if driverPhone != "" {
		var driverID int
		if db.QueryRow("SELECT id FROM drivers WHERE phone = $1", driverPhone).Scan(&driverID) == nil {
			baseQuery += fmt.Sprintf(" OR (r.driver_id = %d AND r.status IN ('accepted', 'in_progress'))", driverID)
		}
	}
	baseQuery += ")"

	if city != "" {
		baseQuery += " AND (r.pickup_address ILIKE $1 OR r.drop_address ILIKE $1 OR $1 = '')"
		baseQuery += " ORDER BY r.created_at DESC LIMIT 50"
		rows, err = db.Query(baseQuery, "%"+city+"%")
	} else {
		baseQuery += " ORDER BY r.created_at DESC LIMIT 50"
		rows, err = db.Query(baseQuery)
	}

	if err != nil {
		log.Printf("Error fetching active rides: %v", err)
		http.Error(w, "Database error", http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	rides := []map[string]interface{}{}
	for rows.Next() {
		var id int
		var custPhone string
		var pickupAddrNull, dropAddrNull, vehicleTypeNull, statusNull, customerNameNull sql.NullString
		var pLatNull, pLngNull, dLatNull, dLngNull, distanceNull, fareNull sql.NullFloat64
		var driverID sql.NullInt64

		err := rows.Scan(
			&id, &custPhone, &customerNameNull, 
			&pLatNull, &pLngNull, &pickupAddrNull, 
			&dLatNull, &dLngNull, &dropAddrNull, 
			&vehicleTypeNull, &distanceNull, &fareNull, 
			&statusNull, &driverID,
		)
		if err != nil {
			log.Printf("Scan error: %v", err)
			continue
		}

		custName := "Customer"
		if customerNameNull.Valid && customerNameNull.String != "" {
			custName = customerNameNull.String
		}

		rideMap := map[string]interface{}{
			"id":               id,
			"customer_phone":   custPhone,
			"customer_name":    custName,
			"pickup_lat":       pLatNull.Float64,
			"pickup_lng":       pLngNull.Float64,
			"pickup_address":   pickupAddrNull.String,
			"drop_lat":         dLatNull.Float64,
			"drop_lng":         dLngNull.Float64,
			"drop_address":     dropAddrNull.String,
			"vehicle_type":     vehicleTypeNull.String,
			"distance_km":      distanceNull.Float64,
			"estimated_fare":   fareNull.Float64,
			"status":           statusNull.String,
		}
		if driverID.Valid {
			rideMap["driver_id"] = driverID.Int64
		} else {
			rideMap["driver_id"] = nil
		}
		rides = append(rides, rideMap)
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(rides)
}

func driverUpdateLocationHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	var req struct {
		Phone     string  `json:"phone"`
		Latitude  float64 `json:"latitude"`
		Longitude float64 `json:"longitude"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Phone == "" {
		http.Error(w, "Invalid input data", http.StatusBadRequest)
		return
	}

	phone := cleanPhone(req.Phone)
	var driverID int
	err := db.QueryRow("SELECT id FROM drivers WHERE phone = $1", phone).Scan(&driverID)
	if err != nil {
		http.Error(w, "Driver not found", http.StatusNotFound)
		return
	}

	query := `
		INSERT INTO driver_locations (driver_id, latitude, longitude, updated_at)
		VALUES ($1, $2, $3, NOW())
		ON CONFLICT (driver_id)
		DO UPDATE SET latitude = EXCLUDED.latitude, longitude = EXCLUDED.longitude, updated_at = NOW();
	`
	_, err = db.Exec(query, driverID, req.Latitude, req.Longitude)
	if err != nil {
		log.Printf("Error saving driver location: %v", err)
		http.Error(w, "Database error", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{"status": "success", "message": "Driver location updated"})
}

func driverAcceptRideHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	var req struct {
		RideID      int    `json:"ride_id"`
		DriverPhone string `json:"driver_phone"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid input data", http.StatusBadRequest)
		return
	}

	phone := cleanPhone(req.DriverPhone)
	var driverID int
	err := db.QueryRow("SELECT id FROM drivers WHERE phone = $1", phone).Scan(&driverID)
	if err != nil {
		log.Printf("Driver not found for phone %s: %v", phone, err)
		http.Error(w, "Driver not registered", http.StatusBadRequest)
		return
	}

	tx, err := db.Begin()
	if err != nil {
		http.Error(w, "DB error", http.StatusInternalServerError)
		return
	}
	defer tx.Rollback()

	var currentStatus string
	var currentDriver sql.NullInt64
	err = tx.QueryRow("SELECT status, driver_id FROM rides WHERE id = $1 FOR UPDATE", req.RideID).Scan(&currentStatus, &currentDriver)
	if err != nil {
		http.Error(w, "Ride not found", http.StatusNotFound)
		return
	}

	if currentStatus != "requested" || currentDriver.Valid {
		tx.Commit()
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusConflict)
		json.NewEncoder(w).Encode(map[string]interface{}{
			"status":  "error",
			"message": "Ride already accepted by someone else",
		})
		return
	}

	_, err = tx.Exec("UPDATE rides SET driver_id = $1, status = 'accepted', updated_at = NOW() WHERE id = $2", driverID, req.RideID)
	if err != nil {
		log.Printf("Error accepting ride: %v", err)
		http.Error(w, "Failed to accept ride", http.StatusInternalServerError)
		return
	}

	err = tx.Commit()
	if err != nil {
		http.Error(w, "DB error", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"status":  "success",
		"message": "Ride accepted successfully",
		"ride_id": req.RideID,
	})
}

func driverStartRideHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	var req struct {
		RideID      int    `json:"ride_id"`
		DriverPhone string `json:"driver_phone"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid input data", http.StatusBadRequest)
		return
	}

	phone := cleanPhone(req.DriverPhone)
	log.Printf("[DEBUG START RIDE] Driver phone: %s, Ride ID: %d", phone, req.RideID)
	
	var driverID int
	err := db.QueryRow("SELECT id FROM drivers WHERE phone = $1", phone).Scan(&driverID)
	if err != nil {
		log.Printf("[DEBUG START RIDE] Driver not found: %v", err)
		http.Error(w, "Driver not found", http.StatusNotFound)
		return
	}

	result, err := db.Exec("UPDATE rides SET status = 'in_progress', updated_at = NOW() WHERE id = $1 AND driver_id = $2 AND status = 'accepted'", req.RideID, driverID)
	if err != nil {
		log.Printf("[DEBUG START RIDE] Update failed: %v", err)
		http.Error(w, "Failed to start ride", http.StatusInternalServerError)
		return
	}
	rows, _ := result.RowsAffected()
	if rows == 0 {
		log.Printf("[DEBUG START RIDE] No rows affected - ride not in accepted state")
		http.Error(w, "Ride not found or not in accepted state", http.StatusBadRequest)
		return
	}

	log.Printf("[DEBUG START RIDE] Ride %d started successfully for driver %d", req.RideID, driverID)
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"status":  "success",
		"message": "Ride started, navigation active",
	})
}

func driverPickupCustomerHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	var req struct {
		RideID      int    `json:"ride_id"`
		DriverPhone string `json:"driver_phone"`
		Code        string `json:"code"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid input data", http.StatusBadRequest)
		return
	}

	phone := cleanPhone(req.DriverPhone)
	log.Printf("[DEBUG PICKUP CUSTOMER] Driver phone: %s, Ride ID: %d", phone, req.RideID)

	var driverID int
	err := db.QueryRow("SELECT id FROM drivers WHERE phone = $1", phone).Scan(&driverID)
	if err != nil {
		log.Printf("[DEBUG PICKUP CUSTOMER] Driver not found: %v", err)
		http.Error(w, "Driver not found", http.StatusNotFound)
		return
	}

	// Only mark picked up if the driver-entered code matches the OTP the customer app
	// displayed (the single stored copy from rideRequestHandler) — this is the only place
	// that ever compares the two.
	result, err := db.Exec("UPDATE rides SET is_picked_up = 1, updated_at = NOW() WHERE id = $1 AND driver_id = $2 AND status = 'in_progress' AND pickup_otp = $3", req.RideID, driverID, req.Code)
	if err != nil {
		log.Printf("[DEBUG PICKUP CUSTOMER] Update failed: %v", err)
		http.Error(w, "Failed to update pickup status", http.StatusInternalServerError)
		return
	}
	rows, _ := result.RowsAffected()
	if rows == 0 {
		log.Printf("[DEBUG PICKUP CUSTOMER] No rows affected - wrong OTP or ride not in in_progress state")
		http.Error(w, "Invalid code, or ride not found/not in progress", http.StatusBadRequest)
		return
	}

	log.Printf("[DEBUG PICKUP CUSTOMER] Customer picked up for ride %d, is_picked_up = 1", req.RideID)
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"status":  "success",
		"message": "Customer picked up, heading to drop location",
	})
}

func driverCompleteRideHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	var req struct {
		RideID      int    `json:"ride_id"`
		DriverPhone string `json:"driver_phone"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid input data", http.StatusBadRequest)
		return
	}

	phone := cleanPhone(req.DriverPhone)
	log.Printf("[DEBUG COMPLETE RIDE] Driver phone: %s, Ride ID: %d", phone, req.RideID)
	
	var driverID int
	err := db.QueryRow("SELECT id FROM drivers WHERE phone = $1", phone).Scan(&driverID)
	if err != nil {
		log.Printf("[DEBUG COMPLETE RIDE] Driver not found: %v", err)
		http.Error(w, "Driver not found", http.StatusNotFound)
		return
	}

	tx, err := db.Begin()
	if err != nil {
		http.Error(w, "DB error", http.StatusInternalServerError)
		return
	}
	defer tx.Rollback()

	var fare float64
	var currentStatus string
	err = tx.QueryRow("SELECT estimated_fare, status FROM rides WHERE id = $1 AND driver_id = $2", req.RideID, driverID).Scan(&fare, &currentStatus)
	if err != nil {
		log.Printf("[DEBUG COMPLETE RIDE] Ride not found: %v", err)
		http.Error(w, "Ride not found", http.StatusNotFound)
		return
	}

	log.Printf("[DEBUG COMPLETE RIDE] Current status: %s, Fare: %.2f", currentStatus, fare)

	if currentStatus == "completed" {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"status":  "success",
			"message": "Ride already completed",
		})
		return
	}

	driverEarnings := math.Round(fare*0.80*100) / 100

	_, err = tx.Exec("UPDATE rides SET status = 'completed', is_dropped = 1, driver_earnings = $1, updated_at = NOW() WHERE id = $2", driverEarnings, req.RideID)
	if err != nil {
		log.Printf("[DEBUG COMPLETE RIDE] Update failed: %v", err)
		http.Error(w, "Failed to complete ride", http.StatusInternalServerError)
		return
	}

	_, err = tx.Exec(`
		INSERT INTO driver_wallets (driver_id, balance, total_earnings)
		VALUES ($1, $2, $2)
		ON CONFLICT (driver_id)
		DO UPDATE SET
			balance = driver_wallets.balance + EXCLUDED.balance,
			total_earnings = driver_wallets.total_earnings + EXCLUDED.total_earnings,
			last_settled_at = NOW()
	`, driverID, driverEarnings)
	if err != nil {
		log.Printf("[DEBUG COMPLETE RIDE] Wallet update error: %v", err)
		http.Error(w, "Failed to update wallet", http.StatusInternalServerError)
		return
	}

	err = tx.Commit()
	if err != nil {
		log.Printf("[DEBUG COMPLETE RIDE] Commit failed: %v", err)
		http.Error(w, "DB error", http.StatusInternalServerError)
		return
	}

	log.Printf("[DEBUG COMPLETE RIDE] Ride %d completed, earnings: %.2f added to driver %d wallet", req.RideID, driverEarnings, driverID)
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"status":          "success",
		"message":         "Trip completed, earnings credited to wallet",
		"driver_earnings": driverEarnings,
		"fare":            fare,
	})
}

func driverTripHistoryHandler(w http.ResponseWriter, r *http.Request) {
	phone := cleanPhone(r.URL.Query().Get("phone"))
	log.Printf("[DEBUG TRIP HISTORY] Request received for phone: %s", phone)
	
	if phone == "" {
		log.Printf("[DEBUG TRIP HISTORY] ERROR: Missing phone parameter")
		http.Error(w, "Missing phone", http.StatusBadRequest)
		return
	}

	var driverID int
	err := db.QueryRow("SELECT id FROM drivers WHERE phone = $1", phone).Scan(&driverID)
	if err != nil {
		log.Printf("[DEBUG TRIP HISTORY] ERROR: Driver not found for phone %s: %v", phone, err)
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"status": "success",
			"trips":  []map[string]interface{}{},
		})
		return
	}
	log.Printf("[DEBUG TRIP HISTORY] Found driver_id: %d for phone: %s", driverID, phone)

	// First, check total rides for this driver in database
	var totalRides int
	db.QueryRow("SELECT COUNT(*) FROM rides WHERE driver_id = $1", driverID).Scan(&totalRides)
	log.Printf("[DEBUG TRIP HISTORY] Total rides for driver_id %d: %d", driverID, totalRides)

	// Check Davangere specific rides
	var davanagereRides int
	db.QueryRow(`SELECT COUNT(*) FROM rides WHERE driver_id = $1 AND 
		(pickup_address ILIKE '%davangere%' OR drop_address ILIKE '%davangere%')`, driverID).Scan(&davanagereRides)
	log.Printf("[DEBUG TRIP HISTORY] Davangere rides for driver_id %d: %d", driverID, davanagereRides)

	rows, err := db.Query(`
		SELECT r.id, r.pickup_address, r.drop_address, r.estimated_fare,
		       COALESCE(r.driver_earnings, r.estimated_fare * 0.8), r.status, r.created_at,
		       u.full_name, r.vehicle_type, r.distance_km
		FROM rides r
		LEFT JOIN users u ON r.customer_phone = u.phone
		WHERE r.driver_id = $1 AND r.status = 'completed'
		ORDER BY r.created_at DESC
		LIMIT 100
	`, driverID)
	if err != nil {
		log.Printf("[DEBUG TRIP HISTORY] ERROR: Query failed: %v", err)
		http.Error(w, "Failed to fetch trips", http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	trips := []map[string]interface{}{}
	tripCount := 0
	davanagereCount := 0
	for rows.Next() {
		var id int
		var pickup, drop, status, customerName, vehicleType sql.NullString
		var fare, earnings, distance sql.NullFloat64
		var createdAt time.Time
		rows.Scan(&id, &pickup, &drop, &fare, &earnings, &status, &createdAt, &customerName, &vehicleType, &distance)
		
		tripCount++
		isDavangere := false
		pickupAddr := pickup.String
		dropAddr := drop.String
		
		if pickup.Valid && (strings.Contains(strings.ToLower(pickupAddr), "davangere") || 
			strings.Contains(strings.ToLower(dropAddr), "davangere")) {
			isDavangere = true
			davanagereCount++
		}
		
		log.Printf("[DEBUG TRIP HISTORY] Trip #%d - ID: %d, Status: %s, Pickup: %s, Drop: %s, Davangere: %v", 
			tripCount, id, status.String, pickupAddr, dropAddr, isDavangere)
		
		trips = append(trips, map[string]interface{}{
			"id":             id,
			"pickup_address": pickup.String,
			"drop_address":   drop.String,
			"fare":           fare.Float64,
			"driver_earnings": earnings.Float64,
			"status":         status.String,
			"date":           createdAt.Format(time.RFC3339),
			"customer_name":  customerName.String,
			"vehicle_type":   vehicleType.String,
			"distance_km":    distance.Float64,
		})
	}
	
	log.Printf("[DEBUG TRIP HISTORY] Query returned %d total trips, %d from Davangere", tripCount, davanagereCount)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"status": "success",
		"trips":  trips,
	})
}

func driverEarningsHandler(w http.ResponseWriter, r *http.Request) {
	phone := cleanPhone(r.URL.Query().Get("phone"))
	log.Printf("[DEBUG EARNINGS] Request received for phone: %s", phone)
	
	if phone == "" {
		log.Printf("[DEBUG EARNINGS] ERROR: Missing phone parameter")
		http.Error(w, "Missing phone", http.StatusBadRequest)
		return
	}

	var driverID int
	var rating sql.NullFloat64
	err := db.QueryRow("SELECT id, rating FROM drivers WHERE phone = $1", phone).Scan(&driverID, &rating)
	if err != nil {
		log.Printf("[DEBUG EARNINGS] ERROR: Driver not found for phone %s: %v", phone, err)
		http.Error(w, "Driver not found", http.StatusNotFound)
		return
	}
	log.Printf("[DEBUG EARNINGS] Found driver_id: %d for phone: %s", driverID, phone)

	var todayEarnings, totalEarnings, weekEarnings float64
	var todayTrips, totalTrips int

	db.QueryRow(`
		SELECT COALESCE(SUM(driver_earnings), 0), COUNT(*)
		FROM rides WHERE driver_id = $1 AND status = 'completed' AND created_at >= CURRENT_DATE
	`, driverID).Scan(&todayEarnings, &todayTrips)
	log.Printf("[DEBUG EARNINGS] Today: %.2f earnings, %d trips", todayEarnings, todayTrips)

	db.QueryRow(`
		SELECT COALESCE(SUM(driver_earnings), 0), COUNT(*)
		FROM rides WHERE driver_id = $1 AND status = 'completed'
	`, driverID).Scan(&totalEarnings, &totalTrips)
	log.Printf("[DEBUG EARNINGS] Total: %.2f earnings, %d trips", totalEarnings, totalTrips)

	db.QueryRow(`
		SELECT COALESCE(SUM(driver_earnings), 0)
		FROM rides WHERE driver_id = $1 AND status = 'completed' AND created_at >= CURRENT_DATE - INTERVAL '7 days'
	`, driverID).Scan(&weekEarnings)
	log.Printf("[DEBUG EARNINGS] Week: %.2f earnings", weekEarnings)

	rows, err := db.Query(`
		SELECT r.id, COALESCE(r.driver_earnings, 0), r.created_at, u.full_name
		FROM rides r
		LEFT JOIN users u ON r.customer_phone = u.phone
		WHERE r.driver_id = $1 AND r.status = 'completed'
		ORDER BY r.created_at DESC LIMIT 20
	`, driverID)

	recentTrips := []map[string]interface{}{}
	if err == nil {
		defer rows.Close()
		recentCount := 0
		for rows.Next() {
			var id int
			var earnings float64
			var createdAt time.Time
			var customerName sql.NullString
			rows.Scan(&id, &earnings, &createdAt, &customerName)
			recentCount++
			log.Printf("[DEBUG EARNINGS] Recent trip #%d - ID: %d, Earnings: %.2f, Customer: %s", 
				recentCount, id, earnings, customerName.String)
			recentTrips = append(recentTrips, map[string]interface{}{
				"id":            id,
				"earnings":      earnings,
				"customer_name": customerName.String,
				"date":          createdAt.Format(time.RFC3339),
			})
		}
		log.Printf("[DEBUG EARNINGS] Total recent trips: %d", recentCount)
	} else {
		log.Printf("[DEBUG EARNINGS] ERROR: Failed to fetch recent trips: %v", err)
	}

	driverRating := 5.0
	if rating.Valid {
		driverRating = rating.Float64
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"status":         "success",
		"today_earnings": todayEarnings,
		"week_earnings":  weekEarnings,
		"total_earnings": totalEarnings,
		"today_trips":    todayTrips,
		"total_trips":    totalTrips,
		"rating":         driverRating,
		"recent_trips":   recentTrips,
	})
}

// ─── Customer Wallet Handlers ────────────────────────────────────

// ensureCustomerWallet creates wallet if not exists, returns wallet id and balance
func ensureCustomerWallet(phone string) (int, float64, error) {
	var walletID int
	var balance float64
	err := db.QueryRow("SELECT id, balance FROM customer_wallets WHERE customer_phone = $1", phone).Scan(&walletID, &balance)
	if err == sql.ErrNoRows {
		err = db.QueryRow(
			"INSERT INTO customer_wallets (customer_phone, balance) VALUES ($1, 0) ON CONFLICT (customer_phone) DO UPDATE SET updated_at=NOW() RETURNING id, balance",
			phone,
		).Scan(&walletID, &balance)
	}
	return walletID, balance, err
}

// GET /api/wallet/balance?phone=xxx
func customerWalletBalanceHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Access-Control-Allow-Origin", "*")
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	phone := cleanPhone(r.URL.Query().Get("phone"))
	if phone == "" {
		json.NewEncoder(w).Encode(map[string]interface{}{"status": "error", "message": "Missing phone"})
		return
	}
	_, balance, err := ensureCustomerWallet(phone)
	if err != nil {
		log.Printf("Wallet balance error for %s: %v", phone, err)
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]interface{}{"status": "error", "message": "Failed to fetch wallet"})
		return
	}
	json.NewEncoder(w).Encode(map[string]interface{}{
		"status":  "success",
		"balance": balance,
	})
}

// GET /api/wallet/transactions?phone=xxx&limit=20
func customerWalletTransactionsHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Access-Control-Allow-Origin", "*")
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	phone := cleanPhone(r.URL.Query().Get("phone"))
	if phone == "" {
		json.NewEncoder(w).Encode(map[string]interface{}{"status": "error", "message": "Missing phone"})
		return
	}

	// Auto-create wallet if needed
	_, _, err := ensureCustomerWallet(phone)
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]interface{}{"status": "error", "message": "Wallet error"})
		return
	}

	rows, err := db.Query(
		`SELECT id, type, amount, balance_after, description, COALESCE(razorpay_payment_id,''), status, created_at
		 FROM customer_wallet_transactions
		 WHERE customer_phone = $1
		 ORDER BY created_at DESC LIMIT 30`,
		phone,
	)
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]interface{}{"status": "error", "message": "Failed to fetch transactions"})
		return
	}
	defer rows.Close()

	type TxRow struct {
		ID           int     `json:"id"`
		Type         string  `json:"type"`
		Amount       float64 `json:"amount"`
		BalanceAfter float64 `json:"balance_after"`
		Description  string  `json:"description"`
		PaymentID    string  `json:"razorpay_payment_id"`
		Status       string  `json:"status"`
		CreatedAt    string  `json:"created_at"`
	}

	var transactions []TxRow
	for rows.Next() {
		var tx TxRow
		var createdAt interface{}
		if err := rows.Scan(&tx.ID, &tx.Type, &tx.Amount, &tx.BalanceAfter, &tx.Description, &tx.PaymentID, &tx.Status, &createdAt); err != nil {
			continue
		}
		if t, ok := createdAt.(time.Time); ok {
			tx.CreatedAt = t.Format(time.RFC3339)
		}
		transactions = append(transactions, tx)
	}
	if transactions == nil {
		transactions = []TxRow{}
	}
	json.NewEncoder(w).Encode(map[string]interface{}{
		"status":       "success",
		"transactions": transactions,
	})
}

// POST /api/wallet/add-money
// Creates a Razorpay order (or just returns order info for client-side payment)
func customerWalletAddMoneyHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Access-Control-Allow-Origin", "*")
	if r.Method == http.MethodOptions {
		w.WriteHeader(http.StatusOK)
		return
	}
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	var req WalletAddMoneyRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Phone == "" || req.Amount <= 0 {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(map[string]interface{}{"status": "error", "message": "Invalid request: phone and amount required"})
		return
	}
	phone := cleanPhone(req.Phone)

	// Ensure wallet exists
	_, balance, err := ensureCustomerWallet(phone)
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]interface{}{"status": "error", "message": "Wallet error"})
		return
	}

	// Return order details so Flutter can open Razorpay
	// Amount in paise for Razorpay
	amountPaise := int64(req.Amount * 100)
	orderID := fmt.Sprintf("order_%d_%s", time.Now().UnixNano(), phone[len(phone)-4:])

	json.NewEncoder(w).Encode(map[string]interface{}{
		"status":          "success",
		"order_id":        orderID,
		"amount_paise":    amountPaise,
		"amount_rupees":   req.Amount,
		"current_balance": balance,
		"currency":        "INR",
	})
}

// POST /api/wallet/verify-payment
// Called after Razorpay success — credits the wallet
func customerWalletVerifyPaymentHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Access-Control-Allow-Origin", "*")
	if r.Method == http.MethodOptions {
		w.WriteHeader(http.StatusOK)
		return
	}
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	var req WalletVerifyRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Phone == "" || req.Amount <= 0 {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(map[string]interface{}{"status": "error", "message": "Invalid request"})
		return
	}
	phone := cleanPhone(req.Phone)

	// Get current balance
	walletID, currentBalance, err := ensureCustomerWallet(phone)
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]interface{}{"status": "error", "message": "Wallet error"})
		return
	}

	newBalance := currentBalance + req.Amount
	desc := req.Description
	if desc == "" {
		desc = fmt.Sprintf("Added ₹%.0f via Razorpay", req.Amount)
	}

	// Update balance and insert transaction atomically
	tx, err := db.Begin()
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]interface{}{"status": "error", "message": "DB error"})
		return
	}

	_, err = tx.Exec("UPDATE customer_wallets SET balance = $1, updated_at = NOW() WHERE id = $2", newBalance, walletID)
	if err != nil {
		tx.Rollback()
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]interface{}{"status": "error", "message": "Failed to update balance"})
		return
	}

	_, err = tx.Exec(
		`INSERT INTO customer_wallet_transactions
		 (customer_phone, type, amount, balance_after, description, razorpay_payment_id, status)
		 VALUES ($1, 'credit', $2, $3, $4, $5, 'completed')`,
		phone, req.Amount, newBalance, desc, req.RazorpayPaymentID,
	)
	if err != nil {
		tx.Rollback()
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]interface{}{"status": "error", "message": "Failed to save transaction"})
		return
	}

	if err = tx.Commit(); err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]interface{}{"status": "error", "message": "Commit error"})
		return
	}

	log.Printf("Wallet credited: phone=%s amount=%.2f new_balance=%.2f payment_id=%s", phone, req.Amount, newBalance, req.RazorpayPaymentID)

	json.NewEncoder(w).Encode(map[string]interface{}{
		"status":      "success",
		"message":     fmt.Sprintf("₹%.0f added to wallet", req.Amount),
		"new_balance": newBalance,
		"amount":      req.Amount,
	})
}

// POST /api/wallet/pay-ride
// Deduct wallet balance for ride payment
func customerWalletPayRideHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Access-Control-Allow-Origin", "*")
	if r.Method == http.MethodOptions {
		w.WriteHeader(http.StatusOK)
		return
	}
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	var req WalletPayRideRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Phone == "" || req.Amount <= 0 {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(map[string]interface{}{"status": "error", "message": "Invalid request"})
		return
	}
	phone := cleanPhone(req.Phone)

	walletID, currentBalance, err := ensureCustomerWallet(phone)
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]interface{}{"status": "error", "message": "Wallet error"})
		return
	}

	if currentBalance < req.Amount {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(map[string]interface{}{"status": "error", "message": "Insufficient wallet balance", "balance": currentBalance})
		return
	}

	newBalance := currentBalance - req.Amount
	desc := fmt.Sprintf("Ride #%d payment", req.RideID)

	txn, err := db.Begin()
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]interface{}{"status": "error", "message": "DB error"})
		return
	}

	_, err = txn.Exec("UPDATE customer_wallets SET balance = $1, updated_at = NOW() WHERE id = $2", newBalance, walletID)
	if err != nil {
		txn.Rollback()
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]interface{}{"status": "error", "message": "Failed to update balance"})
		return
	}

	_, err = txn.Exec(
		`INSERT INTO customer_wallet_transactions
		 (customer_phone, type, amount, balance_after, description, status)
		 VALUES ($1, 'debit', $2, $3, $4, 'completed')`,
		phone, req.Amount, newBalance, desc,
	)
	if err != nil {
		txn.Rollback()
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]interface{}{"status": "error", "message": "Failed to save transaction"})
		return
	}

	if err = txn.Commit(); err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]interface{}{"status": "error", "message": "Commit error"})
		return
	}

	log.Printf("Wallet debited: phone=%s ride=%d amount=%.2f new_balance=%.2f", phone, req.RideID, req.Amount, newBalance)

	json.NewEncoder(w).Encode(map[string]interface{}{
		"status":      "success",
		"message":     "Ride payment successful",
		"new_balance": newBalance,
		"amount":      req.Amount,
	})
}

func driverWalletHandler(w http.ResponseWriter, r *http.Request) {
	phone := cleanPhone(r.URL.Query().Get("phone"))
	if phone == "" {
		http.Error(w, "Missing phone", http.StatusBadRequest)
		return
	}

	var driverID int
	err := db.QueryRow("SELECT id FROM drivers WHERE phone = $1", phone).Scan(&driverID)
	if err != nil {
		http.Error(w, "Driver not found", http.StatusNotFound)
		return
	}

	var balance, totalEarnings sql.NullFloat64
	err = db.QueryRow("SELECT balance, total_earnings FROM driver_wallets WHERE driver_id = $1", driverID).Scan(&balance, &totalEarnings)
	if err == sql.ErrNoRows {
		_, _ = db.Exec("INSERT INTO driver_wallets (driver_id, balance, total_earnings) VALUES ($1, 0, 0)", driverID)
		balance = sql.NullFloat64{Float64: 0, Valid: true}
		totalEarnings = sql.NullFloat64{Float64: 0, Valid: true}
	} else if err != nil {
		http.Error(w, "Failed to fetch wallet", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"status":         "success",
		"balance":        balance.Float64,
		"total_earnings": totalEarnings.Float64,
	})
}

func driverProfileHandler(w http.ResponseWriter, r *http.Request) {
	phone := cleanPhone(r.URL.Query().Get("phone"))
	if phone == "" {
		http.Error(w, "Missing phone", http.StatusBadRequest)
		return
	}

	var id int
	var name, email, gender, driverPhone, profilePhotoUrl, vehicleType sql.NullString
	var rating sql.NullFloat64
	var isVerified bool
	err := db.QueryRow(`
		SELECT id, full_name, email, gender, phone, rating, is_verified, profile_photo_url, vehicle_type
		FROM drivers WHERE phone = $1
	`, phone).Scan(&id, &name, &email, &gender, &driverPhone, &rating, &isVerified, &profilePhotoUrl, &vehicleType)
	if err != nil {
		http.Error(w, "Driver not found", http.StatusNotFound)
		return
	}

	var photoURL string
	if profilePhotoUrl.Valid && profilePhotoUrl.String != "" {
		// Prepend host name dynamically based on the request host
		photoURL = fmt.Sprintf("http://%s%s", r.Host, profilePhotoUrl.String)
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"status":            "success",
		"driver_id":         id,
		"name":              name.String,
		"email":             email.String,
		"gender":            gender.String,
		"phone":             driverPhone.String,
		"rating":            rating.Float64,
		"is_verified":       isVerified,
		"profile_photo_url": photoURL,
		"vehicle_type":      vehicleType.String,
	})
}

func driverUpdateVehicleTypeHandler(w http.ResponseWriter, r *http.Request) {
	log.Printf("Driver Update Vehicle Type Endpoint Hit: %s", r.URL.Path)
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req struct {
		Phone       string `json:"phone"`
		VehicleType string `json:"vehicle_type"`
	}

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid input data", http.StatusBadRequest)
		return
	}

	phone := cleanPhone(req.Phone)
	if phone == "" || req.VehicleType == "" {
		http.Error(w, "Missing phone or vehicle type", http.StatusBadRequest)
		return
	}

	query := "UPDATE drivers SET vehicle_type = $1 WHERE phone = $2"
	_, err := db.Exec(query, req.VehicleType, phone)
	if err != nil {
		log.Printf("Database error updating vehicle type: %v", err)
		http.Error(w, "Database error", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"status": "success",
	})
}

func driverUploadProfilePhotoHandler(w http.ResponseWriter, r *http.Request) {
	log.Printf("Driver Upload Profile Photo Endpoint Hit: %s", r.URL.Path)
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req struct {
		Phone     string `json:"phone"`
		ImageData string `json:"image_data"` // base64 string
	}

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid input data", http.StatusBadRequest)
		return
	}

	phone := cleanPhone(req.Phone)
	if phone == "" || req.ImageData == "" {
		http.Error(w, "Missing phone or image data", http.StatusBadRequest)
		return
	}

	// Decode base64 image data
	decodedBytes, err := base64.StdEncoding.DecodeString(req.ImageData)
	if err != nil {
		log.Printf("Error decoding base64 image: %v", err)
		http.Error(w, "Invalid base64 image data", http.StatusBadRequest)
		return
	}

	// Create attachments directory outside the backend folder
	attachmentsDir := filepath.Join("..", "attachments")
	if err := os.MkdirAll(attachmentsDir, 0755); err != nil {
		log.Printf("Error creating attachments directory: %v", err)
		http.Error(w, "Server error creating storage directory", http.StatusInternalServerError)
		return
	}

	// Save file as profile_<phone>.jpg
	filename := fmt.Sprintf("profile_%s.jpg", phone)
	targetPath := filepath.Join(attachmentsDir, filename)
	if err := os.WriteFile(targetPath, decodedBytes, 0644); err != nil {
		log.Printf("Error writing profile image file: %v", err)
		http.Error(w, "Server error saving image", http.StatusInternalServerError)
		return
	}

	// Update database path
	dbPath := fmt.Sprintf("/attachments/%s", filename)
	query := "UPDATE drivers SET profile_photo_url = $1 WHERE phone = $2"
	_, err = db.Exec(query, dbPath, phone)
	if err != nil {
		log.Printf("Database error updating profile photo path: %v", err)
		http.Error(w, "Database error", http.StatusInternalServerError)
		return
	}

	// Construct full URL to return to client
	fullURL := fmt.Sprintf("http://%s%s", r.Host, dbPath)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"status":            "success",
		"profile_photo_url": fullURL,
	})
}

func driverRideDetailHandler(w http.ResponseWriter, r *http.Request) {
	rideID := r.URL.Query().Get("ride_id")
	driverPhone := cleanPhone(r.URL.Query().Get("driver_phone"))
	if rideID == "" || driverPhone == "" {
		http.Error(w, "Missing ride_id or driver_phone", http.StatusBadRequest)
		return
	}

	var driverID int
	err := db.QueryRow("SELECT id FROM drivers WHERE phone = $1", driverPhone).Scan(&driverID)
	if err != nil {
		http.Error(w, "Driver not found", http.StatusNotFound)
		return
	}

	var id int
	var custPhone, pickupAddr, dropAddr, vehicleType, status sql.NullString
	var pLat, pLng, dLat, dLng, distance, fare sql.NullFloat64
	var customerName sql.NullString

	err = db.QueryRow(`
		SELECT r.id, r.customer_phone, u.full_name, r.pickup_lat, r.pickup_lng, r.pickup_address,
		       r.drop_lat, r.drop_lng, r.drop_address, r.vehicle_type, r.distance_km,
		       r.estimated_fare, r.status
		FROM rides r
		LEFT JOIN users u ON r.customer_phone = u.phone
		WHERE r.id = $1 AND r.driver_id = $2
	`, rideID, driverID).Scan(
		&id, &custPhone, &customerName, &pLat, &pLng, &pickupAddr,
		&dLat, &dLng, &dropAddr, &vehicleType, &distance, &fare, &status,
	)
	if err != nil {
		http.Error(w, "Ride not found", http.StatusNotFound)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"status":         "success",
		"id":             id,
		"customer_phone": custPhone.String,
		"customer_name":  customerName.String,
		"pickup_lat":     pLat.Float64,
		"pickup_lng":     pLng.Float64,
		"pickup_address": pickupAddr.String,
		"drop_lat":       dLat.Float64,
		"drop_lng":       dLng.Float64,
		"drop_address":   dropAddr.String,
		"vehicle_type":   vehicleType.String,
		"distance_km":    distance.Float64,
		"estimated_fare": fare.Float64,
		"ride_status":    status.String,
	})
}

func main() {
	// Seed random number generator
	rand.Seed(time.Now().UnixNano())
	
	// Load .env file
	err := godotenv.Load()
	if err != nil {
		log.Println("Warning: .env file not found, using environment variables or defaults")
	}

	initDB()
	defer db.Close()

	// Initialize Exotel config from env
	exotelAPIKey = getEnv("EXOTEL_API_KEY", "")
	exotelAPIToken = getEnv("EXOTEL_API_TOKEN", "")
	exotelAccountSID = getEnv("EXOTEL_ACCOUNT_SID", "torkk")
	exotelSenderID = getEnv("EXOTEL_SENDER_ID", "TORKKK")
	log.Printf("Exotel initialized | Account: %s | Sender: %s", exotelAccountSID, exotelSenderID)

	// Initialize MSG91 config from env
	msg91AuthKey = getEnv("MSG91_AUTH_KEY", "")
	msg91TemplateID = getEnv("MSG91_TEMPLATE_ID", "")
	log.Printf("MSG91 initialized | Template ID: %s", msg91TemplateID)

	razorpayKeyID = getEnv("RAZORPAY_KEY", "")
	razorpayKeySecret = getEnv("RAZORPAY_KEY_SECRET", "")
	if razorpayKeyID == "" || razorpayKeySecret == "" {
		log.Printf("Razorpay NOT fully configured (RAZORPAY_KEY / RAZORPAY_KEY_SECRET missing) — payments will fail")
	} else {
		log.Printf("Razorpay initialized | Key: ...%s", maskLast4(razorpayKeyID))
	}

	surepassAPIKey = getEnv("SUREPASS_API_KEY", "")
	surepassBaseURL = strings.TrimRight(getEnv("SUREPASS_BASE_URL", "https://kyc-api.surepass.app"), "/")
	if surepassAPIKey == "" {
		log.Printf("Surepass NOT configured (SUREPASS_API_KEY missing) — face verification will fail")
	} else {
		log.Printf("Surepass initialized | Base: %s | Key: ...%s", surepassBaseURL, maskLast4(surepassAPIKey))
	}

	http.HandleFunc("/api/check-phone", checkPhoneHandler)
	http.HandleFunc("/api/register", registerHandler)
	http.HandleFunc("/api/send-otp", sendOTPHandler)
	http.HandleFunc("/api/verify-otp", verifyOTPHandler)
	http.HandleFunc("/api/verify-aadhaar", verifyAadhaarHandler)
	http.HandleFunc("/api/enable-biometric", enableBiometricHandler)
	
	http.HandleFunc("/api/ride/estimate", rideEstimateHandler)
	http.HandleFunc("/api/ride/request", rideRequestHandler)
	http.HandleFunc("/api/ride/match", rideMatchHandler)
	http.HandleFunc("/api/ride/status", rideStatusHandler)
	http.HandleFunc("/api/ride/payment", ridePaymentHandler)
	http.HandleFunc("/api/payments/create-order", paymentsCreateOrderHandler)
	http.HandleFunc("/api/payments/verify", paymentsVerifyHandler)
	http.HandleFunc("/api/kyc/verify-liveness", livenessVerifyHandler)
	// Customer Wallet Endpoints
	http.HandleFunc("/api/wallet/balance", customerWalletBalanceHandler)
	http.HandleFunc("/api/wallet/transactions", customerWalletTransactionsHandler)
	http.HandleFunc("/api/wallet/add-money", customerWalletAddMoneyHandler)
	http.HandleFunc("/api/wallet/verify-payment", customerWalletVerifyPaymentHandler)
	http.HandleFunc("/api/wallet/pay-ride", customerWalletPayRideHandler)

	http.HandleFunc("/api/sos", sosHandler)
	http.HandleFunc("/api/contacts", getContactsHandler)
	http.HandleFunc("/api/contacts/save", saveContactsHandler)
	http.HandleFunc("/api/ride/history", rideHistoryHandler)
	http.HandleFunc("/api/users/current-location", updateLocationHandler)

	// Driver Endpoints
	http.HandleFunc("/api/driver/upload-profile-photo", driverUploadProfilePhotoHandler)
	http.HandleFunc("/api/driver/update-vehicle-type", driverUpdateVehicleTypeHandler)
	http.HandleFunc("/api/driver/verify-otp", driverVerifyOTPHandler)
	http.HandleFunc("/api/driver/verify-dl", driverVerifyDLHandler)
	http.HandleFunc("/api/driver/verify-rc", driverVerifyRCHandler)
	http.HandleFunc("/api/driver/register", driverRegisterHandler)
	http.HandleFunc("/api/driver/check-phone", driverCheckPhoneHandler)
	http.HandleFunc("/api/driver/active-rides", driverActiveRidesHandler)
	http.HandleFunc("/api/driver/accept-ride", driverAcceptRideHandler)
	http.HandleFunc("/api/driver/update-location", driverUpdateLocationHandler)
	http.HandleFunc("/api/driver/start-ride", driverStartRideHandler)
	http.HandleFunc("/api/driver/pickup-customer", driverPickupCustomerHandler)
	http.HandleFunc("/api/driver/complete-ride", driverCompleteRideHandler)
	http.HandleFunc("/api/driver/trips", driverTripHistoryHandler)
	http.HandleFunc("/api/driver/earnings", driverEarningsHandler)
	http.HandleFunc("/api/driver/wallet", driverWalletHandler)
	http.HandleFunc("/api/driver/profile", driverProfileHandler)
	http.HandleFunc("/api/driver/ride", driverRideDetailHandler)
	// Reuse the customer send-otp for the driver (now uses Exotel)
	http.HandleFunc("/api/driver/send-otp", sendOTPHandler)

	// Serve profile attachments
	http.Handle("/attachments/", http.StripPrefix("/attachments/", http.FileServer(http.Dir("../attachments"))))

	port := getEnv("PORT", "8080")
	log.Printf("Torkk Go Backend running on port %s...", port)
	if err := http.ListenAndServe("0.0.0.0:"+port, nil); err != nil {
		log.Fatalf("ListenAndServe failed: %v", err)
	}
}
