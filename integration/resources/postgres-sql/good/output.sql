-- Test file: output.sql

SELECT * FROM {{.test_schema}}.table1;
SELECT AVG(age)::int FROM {{.test_schema}}.table1;
