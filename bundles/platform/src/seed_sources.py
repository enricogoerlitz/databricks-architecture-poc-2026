# Databricks notebook source
# MAGIC %md
# MAGIC # Seed: Dummy-Daten im Quellsystem (simuliert das Quell-Team)
# MAGIC
# MAGIC - Azure SQL `sqldb-salesdb`: Tabellen `dbo.customers`, `dbo.orders` mit leicht "messy" Daten,
# MAGIC   Reader-User `dbx_reader` für Databricks, Change Tracking an (für den CDC-Lernpfad)
# MAGIC - Landing-Volume: CSV-Dateien `products/products_<ts>_r<round>.csv`
# MAGIC
# MAGIC `round=1`: Erstbefüllung (nur wenn leer). `round=2`: Änderungen (Updates, Delete, neue Zeilen)
# MAGIC für die SCD2-Demo. Zugangsdaten kommen ausschließlich aus dem Secret Scope `kv`.

# COMMAND ----------

# MAGIC %pip install python-tds==1.17.* "pyOpenSSL==24.2.*" certifi --quiet

# COMMAND ----------

import random
from datetime import datetime, UTC

import certifi
import pytds

dbutils.widgets.text("round", "1")
dbutils.widgets.text("bronze_catalog", "dev_bronze")
seed_round = int(dbutils.widgets.get("round"))
landing_dir = f"/Volumes/{dbutils.widgets.get('bronze_catalog')}/landing/files/products"

host = dbutils.secrets.get("kv", "salesdb-host")
# python-tds: reines Python (pymssql bricht auf serverless mit SIGABRT ab), TLS ist Pflicht
conn = pytds.connect(
    dsn=host,
    port=1433,
    database="sqldb-salesdb",
    user=dbutils.secrets.get("kv", "salesdb-admin-user"),
    password=dbutils.secrets.get("kv", "salesdb-admin-password"),
    cafile=certifi.where(),
    validate_host=True,
    # Serverless/Free-Offer-DB pausiert automatisch; das Aufwachen dauert 1-3 Minuten
    login_timeout=300,
    autocommit=True,
)
cur = conn.cursor()
print(f"verbunden mit {host.split('.')[0]} (privat über NCC Private Endpoint), round={seed_round}")


def run(sql: str, params=None) -> None:
    cur.execute(sql, params)


def scalar(sql: str):
    cur.execute(sql)
    return cur.fetchone()[0]


# COMMAND ----------

# MAGIC %md ## Schema, Reader-User, Change Tracking

# COMMAND ----------

run("""
IF OBJECT_ID('dbo.customers') IS NULL
CREATE TABLE dbo.customers (
    customer_id INT NOT NULL PRIMARY KEY,
    name        NVARCHAR(200) NULL,
    email       NVARCHAR(200) NULL,
    city        NVARCHAR(100) NULL,
    segment     NVARCHAR(50)  NULL,
    updated_at  DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME()
)""")
run("""
IF OBJECT_ID('dbo.orders') IS NULL
CREATE TABLE dbo.orders (
    order_id    INT NOT NULL PRIMARY KEY,
    customer_id INT NULL,
    order_date  NVARCHAR(30) NULL,      -- bewusst Text: uneinheitliche Formate
    amount      DECIMAL(12,2) NULL,
    status      NVARCHAR(30) NULL,
    is_deleted  BIT NOT NULL DEFAULT 0,
    updated_at  DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
)""")

# Contained Database User für Databricks (nur lesend). Passwort setzt das Quell-Team im Key Vault.
reader = dbutils.secrets.get("kv", "salesdb-user")
reader_pw = dbutils.secrets.get("kv", "salesdb-password").replace("'", "''")
if not scalar(f"SELECT COUNT(*) FROM sys.database_principals WHERE name = '{reader}'"):
    run(f"CREATE USER [{reader}] WITH PASSWORD = '{reader_pw}'")
else:
    run(f"ALTER USER [{reader}] WITH PASSWORD = '{reader_pw}'")
run(f"ALTER ROLE db_datareader ADD MEMBER [{reader}]")
run(f"GRANT VIEW CHANGE TRACKING ON SCHEMA::dbo TO [{reader}]")

# Change Tracking für den Lernpfad (Lakeflow Connect CDC); kostet nichts, schadet dem Full Load nicht
if not scalar("SELECT COUNT(*) FROM sys.change_tracking_databases WHERE database_id = DB_ID()"):
    run("ALTER DATABASE CURRENT SET CHANGE_TRACKING = ON (CHANGE_RETENTION = 3 DAYS, AUTO_CLEANUP = ON)")
for t in ("customers", "orders"):
    if not scalar(f"SELECT COUNT(*) FROM sys.change_tracking_tables WHERE object_id = OBJECT_ID('dbo.{t}')"):
        run(f"ALTER TABLE dbo.{t} ENABLE CHANGE_TRACKING")
print("Schema, Reader-User und Change Tracking ok")

# COMMAND ----------

# MAGIC %md ## Daten (leicht messy)

# COMMAND ----------

rnd = random.Random(42 + seed_round)
first = ["Anna", "Ben", "Clara", "David", "Eva", "Felix", "Greta", "Hannes", "Ida", "Jonas", "Klara", "Lukas"]
last = ["Müller", "Schmidt", "Schneider", "Fischer", "Weber", "Meyer", "Wagner", "Becker"]
cities = ["Berlin", "Hamburg", "München", "Köln", " frankfurt ", "Leipzig", None]
segments = ["Retail", "B2B", " retail", "Enterprise"]
date_fmts = ["%Y-%m-%d", "%d.%m.%Y", "%m/%d/%Y"]


def messy_name(i: int) -> str:
    n = f"{first[i % len(first)]} {last[i % len(last)]}"
    return rnd.choice([n, f"  {n}", n.replace(" ", "   "), n.upper()])


def messy_email(name: str, i: int) -> str | None:
    base = name.strip().lower().replace("   ", ".").replace(" ", ".").replace("ü", "ue").replace("ö", "oe")
    return rnd.choice([f"{base}{i}@example.com", f" {base.upper()}{i}@Example.COM ", f"{base}{i}example.com", None])


if seed_round == 1:
    if scalar("SELECT COUNT(*) FROM dbo.customers"):
        print("round 1: Daten existieren bereits – übersprungen (idempotent)")
    else:
        for i in range(1, 21):
            name = messy_name(i)
            run(
                "INSERT INTO dbo.customers (customer_id, name, email, city, segment) VALUES (%s, %s, %s, %s, %s)",
                (i, name, messy_email(name, i), rnd.choice(cities), rnd.choice(segments)),
            )
        for o in range(1, 61):
            d = datetime(2026, rnd.randint(7, 9), rnd.randint(1, 28))
            amount = round(rnd.uniform(10, 500), 2) if o != 13 else -5.00  # ein ungültiger Betrag
            run(
                "INSERT INTO dbo.orders (order_id, customer_id, order_date, amount, status) VALUES (%s, %s, %s, %s, %s)",
                (
                    o,
                    rnd.choice([*range(1, 21), None]),
                    d.strftime(rnd.choice(date_fmts)),
                    amount,
                    rnd.choice(["shipped", " open", "SHIPPED", "cancelled"]),
                ),
            )
        print("round 1: 20 Kunden, 60 Bestellungen angelegt")

elif seed_round == 2:
    run("UPDATE dbo.customers SET city = N'Dresden', updated_at = SYSUTCDATETIME() WHERE customer_id IN (2, 5)")
    run(
        "UPDATE dbo.customers SET segment = N'Enterprise', email = N'neu.adresse7@example.com', updated_at = SYSUTCDATETIME() WHERE customer_id = 7"
    )
    run("DELETE FROM dbo.customers WHERE customer_id = 20")
    run("""IF NOT EXISTS (SELECT 1 FROM dbo.customers WHERE customer_id = 21)
           INSERT INTO dbo.customers (customer_id, name, email, city, segment)
           VALUES (21, N'Zoe   Neumann', N'ZOE.NEUMANN@EXAMPLE.COM', N'Bonn', N'B2B')""")
    run("UPDATE dbo.orders SET status = N'shipped', updated_at = SYSUTCDATETIME() WHERE status LIKE '%open%'")
    run("UPDATE dbo.orders SET is_deleted = 1, updated_at = SYSUTCDATETIME() WHERE order_id = 3")
    run("""IF NOT EXISTS (SELECT 1 FROM dbo.orders WHERE order_id = 61)
           INSERT INTO dbo.orders (order_id, customer_id, order_date, amount, status)
           VALUES (61, 21, N'2026-10-08', 199.99, N'open')""")
    print("round 2: Updates (Kunden 2, 5, 7), Delete (Kunde 20), Insert (Kunde 21, Bestellung 61)")

cust = scalar("SELECT COUNT(*) FROM dbo.customers")
orders = scalar("SELECT COUNT(*) FROM dbo.orders")
conn.close()
print(f"Quelle: {cust} Kunden, {orders} Bestellungen")

# COMMAND ----------

# MAGIC %md ## Landing-Dateien (CSV, `;`-getrennt)

# COMMAND ----------

import os

products = [
    ("P-100", "Laptop  Pro 14", "Hardware", "1299.00", "2026-01-01"),
    ("P-101", ' Monitor 27" ', "hardware", "349.90", "01.02.2026"),
    ("P-102", "Docking Station", "Hardware", "", "03/01/2026"),
    ("P-200", "Office Lizenz", "Software", "99.00", "2026-01-15"),
    ("P-201", "  Antivirus", " Software ", "29.99", "20260201"),
    ("P-201", "  Antivirus", " Software ", "29.99", "20260201"),  # Dublette
]
if seed_round == 2:
    products = [
        ("P-100", "Laptop Pro 14", "Hardware", "1199.00", "2026-10-01"),  # Preisänderung -> SCD2
        ("P-300", "Headset", "Accessories", "79.00", "08.10.2026"),  # neu
    ]

os.makedirs(landing_dir, exist_ok=True)
ts = datetime.now(UTC).strftime("%Y%m%d%H%M%S")
path = f"{landing_dir}/products_{ts}_r{seed_round}.csv"
with open(path, "w", encoding="utf-8") as f:
    f.write("product_code;product_name;category;price;valid_from\n")
    for row in products:
        f.write(";".join(row) + "\n")
print(f"Datei geschrieben: {path} ({len(products)} Zeilen)")
