PostgreSQL Multi-Tenant E-Commerce Capstone Project
1. Project Overview

The Multi-Tenant E-Commerce Management System is a database-driven application designed to support multiple businesses operating independently on one shared platform.

Each business can manage its own customers, products, inventory, orders and payments while keeping its information isolated from other businesses.

Technologies Used
PostgreSQL – Primary relational database.
Redis – Shopping cart and caching.
Flyway – Database migrations.
SQL and PL/pgSQL – Database operations.
GitHub – Version control and documentation.
Linux – Command-line administration.
DAY 1: REQUIREMENTS AND ER DIAGRAM
2. Requirements Summary
Functional Requirements
Businesses can register and manage their accounts.
Each business can add, update and manage products.
Customers can browse available products.
Customers can add products to shopping carts.
Customers can place orders.
The system records payments and order details.
Businesses can monitor inventory levels.
Administrators can view audit records.
Each business can access only its own private records.
The system supports order and sales reporting.
Non-Functional Requirements
Security through PostgreSQL Row-Level Security.
Data integrity through primary and foreign keys.
Performance through appropriate database indexes.
Availability through backups and recovery procedures.
Scalability through Redis caching.
Maintainability through Flyway migrations.
Accountability through database audit logging.
3. Entity Relationship Diagram

The system contains the following entities:

Tenants
Customers
Products
Orders
Order Items
Payments
Inventory
Audit Log
ER Diagram
mermaid
erDiagram
    TENANTS ||--o{ CUSTOMERS : owns
    TENANTS ||--o{ PRODUCTS : owns
    TENANTS ||--o{ ORDERS : owns
    CUSTOMERS ||--o{ ORDERS : places
    ORDERS ||--|{ ORDER_ITEMS : contains
    PRODUCTS ||--o{ ORDER_ITEMS : included_in
    ORDERS ||--o{ PAYMENTS : receives
    PRODUCTS ||--o| INVENTORY : has

    TENANTS {
        bigint id PK
        varchar name
        timestamp created_at
    }

    CUSTOMERS {
        bigint id PK
        bigint tenant_id FK
        varchar name
        varchar email
    }

    PRODUCTS {
        bigint id PK
        bigint tenant_id FK
        varchar name
        numeric price
    }

    ORDERS {
        bigint id PK
        bigint tenant_id FK
        bigint customer_id FK
        varchar status
        timestamp created_at
    }

    ORDER_ITEMS {
        bigint id PK
        bigint tenant_id FK
        bigint order_id FK
        bigint product_id FK
        integer quantity
        numeric unit_price
    }

    PAYMENTS {
        bigint id PK
        bigint tenant_id FK
        bigint order_id FK
        numeric amount
        varchar status
    }

    INVENTORY {
        bigint id PK
        bigint tenant_id FK
        bigint product_id FK
        integer quantity
    }


Diagram tool: https://dbdiagram.io/

DAY 2: SCHEMA AS FLYWAY MIGRATIONS
4. Project Folder Structure
text
capstone/
│
├── README.md
├── flyway.conf
│
├── migrations/
│   ├── V1__core_tables.sql
│   ├── V2__indexes.sql
│   ├── V3__audit_and_triggers.sql
│   ├── V4__row_level_security.sql
│   └── V5__seed_demo_data.sql
│
├── scripts/
│   └── backup.sh
│
├── docs/
│   ├── requirements.md
│   ├── er_diagram.md
│   └── performance_report.md
│
└── screenshots/

5. V1__core_tables.sql
sql
CREATE TABLE tenants (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name VARCHAR(150) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE customers (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id BIGINT NOT NULL REFERENCES tenants(id),
    name VARCHAR(150) NOT NULL,
    email VARCHAR(200) NOT NULL,
    UNIQUE (tenant_id, email),
    UNIQUE (tenant_id, id)
);

CREATE TABLE products (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id BIGINT NOT NULL REFERENCES tenants(id),
    name VARCHAR(150) NOT NULL,
    price NUMERIC(12,2) NOT NULL CHECK (price >= 0),
    UNIQUE (tenant_id, id)
);

CREATE TABLE orders (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id BIGINT NOT NULL REFERENCES tenants(id),
    customer_id BIGINT NOT NULL,
    status VARCHAR(30) DEFAULT 'pending',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (tenant_id, id),
    FOREIGN KEY (tenant_id, customer_id)
        REFERENCES customers(tenant_id, id)
);

CREATE TABLE order_items (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id BIGINT NOT NULL REFERENCES tenants(id),
    order_id BIGINT NOT NULL,
    product_id BIGINT NOT NULL,
    quantity INT NOT NULL CHECK (quantity > 0),
    unit_price NUMERIC(12,2) NOT NULL,
    FOREIGN KEY (tenant_id, order_id)
        REFERENCES orders(tenant_id, id),
    FOREIGN KEY (tenant_id, product_id)
        REFERENCES products(tenant_id, id)
);

CREATE TABLE inventory (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id BIGINT NOT NULL REFERENCES tenants(id),
    product_id BIGINT NOT NULL,
    quantity INT NOT NULL DEFAULT 0 CHECK (quantity >= 0),
    UNIQUE (tenant_id, product_id),
    FOREIGN KEY (tenant_id, product_id)
        REFERENCES products(tenant_id, id)
);

CREATE TABLE payments (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id BIGINT NOT NULL REFERENCES tenants(id),
    order_id BIGINT NOT NULL,
    amount NUMERIC(12,2) NOT NULL CHECK (amount >= 0),
    status VARCHAR(30) DEFAULT 'pending',
    FOREIGN KEY (tenant_id, order_id)
        REFERENCES orders(tenant_id, id)
);

6. V2__indexes.sql
sql
CREATE INDEX idx_customers_tenant
ON customers(tenant_id);

CREATE INDEX idx_products_tenant
ON products(tenant_id);

CREATE INDEX idx_orders_tenant_date
ON orders(tenant_id, created_at DESC);

CREATE INDEX idx_order_items_order
ON order_items(tenant_id, order_id);

CREATE INDEX idx_payments_order
ON payments(tenant_id, order_id);

CREATE INDEX idx_inventory_product
ON inventory(tenant_id, product_id);

7. V3__audit_and_triggers.sql
sql
CREATE TABLE audit_log (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id BIGINT,
    tbl TEXT NOT NULL,
    op TEXT NOT NULL,
    old_row JSONB,
    new_row JSONB,
    changed_by TEXT DEFAULT current_user,
    at TIMESTAMPTZ DEFAULT NOW()
);

CREATE OR REPLACE FUNCTION audit_changes()
RETURNS TRIGGER AS $$
DECLARE
    v_old JSONB;
    v_new JSONB;
    v_row JSONB;
    v_tenant_id BIGINT;
BEGIN
    IF TG_OP IN ('UPDATE', 'DELETE') THEN
        v_old := to_jsonb(OLD);
    END IF;

    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        v_new := to_jsonb(NEW);
    END IF;

    v_row := COALESCE(v_new, v_old);
    v_tenant_id := NULLIF(v_row->>'tenant_id', '')::BIGINT;

    INSERT INTO audit_log(
        tenant_id, tbl, op, old_row, new_row
    )
    VALUES (
        v_tenant_id, TG_TABLE_NAME, TG_OP, v_old, v_new
    );

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_customers_audit
AFTER INSERT OR UPDATE OR DELETE ON customers
FOR EACH ROW EXECUTE FUNCTION audit_changes();

CREATE TRIGGER trg_products_audit
AFTER INSERT OR UPDATE OR DELETE ON products
FOR EACH ROW EXECUTE FUNCTION audit_changes();

CREATE TRIGGER trg_orders_audit
AFTER INSERT OR UPDATE OR DELETE ON orders
FOR EACH ROW EXECUTE FUNCTION audit_changes();

8. V4__row_level_security.sql

Enable Row-Level Security:

sql
ALTER TABLE customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory ENABLE ROW LEVEL SECURITY;
ALTER TABLE payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;

ALTER TABLE customers FORCE ROW LEVEL SECURITY;
ALTER TABLE products FORCE ROW LEVEL SECURITY;
ALTER TABLE orders FORCE ROW LEVEL SECURITY;
ALTER TABLE order_items FORCE ROW LEVEL SECURITY;
ALTER TABLE inventory FORCE ROW LEVEL SECURITY;
ALTER TABLE payments FORCE ROW LEVEL SECURITY;
ALTER TABLE audit_log FORCE ROW LEVEL SECURITY;


Create tenant-specific policies:

sql
CREATE POLICY customers_tenant_policy ON customers
USING (
    tenant_id = NULLIF(
        current_setting('app.tenant_id', true), ''
    )::BIGINT
)
WITH CHECK (
    tenant_id = NULLIF(
        current_setting('app.tenant_id', true), ''
    )::BIGINT
);

CREATE POLICY products_tenant_policy ON products
USING (
    tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::BIGINT
)
WITH CHECK (
    tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::BIGINT
);

CREATE POLICY orders_tenant_policy ON orders
USING (
    tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::BIGINT
)
WITH CHECK (
    tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::BIGINT
);

CREATE POLICY order_items_tenant_policy ON order_items
USING (
    tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::BIGINT
)
WITH CHECK (
    tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::BIGINT
);

CREATE POLICY inventory_tenant_policy ON inventory
USING (
    tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::BIGINT
)
WITH CHECK (
    tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::BIGINT
);

CREATE POLICY payments_tenant_policy ON payments
USING (
    tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::BIGINT
)
WITH CHECK (
    tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::BIGINT
);

CREATE POLICY audit_tenant_policy ON audit_log
USING (
    tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::BIGINT
)
WITH CHECK (
    tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::BIGINT
);


Tenant context example:

sql
BEGIN;

SET LOCAL app.tenant_id = '1';

SELECT * FROM customers;

COMMIT;


The application must set the tenant context using a trusted authenticated identity. Use a restricted application role, not a superuser or table owner, for normal access.

9. V5__seed_demo_data.sql
sql
INSERT INTO tenants (name)
VALUES
('Business One'),
('Business Two');

INSERT INTO customers (tenant_id, name, email)
VALUES
(1, 'John Doe', 'john@example.com'),
(1, 'Mary Smith', 'mary@example.com'),
(2, 'Peter Brown', 'peter@example.com');

INSERT INTO products (tenant_id, name, price)
VALUES
(1, 'Laptop', 85000.00),
(1, 'Keyboard', 2500.00),
(2, 'T-Shirt', 1500.00);

INSERT INTO inventory (tenant_id, product_id, quantity)
VALUES
(1, 1, 20),
(1, 2, 50),
(2, 3, 100);

INSERT INTO orders (tenant_id, customer_id, status)
VALUES
(1, 1, 'pending'),
(1, 2, 'completed'),
(2, 3, 'pending');

INSERT INTO order_items
(tenant_id, order_id, product_id, quantity, unit_price)
VALUES
(1, 1, 1, 1, 85000.00),
(1, 2, 2, 2, 2500.00),
(2, 3, 3, 1, 1500.00);

INSERT INTO payments (tenant_id, order_id, amount, status)
VALUES
(1, 1, 85000.00, 'pending'),
(1, 2, 5000.00, 'paid'),
(2, 3, 1500.00, 'paid');

10. Flyway Configuration and Execution

Create flyway.conf:

properties
flyway.url=jdbc:postgresql://localhost:5432/capstone
flyway.user=postgres
flyway.password=YOUR_PASSWORD
flyway.locations=filesystem:migrations
flyway.cleanDisabled=false


Run migrations:

bash
flyway clean migrate


Check migration status:

bash
flyway info


Expected migrations:

Migration	Description
V1	Core tables
V2	Indexes
V3	Audit and triggers
V4	Row-Level Security
V5	Seed demo data

WARNING: flyway clean deletes database objects in configured schemas. Use only on a disposable development database. Keep credentials out of GitHub.

DAY 3: ADD THE NOSQL LAYER
11. Redis Integration

Redis is used for shopping carts, temporary sessions and frequently accessed product information.

Why Redis?
Fast in-memory data access.
Reduces repeated PostgreSQL queries.
Supports temporary shopping cart storage.
Provides automatic expiration of cached information.

Start Redis:

bash
redis-cli


Store shopping cart information:

redis
HSET cart:customer:1 product:1 2
HSET cart:customer:1 product:2 1


View shopping cart:

redis
HGETALL cart:customer:1


Cache product information:

redis
SET product:1 "Laptop - 85000" EX 300


Retrieve cached product:

redis
GET product:1

Architecture Decision

PostgreSQL remains the main source of truth for customers, orders, payments and inventory.

Redis handles temporary shopping carts and caching to improve application performance.

DAY 4: OPTIMIZE AND PROVE IT
12. Query Optimization

Use EXPLAIN ANALYZE to examine database query performance.

Query 1: Retrieve tenant orders

Before optimization:

sql
EXPLAIN ANALYZE
SELECT *
FROM orders
WHERE tenant_id = 1;


Create an index:

sql
CREATE INDEX idx_orders_tenant
ON orders(tenant_id);


After optimization:

sql
EXPLAIN ANALYZE
SELECT *
FROM orders
WHERE tenant_id = 1;

Query 2: Retrieve recent orders
sql
EXPLAIN ANALYZE
SELECT *
FROM orders
WHERE tenant_id = 1
ORDER BY created_at DESC
LIMIT 20;


Optimization index:

sql
CREATE INDEX idx_orders_tenant_date
ON orders(tenant_id, created_at DESC);

Performance Report

For every optimized query, document:

QUERY: What question it answers.
BEFORE PLAN: Initial EXPLAIN ANALYZE output.
CHANGE: Index added or query rewritten.
AFTER PLAN: Updated EXPLAIN ANALYZE output.
RESULT: Actual execution time before and after optimization.

Do not invent performance measurements. Use actual results from your PostgreSQL environment.

DAY 5: BACKUP, SECURITY AND PRESENTATION
13. Database Backup Script

Create a file called scripts/backup.sh.

bash
#!/bin/bash

mkdir -p backups

pg_dump -Fc \
-f "backups/capstone_$(date +%F).dump" \
capstone

echo "Database backup completed."


Make the script executable:

bash
chmod +x scripts/backup.sh


Run backup:

bash
./scripts/backup.sh


Verify backup:

bash
pg_restore --list backups/capstone_$(date +%F).dump | head


Test restoration:

bash
createdb capstone_test

pg_restore -d capstone_test \
backups/capstone_$(date +%F).dump

14. Security Checklist
Least-privilege roles (no application superuser).
RLS enabled on all tenant-owned tables.
Sensitive fields hashed or encrypted.
Audit log on critical tables.
Parameterized queries only.
Backups taken and test restore performed.
Redis protected with authentication.
Database credentials excluded from GitHub.
15. Final Project Presentation

The project presentation should cover:

Introduction to the e-commerce management system.
Requirements and ER diagram.
PostgreSQL schema and Flyway migrations.
Redis shopping cart and caching.
Row-Level Security and tenant isolation.
Audit logging and triggers.
Query optimization and performance evidence.
Database backup and restoration.
16. Expected GitHub Repository Structure
text
postgresql-ecommerce-capstone/
│
├── README.md
│
├── migrations/
│   ├── V1__core_tables.sql
│   ├── V2__indexes.sql
│   ├── V3__audit_and_triggers.sql
│   ├── V4__row_level_security.sql
│   └── V5__seed_demo_data.sql
│
├── scripts/
│   └── backup.sh
│
├── docs/
│   ├── requirements.md
│   ├── er_diagram.md
│   └── performance_report.md
│
└── screenshots/
    ├── migrations.png
    ├── audit_log.png
    ├── categories.png
    └── backup_restore.png

17. Conclusion

This capstone project demonstrates the complete lifecycle of a modern database system, from requirements gathering and ER diagram design to schema implementation, optimization, security and disaster recovery.

The project demonstrates:

Relational database design.
Version-controlled database migrations.
NoSQL integration using Redis.
Query performance optimization.
Multi-tenant security using PostgreSQL RLS.
Audit logging using database triggers.
Database backup and recovery.

The completed system provides a foundation for building a secure, scalable and maintainable multi-tenant e-commerce platform.

Repository Information

Project Name: PostgreSQL Multi-Tenant E-Commerce Capstone

Database: PostgreSQL

NoSQL: Redis

Migration Tool: Flyway

Author: [Your Name]

GitHub Repository: [Add your repository link]

Project Status: Prepared for practical implementation and verification.
