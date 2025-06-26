# Databases 201 — Session 2 (90 minutes)
**Building a Multi-Database E-commerce Platform: Data Modeling Decisions in Practice**

## Objective
Experience how the same business domain can be modeled across PostgreSQL (transactional), MongoDB (document), and Neo4j (graph) databases to understand when and why each approach excels. Build practical decision-making skills for database selection in real-world applications.

---

## Prerequisites and Environment Setup (5 minutes)

**Required Tools**: Docker Desktop 4+, bash shell with curl and unzip utilities

**Project Structure**:
```bash
# Create lab directory and data staging areas
mkdir -p db201/data/{postgres,mongo,neo4j}
cd db201
```

### Data Acquisition and Preprocessing

```bash
# Download Northwind CSV data for PostgreSQL and Neo4j
curl -L https://github.com/bitnine-oss/import-northwind/archive/refs/heads/master.zip -o nw.zip
unzip -qq nw.zip && rm nw.zip
cp import-northwind-master/*.csv data/postgres/
cp import-northwind-master/*.csv data/neo4j/
rm -rf import-northwind-master/

# Download JSON data for MongoDB
git clone --depth 1 https://github.com/jasny/mongodb-northwind.git
mv mongodb-northwind/json/*.json data/mongo/
rm -rf mongodb-northwind/

# Download Neo4j Cypher loading script
curl -L https://raw.githubusercontent.com/neo4j-graph-examples/northwind/main/scripts/northwind.cypher -o data/neo4j/northwind.cypher

# Clean CSV files: remove Windows line endings and trailing pipe delimiters
for f in data/postgres/*.csv data/neo4j/*.csv; do
  awk '{sub(/\r$/, ""); sub(/\|$/, ""); print}' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
done

echo "Data acquisition and preprocessing complete"
```

### Docker Compose Configuration

```yaml
services:
  postgresql_db:
    image: postgres:16
    container_name: postgresql_db
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: northwind
      POSTGRES_HOST_AUTH_METHOD: trust
    ports:
      - "5432:5432"
    volumes:
      - pgdata:/var/lib/postgresql/data
      - ./data/postgres:/dataset:ro
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres -d northwind"]
      interval: 5s
      timeout: 5s
      retries: 5

  mongodb:
    image: mongo:7
    container_name: mongodb_container
    ports:
      - "27017:27017"
    volumes:
      - mongodata:/data/db
      - ./data/mongo:/dataset:ro
    healthcheck:
      test: ["CMD", "mongosh", "--eval", "db.runCommand({ping: 1})"]
      interval: 10s
      timeout: 5s
      retries: 5

  neo4j:
    image: neo4j:5-community
    container_name: neo4j_container
    environment:
      NEO4J_AUTH: neo4j/password
      NEO4J_PLUGINS: '["apoc"]'
      NEO4J_server_directories_import: /var/lib/neo4j/import
    ports:
      - "7474:7474"
      - "7687:7687"
    volumes:
      - neo4jdata:/data
      - ./data/neo4j:/var/lib/neo4j/import
    healthcheck:
      test: ["CMD", "cypher-shell", "-u", "neo4j", "-p", "password", "RETURN 1"]
      interval: 10s
      timeout: 5s
      retries: 5

volumes:
  pgdata:
  mongodata:
  neo4jdata:
```

### Environment Startup

```bash
# Start all database containers
docker compose up -d

# Verify all systems are healthy
docker compose ps
```

**Expected Output**: All three containers should display "healthy" status, indicating successful startup and readiness for connections.

---

## Scenario Overview: E-commerce Platform Architecture (3 minutes)

**The Business Challenge**: You are architecting a modern e-commerce platform that must handle diverse data requirements efficiently. Different aspects of the business have fundamentally different characteristics that align with different database technologies.

**Architectural Strategy**: Rather than forcing all data into a single database technology, modern applications use polyglot persistence where each database handles the domain aspects where it naturally excels.

**Our Implementation**:
- **PostgreSQL**: Financial transactions, order processing, inventory management requiring ACID compliance
- **MongoDB**: Product catalogs with varying attributes, content management, flexible schemas
- **Neo4j**: Customer relationships, product recommendations, supply chain analysis

**🛑 PAUSE POINT**: This represents real-world architecture patterns where database choice follows data characteristics rather than organizational familiarity.

---

## Phase 1: Transactional Foundation with PostgreSQL (25 minutes)

### Understanding the Relational Approach

E-commerce transactions require strict ACID compliance to ensure financial integrity. Order processing, payment handling, and inventory management cannot tolerate data inconsistencies that might result in financial discrepancies or customer service issues.

```bash
# Connect to PostgreSQL
docker exec -it postgresql_db psql -U postgres -d northwind
```

### Schema Creation and Data Loading

```sql
-- Create normalized tables with foreign key constraints
CREATE TABLE customers (
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

CREATE TABLE products (
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

CREATE TABLE orders (
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

CREATE TABLE order_details (
    order_id INTEGER REFERENCES orders(order_id),
    product_id INTEGER REFERENCES products(product_id),
    list_price DECIMAL(10,2) NOT NULL,
    quantity INTEGER NOT NULL,
    discount REAL DEFAULT 0,
    PRIMARY KEY (order_id, product_id)
);
```
Load the sample data and verify it loaded successfully. Run each `COPY` command individually.
```sql
-- Load data using pipe delimiter format
\COPY customers FROM '/dataset/customers.csv' WITH (FORMAT csv, HEADER true, DELIMITER '|');
\COPY products FROM '/dataset/products.csv' WITH (FORMAT csv, HEADER true, DELIMITER '|');
\COPY orders FROM '/dataset/orders.csv' WITH (FORMAT csv, HEADER true, DELIMITER '|', NULL 'NULL');
\COPY order_details FROM '/dataset/order-details.csv' WITH (FORMAT csv, HEADER true, DELIMITER '|');

-- Verify data integrity
SELECT 'customers' as table_name, COUNT(*) as row_count FROM customers
UNION ALL
SELECT 'products', COUNT(*) FROM products  
UNION ALL
SELECT 'orders', COUNT(*) FROM orders
UNION ALL
SELECT 'order_details', COUNT(*) FROM order_details;
```

**🛑 PAUSE POINT**: Notice the strict schema definition with foreign key constraints. PostgreSQL enforces referential integrity automatically, preventing orphaned records and maintaining data consistency across related tables. The normalized structure eliminates data duplication but requires joins for comprehensive queries.

### Transactional Integrity Demonstration

```sql
-- Demonstrate ACID transaction handling for order processing
BEGIN;

-- First check if we have enough inventory
SELECT units_in_stock 
FROM products 
WHERE product_id = 1;

-- Create a new order and add order details atomically
-- If any step fails, the entire order is rolled back
INSERT INTO orders (
    customer_id, employee_id, order_date, required_date, 
    ship_name, ship_address, ship_city, ship_country, freight
) VALUES (
    'ALFKI', 5, CURRENT_DATE, CURRENT_DATE + INTERVAL '7 days',
    'Alfreds Futterkiste', 'Obere Str. 57', 'Berlin', 'Germany', 15.50
);

-- Add order details using the newly generated order ID
INSERT INTO order_details (
    order_id, product_id, list_price, quantity, discount
) VALUES (
    currval('orders_order_id_seq'), 1, 18.00, 10, 0.05
);

-- Safely update inventory with a check constraint
-- Will fail if not enough stock, rolling back the entire transaction
UPDATE products 
SET units_in_stock = units_in_stock - 10
WHERE product_id = 1 
AND units_in_stock >= 10;

-- If we reach here, all operations succeeded
-- The order is created, details added, and inventory updated as one atomic unit
COMMIT;

-- Verify the completed transaction (run after commit)
SELECT 
    o.order_id,
    o.customer_id,
    p.product_name,
    p.units_in_stock as remaining_stock,
    od.quantity as ordered_quantity
FROM orders o
JOIN order_details od ON o.order_id = od.order_id
JOIN products p ON od.product_id = p.product_id
WHERE o.order_id = currval('orders_order_id_seq');
```

**🛑 PAUSE POINT**: This transaction demonstrates ACID properties in action. Either all operations succeed together (order creation, line item addition, inventory update), or none take effect. The database guarantees consistency even if the system fails during processing. This atomic behavior is essential for financial accuracy in commerce applications.

### Complex Analytical Queries

```sql
-- PostgreSQL excels at complex analytics across normalized data
-- Customer analysis with order statistics
SELECT 
    c.company_name,
    c.country,
    COUNT(DISTINCT o.order_id) as total_orders,
    SUM(od.list_price * od.quantity * (1 - od.discount)) as total_revenue,
    AVG(od.list_price * od.quantity * (1 - od.discount)) as avg_order_value,
    MAX(o.order_date) as last_order_date
FROM customers c
JOIN orders o ON c.customer_id = o.customer_id
JOIN order_details od ON o.order_id = od.order_id
WHERE o.order_date >= '1997-01-01'
GROUP BY c.customer_id, c.company_name, c.country
HAVING COUNT(DISTINCT o.order_id) > 3
ORDER BY total_revenue DESC
LIMIT 15;

-- Product performance analysis across categories
SELECT 
    p.product_name,
    SUM(od.quantity) as total_quantity_sold,
    SUM(od.list_price * od.quantity * (1 - od.discount)) as total_revenue,
    COUNT(DISTINCT od.order_id) as order_frequency,
    AVG(od.discount) as avg_discount_rate
FROM products p
JOIN order_details od ON p.product_id = od.product_id
JOIN orders o ON od.order_id = o.order_id
WHERE o.order_date BETWEEN '1997-01-01' AND '1997-12-31'
GROUP BY p.product_id, p.product_name
HAVING SUM(od.quantity) > 100
ORDER BY total_revenue DESC;

-- Exit PostgreSQL
\q
```

**🛑 PAUSE POINT**: Complex joins and aggregations across multiple normalized tables showcase PostgreSQL's analytical strengths. The query optimizer efficiently processes relationships between entities while maintaining data integrity throughout the operation. These queries would be difficult to express and optimize in document or graph databases.

---

## Phase 2: Flexible Catalogs with MongoDB (25 minutes)

### Importing the Northwind Data into MongoDB

Before exploring the data, import all available Northwind collections into MongoDB:

```bash
# Import the full Northwind dataset into MongoDB
docker exec mongodb_container mongoimport --db northwind --collection customers --file /dataset/customers.json --drop
docker exec mongodb_container mongoimport --db northwind --collection products --file /dataset/products.json --drop
docker exec mongodb_container mongoimport --db northwind --collection orders --file /dataset/orders.json --drop
```

### Understanding Document-Oriented Modeling

The Northwind MongoDB data uses a flat, simple schema for products, customers, and orders. This makes it easy to query, but also highlights the differences from a relational model.

```bash
# Connect to MongoDB
docker exec -it mongodb_container mongosh
```

### Explore the Document Structure

```javascript
// Switch to the northwind database
use northwind

// Check collection sizes
db.customers.countDocuments()
db.products.countDocuments()
db.orders.countDocuments()

// Examine a product document
db.products.findOne()

// Examine a customer document
db.customers.findOne()

// Examine an order document
db.orders.findOne()
```

**🛑 PAUSE POINT**: Notice the flat structure—no nested subdocuments for category, pricing, or marketing. All fields are top-level.

---

### Querying and Indexing

```javascript
// Create indexes for common queries
db.products.createIndex({ category: 1, list_price: 1 })
db.products.createIndex({ discontinued: 1 })
db.products.createIndex({ supplier_ids: 1 })

// Find all Beverages under $20 that are not discontinued
db.products.find({
  category: "Beverages",
  list_price: { $lt: 20 },
  discontinued: false
})

// Find all products from supplier 4
db.products.find({
  supplier_ids: 4
})

// Find all products with reorder level below 10
db.products.find({
  reorder_level: { $lt: 10 }
})

// Text search on product name (requires text index)
db.products.createIndex({ product_name: "text" })
db.products.find({ $text: { $search: "chocolate" } })
```

---

### Aggregation Pipeline Analytics

```javascript
// Count products per category
db.products.aggregate([
  { $group: { _id: "$category", count: { $sum: 1 } } },
  { $sort: { count: -1 } }
])

// Average price per category
db.products.aggregate([
  { $group: { _id: "$category", avg_price: { $avg: "$list_price" } } },
  { $sort: { avg_price: -1 } }
])

// Top 5 most expensive products with customer data
// For each of the top 5 most expensive products, show the customers who have ordered them

db.products.aggregate([
  { $sort: { list_price: -1 } },
  { $limit: 5 },
  {
    $lookup: {
      from: "orders",
      let: { productId: "$_id" },
      pipeline: [
        { $match: { $expr: { $in: ["$$productId", "$details.product_id"] } } },
        {
          $lookup: {
            from: "customers",
            localField: "customer_id",
            foreignField: "_id",
            as: "customer"
          }
        },
        { $unwind: "$customer" },
        {
          $project: {
            _id: 0,
            customer_id: 1,
            "customer.company": 1,
            "customer.first_name": 1,
            "customer.last_name": 1,
            "customer.city": 1,
            "customer.country_region": 1
          }
        }
      ],
      as: "orders"
    }
  },
  {
    $project: {
      _id: 1,
      product_name: 1,
      list_price: 1,
      customers: "$orders.customer"
    }
  }
])

// Top customers by total order value, joined with customer info for readability
// This shows the customer's name and company, not just their ID

db.orders.aggregate([
  { $unwind: "$details" },
  { $group: {
      _id: "$customer_id",
      total_spent: { $sum: { $multiply: ["$details.unit_price", "$details.quantity"] } }
    }
  },
  { $sort: { total_spent: -1 } },
  {
    $lookup: {
      from: "customers",
      localField: "_id",
      foreignField: "_id",
      as: "customer"
    }
  },
  { $unwind: "$customer" },
  {
    $project: {
      _id: 0,
      customer_id: "$customer._id",
      company: "$customer.company",
      first_name: "$customer.first_name",
      last_name: "$customer.last_name",
      city: "$customer.city",
      country_region: "$customer.country_region",
      total_spent: 1
    }
  }
])
```

---

**🛑 PAUSE POINT**: These queries and aggregations reflect the real structure of your MongoDB Northwind data. They demonstrate how to work with flat schemas and embedded arrays (like `details` in orders) for analytics and reporting.

---

## Phase 3: Relationship Intelligence with Neo4j (25 minutes)

### Understanding Graph-Based Modeling

E-commerce platforms generate complex webs of relationships between customers, products, categories, suppliers, and orders. Traditional relational approaches require expensive multi-table joins to analyze these connections, while graph databases model relationships as first-class entities that can be efficiently traversed and analyzed.

```bash
# Connect to Neo4j
docker exec -it neo4j_container cypher-shell -u neo4j -p password
```

### Loading the Complete Graph Dataset

```sql
-- Import the complete Northwind dataset using the prepared Cypher script
-- This creates comprehensive nodes and relationships for the entire business domain
:source /var/lib/neo4j/import/northwind.cypher

-- Verify the graph structure and size
MATCH (n) RETURN labels(n)[0] AS node_type, count(*) AS count ORDER BY count DESC;

-- Examine the relationship types in the graph
CALL db.relationshipTypes();
```

**🛑 PAUSE POINT**: The Cypher import script has created a complete graph representation of the Northwind business domain with thousands of nodes and relationships. This comprehensive dataset enables meaningful analysis of customer behavior, product relationships, and supply chain patterns that would be difficult to achieve with synthetic examples.

### Relationship Analysis and Recommendations

```sql
-- Examine the actual data structure that was imported
MATCH (c:Customer) RETURN c LIMIT 3;
MATCH (p:Product) RETURN p LIMIT 3;
MATCH ()-[r]->() RETURN type(r), count(*) AS relationship_count ORDER BY relationship_count DESC;

-- Find customers who purchased similar products (collaborative filtering foundation)
MATCH (c1:Customer)-[:PURCHASED]->(o1:Order)-[:ORDERS]->(p:Product)
MATCH (c2:Customer)-[:PURCHASED]->(o2:Order)-[:ORDERS]->(p)
WHERE c1 <> c2
RETURN c1.companyName, c2.companyName, p.productName
ORDER BY c1.companyName, c2.companyName
LIMIT 20;

-- Generate product recommendations based on customer purchase patterns
MATCH (target:Customer {customerID: 'ALFKI'})-[:PURCHASED]->(target_order:Order)-[:ORDERS]->(purchased_product:Product)
MATCH (similar:Customer)-[:PURCHASED]->(similar_order:Order)-[:ORDERS]->(purchased_product)
MATCH (similar)-[:PURCHASED]->(rec_order:Order)-[:ORDERS]->(recommendation:Product)
WHERE target <> similar 
  AND NOT EXISTS((target)-[:PURCHASED]->(:Order)-[:ORDERS]->(recommendation))
RETURN DISTINCT recommendation.productName,
       COUNT(similar) as similar_customers,
       AVG(recommendation.unitPrice) as avg_price
ORDER BY similar_customers DESC, avg_price ASC
LIMIT 10;

-- Analyze geographic purchase patterns  
MATCH (c:Customer)-[:PURCHASED]->(o:Order)-[:ORDERS]->(p:Product)
RETURN c.country,
       COUNT(DISTINCT c) as customers,
       COUNT(DISTINCT p) as unique_products,
       COUNT(o) as total_orders,
       AVG(toFloat(o.freight)) as avg_shipping_cost
ORDER BY total_orders DESC
LIMIT 15;

-- Supply chain relationship analysis
MATCH (s:Supplier)-[:SUPPLIES]->(p:Product)
MATCH (c:Customer)-[:PURCHASED]->(o:Order)-[:ORDERS]->(p)
RETURN s.companyName, 
       s.country as supplier_country,
       COUNT(DISTINCT p) as products_supplied,
       COUNT(DISTINCT c) as customers_reached,
       COUNT(o) as total_orders_involving_products
ORDER BY customers_reached DESC, products_supplied DESC
LIMIT 10;
```

**🛑 PAUSE POINT**: These relationship queries demonstrate natural pattern matching across the complete business domain. The graph database efficiently traverses relationship paths to discover customer similarities, product affinities, and supply chain connections that would require complex multi-table joins and subqueries in relational databases.

### Advanced Graph Analytics

```sql
-- Customer influence analysis through purchase volume and diversity
MATCH (c:Customer)-[:PURCHASED]->(o:Order)-[:ORDERS]->(p:Product)
WITH c, 
     COUNT(DISTINCT p) as product_diversity,
     COUNT(o) as order_frequency,
     SUM(toFloat(o.freight)) as total_shipping_paid,
     COLLECT(DISTINCT p.categoryID) as categories_purchased
RETURN c.companyName,
       c.country,
       product_diversity,
       order_frequency,
       total_shipping_paid,
       SIZE(categories_purchased) as category_diversity,
       (product_diversity * order_frequency * SIZE(categories_purchased)) as influence_score
ORDER BY influence_score DESC
LIMIT 15;

-- Product centrality analysis (most connected in the business network)
MATCH (p:Product)
OPTIONAL MATCH (c:Customer)-[:PURCHASED]->(o:Order)-[:ORDERS]->(p)
OPTIONAL MATCH (s:Supplier)-[:SUPPLIES]->(p)
OPTIONAL MATCH (p)-[:PART_OF]->(cat:Category)
RETURN p.productName,
       COUNT(DISTINCT c) as customer_connections,
       COUNT(DISTINCT s) as supplier_connections,
       COUNT(DISTINCT cat) as category_connections,
       COUNT(DISTINCT o) as order_appearances,
       (COUNT(DISTINCT c) + COUNT(DISTINCT s) + COUNT(DISTINCT o)) as total_network_centrality
ORDER BY total_network_centrality DESC, customer_connections DESC
LIMIT 15;

-- Identify market opportunities through relationship gaps
MATCH (c:Customer)-[:PURCHASED]->(o:Order)-[:ORDERS]->(p:Product)-[:PART_OF]->(cat:Category)
WITH c, COLLECT(DISTINCT cat.categoryName) as purchased_categories
MATCH (all_cat:Category)
WHERE NOT all_cat.categoryName IN purchased_categories
RETURN c.companyName, 
       c.country,
       SIZE(purchased_categories) as categories_purchased,
       COLLECT(all_cat.categoryName) as untapped_categories,
       SIZE(COLLECT(all_cat.categoryName)) as opportunity_count
ORDER BY opportunity_count DESC, categories_purchased DESC
LIMIT 10;

-- Geographic clustering through shared business patterns
MATCH (c1:Customer)-[:PURCHASED]->(o1:Order)-[:ORDERS]->(p:Product)
MATCH (c2:Customer)-[:PURCHASED]->(o2:Order)-[:ORDERS]->(p)
WHERE c1.country = c2.country AND c1 <> c2
WITH c1.country as country,
     COUNT(DISTINCT p) as shared_products,
     COUNT(DISTINCT c1) + COUNT(DISTINCT c2) as customer_relationships
RETURN country,
       shared_products,
       customer_relationships,
       (shared_products * customer_relationships) as market_cohesion_score
ORDER BY market_cohesion_score DESC
LIMIT 10;

-- Exit Neo4j
:exit
```

**🛑 PAUSE POINT**: Graph analytics reveal business insights that are difficult or impossible to discover through traditional relational analysis. Influence scoring, market opportunity identification, and network centrality analysis become natural operations that scale efficiently as the relationship complexity grows. These patterns drive recommendation engines, market segmentation strategies, and business development initiatives.

---

## Database Selection Framework and Integration (10 minutes)

### Architectural Integration Patterns

Modern applications leverage multiple database technologies through well-defined integration patterns that maintain data consistency while optimizing each system for its strengths.

**Event-Driven Synchronization**: Changes in the transactional system trigger updates to other databases through message queues or event streams. Order completion in PostgreSQL triggers product catalog updates in MongoDB and relationship updates in Neo4j.

**API-Mediated Integration**: Applications access each database through dedicated microservices that encapsulate database-specific logic while presenting unified business interfaces. This pattern enables independent scaling and technology evolution.

**Batch Synchronization**: Periodic data pipeline processes ensure consistency across systems for analytics and reporting purposes while allowing each database to optimize for its primary workload.

### Decision Framework Application

**Choose PostgreSQL when you need**:
- ACID compliance for financial transactions and critical business operations
- Complex analytical queries across multiple related entities
- Regulatory compliance requiring audit trails and data integrity guarantees
- Mature ecosystem integration with existing enterprise tools and processes

**Choose MongoDB when you need**:
- Flexible schemas that evolve rapidly with changing business requirements
- Content management systems with varying document structures
- Geographic distribution through replica sets and sharding capabilities
- Development agility for prototyping and iterative feature development

**Choose Neo4j when you need**:
- Relationship analysis for recommendation engines and personalization systems
- Social network analysis and community detection algorithms
- Fraud detection through connection pattern analysis
- Knowledge graphs and semantic data modeling for complex domain relationships

**Integration Considerations**:
- Data consistency requirements across database boundaries and acceptable consistency models
- Performance implications of cross-system queries and synchronization overhead
- Operational complexity of managing multiple database technologies and monitoring systems
- Team expertise development and ongoing maintenance capability requirements

**🛑 PAUSE POINT**: Database technology selection should align with specific data patterns and access requirements rather than defaulting to familiar technologies. Each database type provides distinct advantages when applied to appropriate use cases within the same business domain.

---

## Key Takeaways and Practical Applications (7 minutes)

### Demonstrated Architectural Patterns

The laboratory exercises demonstrate that modern database architecture requires matching technology capabilities to specific business requirements rather than forcing all data into a single database paradigm. Each database type excels in different dimensions that reflect fundamental differences in data structure and access pattern optimization.

**Relational Database Strengths**: ACID transaction guarantees, complex analytical capabilities across normalized data, and mature ecosystem integration make PostgreSQL essential for financial accuracy and regulatory compliance requirements.

**Document Database Advantages**: Schema flexibility, nested data structure support, and horizontal scaling capabilities make MongoDB valuable for content management and rapidly evolving application requirements.

**Graph Database Capabilities**: Relationship modeling, pattern matching, and traversal efficiency make Neo4j powerful for recommendation systems and network analysis applications that require understanding connections between entities.

### Real-World Implementation Guidance

Modern e-commerce platforms commonly employ polyglot persistence architectures where each database technology handles the aspects of the business domain where it naturally excels. The integration challenges involve maintaining data consistency across database boundaries while enabling each system to optimize for its primary workload characteristics.

**Immediate Action Items**: Review current projects to identify opportunities where alternative database technologies might provide superior capabilities compared to existing monolithic database approaches. Consider whether data access patterns align with current technology choices or whether specialized databases could improve performance and development velocity.

**Strategic Development**: Build organizational capabilities across multiple database paradigms to enable technology selection based on technical requirements rather than familiarity constraints. Invest in integration patterns and operational expertise that support polyglot persistence architectures effectively.

---

## Environment Cleanup

```bash
# Stop all database containers and remove volumes
docker compose down -v

# Remove all Docker volumes created for the lab (optional, irreversible)
docker volume rm $(docker volume ls -qf 'name=db201')

# Remove all unused Docker volumes (including anonymous ones)
docker volume prune -f

# Optional: Remove downloaded data files
rm -rf data/
```

The laboratory environment can be quickly recreated by repeating the data acquisition and container startup procedures, enabling repeated practice with the demonstrated concepts and techniques.

## Cross-Database Comparison: Top Customers by Total Order Value

| Database      | Description                                                                 |
|---------------|-----------------------------------------------------------------------------|
| PostgreSQL    | Uses SQL joins and aggregation to sum order values per customer.            |
| MongoDB       | Aggregates order details, then joins with customers for readable output.    |
| Neo4j         | Traverses relationships and sums order values per customer.                 |

---

**PostgreSQL**
```sql
SELECT c.company_name, SUM(od.list_price * od.quantity * (1 - od.discount)) AS total_spent
FROM customers c
JOIN orders o ON c.customer_id = o.customer_id
JOIN order_details od ON o.order_id = od.order_id
GROUP BY c.company_name
ORDER BY total_spent DESC
LIMIT 10;
```

**MongoDB**
```javascript
db.orders.aggregate([
  { $unwind: "$details" },
  { $group: {
      _id: "$customer_id",
      total_spent: { $sum: { $multiply: ["$details.unit_price", "$details.quantity"] } }
    }
  },
  { $sort: { total_spent: -1 } },
  {
    $lookup: {
      from: "customers",
      localField: "_id",
      foreignField: "_id",
      as: "customer"
    }
  },
  { $unwind: "$customer" },
  {
    $project: {
      _id: 0,
      company: "$customer.company",
      total_spent: 1
    }
  },
  { $limit: 10 }
])
```

**Neo4j**
```sql
MATCH (c:Customer)-[:PURCHASED]->(o:Order)-[:ORDERS]->(p:Product)
WITH c, SUM(o.freight + REDUCE(total = 0, od IN o.orderDetails | total + od.unitPrice * od.quantity * (1 - od.discount))) AS total_spent
RETURN c.companyName, total_spent
ORDER BY total_spent DESC
LIMIT 10;
```

This section demonstrates how a common business question is answered in each database, highlighting differences in query language and approach.