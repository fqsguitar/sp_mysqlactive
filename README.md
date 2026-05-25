# sp_mysqlactive

Lightweight MySQL activity monitoring procedure inspired by `sp_WhoIsActive` for SQL Server.

---

## Features

- Active session monitoring
- Blocking session detection
- Transaction visibility
- Lock wait analysis
- Wait event details
- Query troubleshooting
- Temp table detection
- SQL text fallback support
- Database filtering
- Elapsed time filtering

---

## Compatibility

- MySQL 8.0+
- Aurora MySQL
- AWS RDS MySQL

---

## Installation

Run the SQL installation script:

```sql
SOURCE sp_mysqlactive_v1_0_0.sql;
```

---

## Usage

Default mode:

```sql
CALL sp_mysqlactive();
```

Advanced mode:

```sql
CALL sp_mysqlactive_full(TRUE, 10, NULL);
```

Version info:

```sql
CALL sp_mysqlactive_version();
```

---

## Output Information

The procedure provides real-time visibility for:

- Running sessions
- Blocking and blocked sessions
- Wait events
- Open transactions
- Rows examined
- Rows sent
- Temp table usage
- Index usage issues
- Current SQL text

---

## Author

Felipe Queiroz  
QZ Data

---

## License

MIT License
