-- Embroidery Module Schema
CREATE SCHEMA IF NOT EXISTS embroidery;

-- 1. Clients (same as design)
CREATE TABLE embroidery.clients (
  id SERIAL PRIMARY KEY,
  full_name VARCHAR(100) NOT NULL,
  phone VARCHAR(20) NOT NULL UNIQUE,
  address TEXT NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 2. Suppliers (same as design)
CREATE TABLE embroidery.suppliers (
  id SERIAL PRIMARY KEY,
  full_name VARCHAR(100) NOT NULL,
  phone VARCHAR(20) NOT NULL UNIQUE,
  address TEXT NOT NULL,
  company_name VARCHAR(100),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 3. Warehouses (same as design)
CREATE TABLE embroidery.warehouses (
  id SERIAL PRIMARY KEY,
  name VARCHAR(100) NOT NULL,
  type VARCHAR(20) NOT NULL CHECK (type IN ('ready','raw')),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 4. Material Management (reuse design)
CREATE TABLE embroidery.material_types (
  id SERIAL PRIMARY KEY,
  name VARCHAR(100) UNIQUE NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE embroidery.material_specs (
  id SERIAL PRIMARY KEY,
  type_id INT NOT NULL REFERENCES embroidery.material_types(id) ON DELETE CASCADE,
  name VARCHAR(100) NOT NULL,
  UNIQUE(type_id, name)
);

CREATE TABLE embroidery.materials (
  id SERIAL PRIMARY KEY,
  type_id INT NOT NULL REFERENCES embroidery.material_types(id),
  code VARCHAR(100) UNIQUE NOT NULL,
  image_url TEXT,
  stock_quantity FLOAT NOT NULL CHECK (stock_quantity >= 0),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE embroidery.material_spec_values (
  id SERIAL PRIMARY KEY,
  material_id INT NOT NULL REFERENCES embroidery.materials(id) ON DELETE CASCADE,
  spec_id INT NOT NULL REFERENCES embroidery.material_specs(id) ON DELETE CASCADE,
  value TEXT NOT NULL,
  UNIQUE(material_id, spec_id)
);

CREATE TABLE embroidery.raw_inventory (
  id SERIAL PRIMARY KEY,
  warehouse_id INT NOT NULL REFERENCES embroidery.warehouses(id),
  material_id INT NOT NULL REFERENCES embroidery.materials(id),
  quantity FLOAT NOT NULL CHECK (quantity >= 0),
  last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (warehouse_id, material_id)
);

-- 5. Models (embroidery-specific) must be defined before referencing
CREATE TABLE embroidery.models (
  id SERIAL PRIMARY KEY,
  model_date DATE NOT NULL,
  model_name VARCHAR(100) NOT NULL,
  stitch_price NUMERIC(10,2) NOT NULL CHECK(stitch_price >= 0),
  stitch_number INT NOT NULL CHECK(stitch_number >= 0),
  total_price NUMERIC(12,2) GENERATED ALWAYS AS (stitch_price * stitch_number) STORED,
  used_string NUMERIC(10,2) NOT NULL CHECK(used_string >= 0),
  description TEXT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 6. Product Inventory (same as design)
CREATE TABLE embroidery.product_inventory (
  id SERIAL PRIMARY KEY,
  warehouse_id INT NOT NULL REFERENCES embroidery.warehouses(id),
  model_id INT NOT NULL REFERENCES embroidery.models(id),
  color VARCHAR(50),
  size_label VARCHAR(20),
  quantity FLOAT NOT NULL CHECK (quantity >= 0),
  last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (warehouse_id, model_id, color, size_label)
);

-- 7. Purchases & Purchase Items & Payments (same as design)
CREATE TABLE embroidery.purchases (
  id SERIAL PRIMARY KEY,
  purchase_date DATE DEFAULT CURRENT_DATE,
  supplier_id INT NOT NULL REFERENCES embroidery.suppliers(id),
  amount_paid_on_creation NUMERIC(12,2) DEFAULT 0 CHECK (amount_paid_on_creation >= 0)
);

CREATE TABLE embroidery.purchase_items (
  id SERIAL PRIMARY KEY,
  purchase_id INT NOT NULL REFERENCES embroidery.purchases(id) ON DELETE CASCADE,
  material_id INT NOT NULL REFERENCES embroidery.materials(id),
  quantity FLOAT NOT NULL CHECK (quantity >= 0),
  unit_price NUMERIC(10,2) NOT NULL CHECK (unit_price >= 0)
);

CREATE TABLE embroidery.purchase_payments (
  id SERIAL PRIMARY KEY,
  purchase_id INT NOT NULL REFERENCES embroidery.purchases(id) ON DELETE CASCADE,
  amount_paid NUMERIC(12,2) NOT NULL CHECK(amount_paid >= 0),
  payment_date DATE DEFAULT CURRENT_DATE,
  method VARCHAR(50),
  notes TEXT
);

-- 8. Factures & Facture Items & Payments (same as design)
CREATE TABLE embroidery.factures (
  id SERIAL PRIMARY KEY,
  client_id INT NOT NULL REFERENCES embroidery.clients(id),
  facture_name VARCHAR(100) NOT NULL,
  facture_date DATE DEFAULT CURRENT_DATE,
  total_amount NUMERIC(12,2) NOT NULL CHECK(total_amount >= 0),
  amount_paid_on_creation NUMERIC(12,2) DEFAULT 0 CHECK(amount_paid_on_creation >= 0 AND amount_paid_on_creation <= total_amount)
);

CREATE TABLE embroidery.facture_items (
  id SERIAL PRIMARY KEY,
  facture_id INT NOT NULL REFERENCES embroidery.factures(id) ON DELETE CASCADE,
  model_id INT NOT NULL REFERENCES embroidery.models(id),
  color VARCHAR(50),
  quantity INT NOT NULL CHECK(quantity >= 0),
  unit_price NUMERIC(10,2) NOT NULL CHECK(unit_price >= 0)
);

CREATE TABLE embroidery.facture_payments (
  id SERIAL PRIMARY KEY,
  facture_id INT NOT NULL REFERENCES embroidery.factures(id) ON DELETE CASCADE,
  amount_paid NUMERIC(12,2) NOT NULL CHECK(amount_paid >= 0),
  payment_date DATE DEFAULT CURRENT_DATE,
  method VARCHAR(50),
  notes TEXT
);

-- 9. Seasons & Season Reports (same as design)
CREATE TABLE embroidery.seasons (
  id SERIAL PRIMARY KEY,
  name VARCHAR(100) NOT NULL,
  start_date DATE NOT NULL,
  end_date DATE NOT NULL
);

CREATE TABLE embroidery.season_reports (
  id SERIAL PRIMARY KEY,
  season_id INT NOT NULL REFERENCES embroidery.seasons(id),
  model_id INT NOT NULL REFERENCES embroidery.models(id),
  quantity_sold INT NOT NULL,
  total_revenue NUMERIC(12,2) NOT NULL,
  total_cost NUMERIC(12,2) NOT NULL,
  profit NUMERIC(12,2) NOT NULL,
  calculated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(season_id, model_id)
);

-- 10. Returns (same as design)
CREATE TABLE embroidery.returns (
  id SERIAL PRIMARY KEY,
  facture_id INT NOT NULL REFERENCES embroidery.factures(id) ON DELETE CASCADE,
  model_id INT NOT NULL REFERENCES embroidery.models(id),
  quantity INT NOT NULL CHECK(quantity > 0),
  return_date DATE DEFAULT CURRENT_DATE,
  is_ready_to_sell BOOLEAN NOT NULL DEFAULT FALSE,
  repair_materials JSONB,
  repair_cost NUMERIC(10,2) DEFAULT 0 CHECK(repair_cost >= 0),
  notes TEXT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX idx_returns_facture_id ON embroidery.returns(facture_id);
CREATE INDEX idx_returns_model_id ON embroidery.returns(model_id);
CREATE INDEX idx_returns_return_date ON embroidery.returns(return_date);

-- 11. Expenses (same as design)
CREATE TABLE embroidery.expenses (
  id SERIAL PRIMARY KEY,
  expense_type VARCHAR(50) NOT NULL CHECK(expense_type IN ('electricity','rent','water','maintenance','transport','custom','raw_materials')),
  description TEXT,
  amount NUMERIC(12,2) NOT NULL CHECK(amount >= 0),
  expense_date DATE NOT NULL DEFAULT CURRENT_DATE,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  material_type_id INT NULL REFERENCES embroidery.material_types(id) ON DELETE SET NULL,
  material_id INT NULL REFERENCES embroidery.materials(id) ON DELETE SET NULL,
  quantity NUMERIC(12,3) NULL,
  unit_price NUMERIC(12,3) NULL,
  CONSTRAINT chk_raw_materials_fields CHECK((expense_type <> 'raw_materials') OR (material_id IS NOT NULL AND quantity IS NOT NULL AND unit_price IS NOT NULL))
);

-- 12. Embroidery-specific tables
CREATE TABLE embroidery.stitch_types (
  id SERIAL PRIMARY KEY,
  name VARCHAR(50) NOT NULL UNIQUE,
  default_length NUMERIC(6,2) NOT NULL,
  default_speed INT NOT NULL
);

CREATE TABLE embroidery.thread_colors (
  id SERIAL PRIMARY KEY,
  code VARCHAR(20) UNIQUE NOT NULL,
  name VARCHAR(100) NOT NULL,
  rgb_hex CHAR(7) NOT NULL
);

CREATE TABLE embroidery.embroidery_patterns (
  id SERIAL PRIMARY KEY,
  name VARCHAR(100) NOT NULL,
  description TEXT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE embroidery.pattern_stitches (
  id SERIAL PRIMARY KEY,
  embroidery_pattern_id INT NOT NULL REFERENCES embroidery.embroidery_patterns(id) ON DELETE CASCADE,
  stitch_type_id INT NOT NULL REFERENCES embroidery.stitch_types(id),
  thread_color_id INT NOT NULL REFERENCES embroidery.thread_colors(id),
  sequence_order INT NOT NULL,
  length_override NUMERIC(6,2),
  notes TEXT
);

CREATE TABLE embroidery.embroidery_jobs (
  id SERIAL PRIMARY KEY,
  embroidery_pattern_id INT NOT NULL REFERENCES embroidery.embroidery_patterns(id),
  fabric_inventory_id INT NOT NULL REFERENCES embroidery.product_inventory(id),
  client_id INT NOT NULL REFERENCES embroidery.clients(id),
  start_date DATE NOT NULL,
  due_date DATE,
  status VARCHAR(20) NOT NULL DEFAULT 'pending',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 13. Employees & related tables (adjusted for shift hours)
CREATE TABLE embroidery.employees (
  id SERIAL PRIMARY KEY,
  first_name VARCHAR(100) NOT NULL,
  last_name VARCHAR(100) NOT NULL,
  phone VARCHAR(20) NOT NULL UNIQUE,
  address TEXT NOT NULL,
  payment_type VARCHAR(10) NOT NULL CHECK(payment_type IN ('monthly','stitchly')),
  salary NUMERIC(10,2),
  photo_url TEXT,
  status VARCHAR(20) DEFAULT 'active' CHECK(status IN ('active','inactive','deleted')),
  shift_hours INT NOT NULL CHECK(shift_hours IN (8,12)),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE embroidery.employee_attendance (
  id SERIAL PRIMARY KEY,
  employee_id INT REFERENCES embroidery.employees(id),
  check_in TIMESTAMP,
  check_out TIMESTAMP,
  date DATE NOT NULL,
  UNIQUE(employee_id, date)
);

CREATE TABLE embroidery.employee_loans (
  id SERIAL PRIMARY KEY,
  employee_id INT REFERENCES embroidery.employees(id),
  amount NUMERIC(10,2) NOT NULL CHECK(amount >= 0),
  loan_date DATE DEFAULT CURRENT_DATE,
  duration_months INT NOT NULL DEFAULT 1
);

CREATE TABLE embroidery.employee_loan_installments (
  id SERIAL PRIMARY KEY,
  loan_id INT NOT NULL REFERENCES embroidery.employee_loans(id) ON DELETE CASCADE,
  installment_no INT NOT NULL,
  due_date DATE NOT NULL,
  amount NUMERIC(10,2) NOT NULL CHECK(amount >= 0),
  is_paid BOOLEAN NOT NULL DEFAULT FALSE,
  paid_date DATE NULL
);

CREATE TABLE embroidery.employee_debts (
  id SERIAL PRIMARY KEY,
  employee_id INT REFERENCES embroidery.employees(id) ON DELETE CASCADE,
  amount NUMERIC(10,2) NOT NULL CHECK(amount >= 0),
  debt_date DATE NOT NULL DEFAULT CURRENT_DATE,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 14. Client credit payments (same as sewing)
CREATE TABLE embroidery.client_credit_payments (
  id SERIAL PRIMARY KEY,
  client_id INT REFERENCES embroidery.clients(id),
  amount DOUBLE PRECISION NOT NULL CHECK(amount > 0),
  payment_date DATE DEFAULT CURRENT_DATE,
  notes TEXT
);

-- 15. Piece records (same as sewing)
CREATE TABLE embroidery.piece_records (
  id SERIAL PRIMARY KEY,
  employee_id INT REFERENCES embroidery.employees(id),
  model_id INT REFERENCES embroidery.models(id),
  quantity INT NOT NULL CHECK(quantity >= 0),
  piece_price NUMERIC(10,2) NOT NULL CHECK(piece_price >= 0),
  record_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
ALTER TABLE embroidery.models
  ADD COLUMN model_type VARCHAR(20) NOT NULL
    DEFAULT 'سحبة'
    CHECK (model_type IN ('سحبة', 'حطة'));
ALTER TABLE embroidery.product_inventory
  ADD CONSTRAINT embroidery_product_inventory_unique UNIQUE (warehouse_id, model_id, color, size_label);


-- Set the search path to the embroidery schema
SET search_path TO embroidery;

-- Truncate all tables except for the warehouses table
TRUNCATE TABLE
  clients,
  suppliers,
  material_types,
  material_specs,
  materials,
  material_spec_values,
  raw_inventory,
  models,
  model_colors,
  product_inventory,
  purchases,
  purchase_items,
  purchase_payments,
  factures,
  facture_items,
  facture_payments,
  seasons,
  season_reports,
  expenses,
  returns,
  employee_debts,
  client_credit_payments,
  piece_records,
  employee_attendance,
  employees,
  employee_loans,
  employee_loan_installments
CASCADE;

-- Reset the IDs for the truncated tables to start from 1
ALTER SEQUENCE clients_id_seq RESTART WITH 1;
ALTER SEQUENCE suppliers_id_seq RESTART WITH 1;
ALTER SEQUENCE material_types_id_seq RESTART WITH 1;
ALTER SEQUENCE material_specs_id_seq RESTART WITH 1;
ALTER SEQUENCE materials_id_seq RESTART WITH 1;
ALTER SEQUENCE material_spec_values_id_seq RESTART WITH 1;
ALTER SEQUENCE raw_inventory_id_seq RESTART WITH 1;
ALTER SEQUENCE models_id_seq RESTART WITH 1;
ALTER SEQUENCE model_colors_id_seq RESTART WITH 1;
ALTER SEQUENCE product_inventory_id_seq RESTART WITH 1;
ALTER SEQUENCE purchases_id_seq RESTART WITH 1;
ALTER SEQUENCE purchase_items_id_seq RESTART WITH 1;
ALTER SEQUENCE purchase_payments_id_seq RESTART WITH 1;
ALTER SEQUENCE factures_id_seq RESTART WITH 1;
ALTER SEQUENCE facture_items_id_seq RESTART WITH 1;
ALTER SEQUENCE facture_payments_id_seq RESTART WITH 1;
ALTER SEQUENCE seasons_id_seq RESTART WITH 1;
ALTER SEQUENCE season_reports_id_seq RESTART WITH 1;
ALTER SEQUENCE expenses_id_seq RESTART WITH 1;
ALTER SEQUENCE returns_id_seq RESTART WITH 1;
ALTER SEQUENCE employee_debts_id_seq RESTART WITH 1;
ALTER SEQUENCE client_credit_payments_id_seq RESTART WITH 1;
ALTER SEQUENCE piece_records_id_seq RESTART WITH 1;
ALTER SEQUENCE employee_attendance_id_seq RESTART WITH 1;
ALTER SEQUENCE employees_id_seq RESTART WITH 1;
ALTER SEQUENCE employee_loans_id_seq RESTART WITH 1;
ALTER SEQUENCE employee_loan_installments_id_seq RESTART WITH 1;
