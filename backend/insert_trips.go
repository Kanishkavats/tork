package main

import (
	"database/sql"
	"fmt"
	"log"

	_ "github.com/lib/pq"
)

func main() {
	host := "torkk-db.cno80cam2fzy.ap-south-1.rds.amazonaws.com"
	port := "5432"
	user := "postgres"
	password := "12345678"
	dbname := "postgres"
	sslmode := "require"

	connStr := fmt.Sprintf("host=%s port=%s user=%s password=%s dbname=%s sslmode=%s", host, port, user, password, dbname, sslmode)

	db, err := sql.Open("postgres", connStr)
	if err != nil {
		log.Fatalf("Error opening database connection: %v", err)
	}
	defer db.Close()

	err = db.Ping()
	if err != nil {
		log.Fatalf("Error connecting to database: %v", err)
	}

	fmt.Println("Successfully connected to database")

	// SQL queries to insert Davangere trips
	queries := []string{
		// In-Progress rides (driver assigned, ride ongoing)
		`INSERT INTO rides (customer_phone, driver_id, pickup_lat, pickup_lng, pickup_address, drop_lat, drop_lng, drop_address, vehicle_type, distance_km, estimated_fare, driver_earnings, status, is_picked_up, is_dropped, male_passengers, female_passengers, created_at) VALUES
		('8310501036', 1, 14.4633, 75.9237, 'MCC B Block, Davangere', 14.4693, 75.9307, 'Saraswathipuram, Davangere', 'cab', 5.2, 120.00, 96.00, 'in_progress', 1, 0, 1, 0, NOW() - INTERVAL '30 minutes'),
		('9876543210', 2, 14.4673, 75.9287, 'PJ Extension, Davangere', 14.4733, 75.9347, 'Vidyanagar, Davangere', 'auto', 3.5, 45.00, 36.00, 'in_progress', 0, 0, 0, 1, NOW() - INTERVAL '15 minutes'),
		('9743446504', 3, 14.4653, 75.9257, 'Kondajji Road, Davangere', 14.4713, 75.9327, 'Bathi Bus Stand, Davangere', 'auto', 4.1, 55.00, 44.00, 'in_progress', 1, 0, 1, 0, NOW() - INTERVAL '45 minutes'),
		('8765432109', 4, 14.4693, 75.9307, 'SS Layout, Davangere', 14.4753, 75.9367, 'University of Davangere, Davangere', 'cab', 6.0, 150.00, 120.00, 'in_progress', 0, 0, 2, 1, NOW() - INTERVAL '20 minutes'),
		('9876545896', 5, 14.4713, 75.9327, 'Shamanur Road, Davangere', 14.4643, 75.9247, 'City Hospital, Davangere', 'bike', 2.5, 80.00, 64.00, 'in_progress', 1, 0, 1, 0, NOW() - INTERVAL '10 minutes')`,

		// Requested rides (waiting for driver assignment)
		`INSERT INTO rides (customer_phone, driver_id, pickup_lat, pickup_lng, pickup_address, drop_lat, drop_lng, drop_address, vehicle_type, distance_km, estimated_fare, driver_earnings, status, is_picked_up, is_dropped, male_passengers, female_passengers, created_at) VALUES
		('8310501036', NULL, 14.4633, 75.9237, 'Railway Station, Davangere', 14.4693, 75.9307, 'Bus Stand, Davangere', 'auto', 3.8, 50.00, NULL, 'requested', 0, 0, 1, 0, NOW() - INTERVAL '5 minutes'),
		('9876543210', NULL, 14.4673, 75.9287, 'JP Nagar, Davangere', 14.4733, 75.9347, 'Mall Road, Davangere', 'cab', 5.5, 130.00, NULL, 'requested', 0, 0, 2, 1, NOW() - INTERVAL '8 minutes'),
		('9743446504', NULL, 14.4653, 75.9257, 'Laxmi Theater, Davangere', 14.4713, 75.9327, 'Davanagere Court, Davangere', 'auto', 4.2, 58.00, NULL, 'requested', 0, 0, 1, 0, NOW() - INTERVAL '12 minutes'),
		('8765432109', NULL, 14.4693, 75.9307, 'Karnataka Milk Union, Davangere', 14.4753, 75.9367, 'Tolahunase, Davangere', 'cab', 7.5, 175.00, NULL, 'requested', 0, 0, 1, 2, NOW() - INTERVAL '3 minutes'),
		('9876545896', NULL, 14.4713, 75.9327, 'Bapuji Nagar, Davangere', 14.4643, 75.9247, 'Old Bus Stand, Davangere', 'bike', 3.0, 95.00, NULL, 'requested', 0, 0, 1, 0, NOW() - INTERVAL '7 minutes')`,

		// More in-progress rides for testing
		`INSERT INTO rides (customer_phone, driver_id, pickup_lat, pickup_lng, pickup_address, drop_lat, drop_lng, drop_address, vehicle_type, distance_km, estimated_fare, driver_earnings, status, is_picked_up, is_dropped, male_passengers, female_passengers, created_at) VALUES
		('8310501036', 1, 14.4633, 75.9237, 'Siddhartha Layout, Davangere', 14.4693, 75.9307, 'Gandhinagar, Davangere', 'cab', 4.8, 115.00, 92.00, 'in_progress', 0, 0, 2, 0, NOW() - INTERVAL '25 minutes'),
		('9876543210', 2, 14.4673, 75.9287, 'Police Station, Davangere', 14.4733, 75.9347, 'RTO Office, Davangere', 'auto', 2.9, 40.00, 32.00, 'in_progress', 1, 0, 0, 1, NOW() - INTERVAL '35 minutes'),
		('9743446504', 3, 14.4653, 75.9257, 'Davanagere South, Davangere', 14.4713, 75.9327, 'Harapanahalli Road, Davangere', 'auto', 5.5, 70.00, 56.00, 'in_progress', 0, 0, 1, 1, NOW() - INTERVAL '40 minutes'),
		('8765432109', 4, 14.4693, 75.9307, 'P B Road, Davangere', 14.4753, 75.9367, 'Jawaharlal Nehru Road, Davangere', 'cab', 3.2, 85.00, 68.00, 'in_progress', 1, 0, 1, 0, NOW() - INTERVAL '50 minutes'),
		('9876545896', 5, 14.4713, 75.9327, 'Kunduvada, Davangere', 14.4643, 75.9247, 'Santhebennur, Davangere', 'bike', 8.5, 250.00, 200.00, 'in_progress', 0, 0, 1, 0, NOW() - INTERVAL '55 minutes')`,
	}

	for i, query := range queries {
		result, err := db.Exec(query)
		if err != nil {
			log.Printf("Error executing query %d: %v", i+1, err)
			continue
		}
		rowsAffected, _ := result.RowsAffected()
		fmt.Printf("Query %d executed successfully. Rows affected: %d\n", i+1, rowsAffected)
	}

	// Verify the inserted rides
	fmt.Println("\n--- Verifying Davangere Trips ---")
	rows, err := db.Query(`
		SELECT id, customer_phone, driver_id, pickup_address, drop_address, 
		       vehicle_type, status, created_at 
		FROM rides 
		WHERE (pickup_address ILIKE '%Davanagere%' OR drop_address ILIKE '%Davanagere%')
		  AND status IN ('in_progress', 'requested')
		ORDER BY created_at DESC
	`)
	if err != nil {
		log.Printf("Error querying rides: %v", err)
		return
	}
	defer rows.Close()

	count := 0
	for rows.Next() {
		var id int
		var customerPhone sql.NullString
		var driverID sql.NullInt64
		var pickupAddress, dropAddress, vehicleType, status string
		var createdAt string
		rows.Scan(&id, &customerPhone, &driverID, &pickupAddress, &dropAddress, &vehicleType, &status, &createdAt)
		fmt.Printf("ID: %d | Customer: %s | Driver: %v | %s -> %s | %s | %s\n",
			id, customerPhone.String, driverID.Int64, pickupAddress, dropAddress, vehicleType, status)
		count++
	}
	fmt.Printf("\nTotal Davangere active rides: %d\n", count)
}
