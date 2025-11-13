import psycopg2
import pandas as pd

# 🔧 Datos de conexión (tu Render DB)
conn_params = {
    "host": "dpg-d4avpa2li9vc73dljvng-a.oregon-postgres.render.com",
    "dbname": "iot_db_wcra",
    "user": "iot",
    "password": "p3guljWveqfEFZLYmI32piQxbzi6iaIq",
    "port": 5432
}

# 🧩 Conectar
try:
    conn = psycopg2.connect(**conn_params)
    print("✅ Conectado a la base de datos")

    # 👉 Mostrar todas las tablas
    query_tablas = """
    SELECT table_name
    FROM information_schema.tables
    WHERE table_schema = 'public';
    """
    tablas = pd.read_sql(query_tablas, conn)
    print("\n📋 Tablas disponibles:")
    print(tablas)

    # 👀 Elegir una tabla para ver datos
    tabla = input("\n👉 Ingresa el nombre de la tabla que quieres ver: ")

    query_datos = f"SELECT * FROM {tabla} ORDER BY id DESC LIMIT 10;"
    datos = pd.read_sql(query_datos, conn)

    print(f"\n📊 Últimos registros de la tabla '{tabla}':")
    print(datos)

except Exception as e:
    print("❌ Error al conectar o consultar:", e)

finally:
    if 'conn' in locals():
        conn.close()
        print("\n🔒 Conexión cerrada.")
