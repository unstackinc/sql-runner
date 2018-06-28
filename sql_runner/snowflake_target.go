package main

import (
	"database/sql"
	"log"
	"time"
	sf "github.com/snowflakedb/gosnowflake"
	"strings"
	"text/tabwriter"
	"os"
	"fmt"
	"bytes"
)

// Specific for Snowflake db
const (
	loginTimeout = 5 * time.Second // by default is 60
)

type SnowFlakeTarget struct {
	Target
	Client *sql.DB
}

func NewSnowflakeTarget(target Target) *SnowFlakeTarget {

	configStr, err := sf.DSN(&sf.Config{
		Region:       target.Region,
		Account:      target.Account,
		User:         target.Username,
		Password:     target.Password,
		Database:     target.Database,
		Warehouse:    target.Warehouse,
		LoginTimeout: loginTimeout,
	})

	if err != nil {
		log.Fatal(err)
	}

	db, err := sql.Open("snowflake", configStr)

	if err != nil {
		log.Fatal(err)
	}

	return &SnowFlakeTarget{target, db}
}

func (sft SnowFlakeTarget) GetTarget() Target {
	return sft.Target
}

// Run a query against the target
// One statement per API call
func (sft SnowFlakeTarget) RunQuery(query ReadyQuery, dryRun bool, dropOutput bool) QueryStatus {
	var affected int64 = 0
	var err error

	if dryRun {
		return QueryStatus{query, query.Path, 0, nil}
	}

	scripts := strings.Split(query.Script, ";")

	for _, script := range scripts {
		if len(strings.TrimSpace(script)) > 0 {
			if dropOutput {
				const padding = 3
				w := tabwriter.NewWriter(os.Stdout, 0, 0, padding, '-', tabwriter.AlignRight|tabwriter.Debug)
				rows, err := sft.Client.Query(script)

				cols, err := rows.Columns() // Remember to check err afterwards
				if err != nil {
					log.Println("ERROR: Unable to read columns")
					return QueryStatus{query, query.Path, int(affected), err}
				}

				tabbedColumns := concatenate(cols)
				fmt.Fprintln(w, tabbedColumns)

				vals := make([]interface{}, len(cols))
				for i, _ := range cols {
					vals[i] = new(sql.RawBytes)
				}

				for rows.Next() {
					err = rows.Scan(vals...)
					if err != nil {
						return QueryStatus{query, query.Path, int(affected), err}
					}

					tabbedRow := concatenate(stringify(vals))
					fmt.Fprintln(w, tabbedRow)
				}
			} else {
				res, err := sft.Client.Exec(script)

				if err != nil {
					return QueryStatus{query, query.Path, int(affected), err}
				} else {
					aff, _ := res.RowsAffected()
					affected += aff
				}
			}
		}
	}

	return QueryStatus{query, query.Path, int(affected), err}
}

func concatenate(row []string) string {
	var line bytes.Buffer
	for _, element := range row {
		line.WriteString(fmt.Sprint(element))
		line.WriteString("\t")
	}
	return line.String()
}

func stringify(row []interface{}) []string {
	var line []string
	for _, element := range row {
		line = append(line, fmt.Sprint(element))
	}
	return line
}