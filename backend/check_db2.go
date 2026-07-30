package main

import (
	"database/sql"
	"fmt"
	"log"

	_ "github.com/lib/pq"
)

func main() {
	connStr := "host=localhost port=5432 user=postgres password=Sonal@123 dbname=torkk_db sslmode=disable"
	db, err := sql.Open("postgres", connStr)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	rows, err := db.Query("SELECT phone, full_name, has_biometric, biometric_type, email FROM users ORDER BY id DESC LIMIT 5")
	if err != nil {
		log.Fatal("Error querying users: ", err)
	}
	defer rows.Close()

	fmt.Println("Latest 5 USERS in DB:")
	for rows.Next() {
		var phone, name string
		var hasBio bool
		var bioType sql.NullString
		var email sql.NullString
		err := rows.Scan(&phone, &name, &hasBio, &bioType, &email)
		if err != nil {
			log.Fatal(err)
		}
		fmt.Printf("Phone: '%s', Name: '%s', Email: '%s', HasBio: %v, BioType: '%s'\n", phone, name, email.String, hasBio, bioType.String)
	}
}
