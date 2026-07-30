package main

import (
	"database/sql"
	"fmt"
	"log"

	_ "github.com/lib/pq"
)

func main() {
	connStr := "user=postgres password=Sonal@123 dbname=torkk_db sslmode=disable"
	db, err := sql.Open("postgres", connStr)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	var exists bool
	err = db.QueryRow("SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'driver_documents')").Scan(&exists)
	fmt.Printf("driver_documents exists: %v\n", exists)

	var phone string
	err = db.QueryRow("SELECT phone FROM drivers WHERE phone = '8310501036'").Scan(&phone)
	if err != nil {
		fmt.Printf("Driver 8310501036 error: %v\n", err)
	} else {
		fmt.Printf("Driver 8310501036 exists in drivers table\n")
	}
}
