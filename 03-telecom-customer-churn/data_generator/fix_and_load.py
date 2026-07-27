"""Fix-and-reload: converts timestamps to strings before Snowflake load."""
import sys, os
sys.path.insert(0, ".")
from generate_data import build_tables, get_connection, DDL
from snowflake.connector.pandas_tools import write_pandas
import numpy as np

rng = np.random.default_rng(42)
tables, _ = build_tables(rng, 10000)

# Convert all datetime columns to ISO strings so write_pandas does not corrupt them
for name, df in tables.items():
    for col in df.columns:
        if df[col].dtype.kind == "M":
            df[col] = df[col].dt.strftime("%Y-%m-%d %H:%M:%S")

conn = get_connection()
cur = conn.cursor()
database = os.environ.get("SNOWFLAKE_DATABASE")
schema = os.environ.get("SNOWFLAKE_SCHEMA", "RAW")
if database:
    cur.execute(f"CREATE DATABASE IF NOT EXISTS {database}")
    cur.execute(f"USE DATABASE {database}")
cur.execute(f"CREATE SCHEMA IF NOT EXISTS {schema}")
cur.execute(f"USE SCHEMA {schema}")

for name, df in tables.items():
    print(f"  -> {name}: {len(df):,} rows")
    cur.execute(DDL[name])
    success, _, nrows, _ = write_pandas(conn, df, name, quote_identifiers=False, auto_create_table=False)
    if not success:
        sys.exit(f"Load failed for {name}")
    print(f"     loaded")

cur.close()
conn.close()
print("Done. All tables reloaded with fixed timestamps.")
