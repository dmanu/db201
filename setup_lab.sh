#!/bin/bash
set -e

# 1. Create lab directories if not present
mkdir -p data/{postgres,mongo,neo4j}

# 2. Download and extract Northwind CSV data for PostgreSQL and Neo4j
if [ ! -f data/postgres/customers.csv ]; then
  echo "Downloading Northwind CSV data..."
  curl -L https://github.com/bitnine-oss/import-northwind/archive/refs/heads/master.zip -o nw.zip
  unzip -qq nw.zip && rm nw.zip
  cp import-northwind-master/*.csv data/postgres/
  cp import-northwind-master/*.csv data/neo4j/
  rm -rf import-northwind-master/
fi

# 3. Download MongoDB JSON data
if [ ! -f data/mongo/customers.json ]; then
  echo "Downloading MongoDB JSON data..."
  git clone --depth 1 https://github.com/jasny/mongodb-northwind.git
  mv mongodb-northwind/json/*.json data/mongo/
  rm -rf mongodb-northwind/
fi

# 4. Download Neo4j Cypher loading script
if [ ! -f data/neo4j/northwind.cypher ]; then
  echo "Downloading Neo4j Cypher script..."
  curl -L https://raw.githubusercontent.com/neo4j-graph-examples/northwind/main/scripts/northwind.cypher -o data/neo4j/northwind.cypher
fi

# 5. Start Docker Compose
echo "Starting Docker Compose..."
docker compose up -d

# 6. Wait for PostgreSQL to be ready
echo "Waiting for PostgreSQL to be ready..."
until docker exec -u postgres postgresql_db pg_isready -d postgres; do
  sleep 2
done

# 7. Ensure northwind database exists
echo "Ensuring northwind database exists..."
docker exec -u postgres postgresql_db psql -tc "SELECT 1 FROM pg_database WHERE datname = 'northwind';" | grep -q 1 || \
  docker exec -u postgres postgresql_db psql -c "CREATE DATABASE northwind;"

# 8. Wait for northwind database to be ready
until docker exec -u postgres postgresql_db pg_isready -d northwind; do
  sleep 2
done

echo "Importing data into MongoDB..."
docker exec mongodb_container mongoimport --db northwind --collection customers --file /dataset/customers.json --drop
docker exec mongodb_container mongoimport --db northwind --collection products --file /dataset/products.json --drop
docker exec mongodb_container mongoimport --db northwind --collection orders --file /dataset/orders.json --drop

echo "Writing PostgreSQL schema to temp file..."
cat > /tmp/northwind_schema.sql <<'EOF'
CREATE TABLE IF NOT EXISTS customers (
    customer_id VARCHAR(5) PRIMARY KEY,
    company_name VARCHAR(40) NOT NULL,
    contact_name VARCHAR(30),
    contact_title VARCHAR(30),
    address VARCHAR(60),
    city VARCHAR(15),
    region VARCHAR(15),
    postal_code VARCHAR(10),
    country VARCHAR(15),
    phone VARCHAR(24),
    fax VARCHAR(24)
);

CREATE TABLE IF NOT EXISTS products (
    product_id SERIAL PRIMARY KEY,
    product_name VARCHAR(40) NOT NULL,
    supplier_id INTEGER,
    category_id INTEGER,
    quantity_per_unit VARCHAR(20),
    list_price DECIMAL(10,2),
    units_in_stock INTEGER,
    units_on_order INTEGER,
    reorder_level INTEGER,
    discontinued BOOLEAN DEFAULT FALSE
);

CREATE TABLE IF NOT EXISTS orders (
    order_id SERIAL PRIMARY KEY,
    customer_id VARCHAR(5) REFERENCES customers(customer_id),
    employee_id INTEGER,
    order_date DATE,
    required_date DATE,
    shipped_date DATE,
    ship_via INTEGER,
    freight DECIMAL(10,2),
    ship_name VARCHAR(40),
    ship_address VARCHAR(60),
    ship_city VARCHAR(15),
    ship_region VARCHAR(15),
    ship_postal_code VARCHAR(10),
    ship_country VARCHAR(15)
);

CREATE TABLE IF NOT EXISTS order_details (
    order_id INTEGER REFERENCES orders(order_id),
    product_id INTEGER REFERENCES products(product_id),
    list_price DECIMAL(10,2) NOT NULL,
    quantity INTEGER NOT NULL,
    discount REAL DEFAULT 0,
    PRIMARY KEY (order_id, product_id)
);
EOF

echo "Copying schema file into the container..."
docker cp /tmp/northwind_schema.sql postgresql_db:/northwind_schema.sql

echo "Creating PostgreSQL tables..."
docker exec -u postgres postgresql_db psql -d northwind -f /northwind_schema.sql

echo "Truncating PostgreSQL tables before import..."
docker exec -u postgres postgresql_db psql -d northwind -c "TRUNCATE order_details, orders, products, customers RESTART IDENTITY CASCADE;"

echo "Importing data into PostgreSQL..."
docker exec -u postgres postgresql_db psql -d northwind -c "\COPY customers FROM '/dataset/customers.csv' WITH (FORMAT csv, HEADER true, DELIMITER '|');"
docker exec -u postgres postgresql_db psql -d northwind -c "\COPY products FROM '/dataset/products.csv' WITH (FORMAT csv, HEADER true, DELIMITER '|');"
docker exec -u postgres postgresql_db psql -d northwind -c "\COPY orders FROM '/dataset/orders.csv' WITH (FORMAT csv, HEADER true, DELIMITER '|', NULL 'NULL');"
docker exec -u postgres postgresql_db psql -d northwind -c "\COPY order_details FROM '/dataset/order-details.csv' WITH (FORMAT csv, HEADER true, DELIMITER '|');"

echo "Importing data into Neo4j..."
docker exec -i neo4j_container cypher-shell -u neo4j -p password < data/neo4j/northwind.cypher

echo "Lab setup complete. You can now connect to your databases!" 