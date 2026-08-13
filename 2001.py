
import pyodbc

server = 'dist-6-505.uopnet.plymouth.ac.uk'
database = 'COMP2001_JMcEwan'
username = 'JMcEwan'
password = 'EidJ320'
driver = '{ODBC Driver 17 for SQL Server}'

conn_str = (
    f"DRIVER={driver};"
    f"SERVER={server};"
    f"DATABASE={database};"
    f"UID={username};"
    f"PWD={password};"
    "Encrypt=Yes;"
    "TrustServerCertificate=Yes;"
    "Connection Timeout=30;"
)

try:
    conn = pyodbc.connect(conn_str)
    print("Connected successfully!")
    conn.close()
except Exception as e:
    print(f"Connection failed: {e}")