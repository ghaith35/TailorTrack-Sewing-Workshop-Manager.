-- =========================================
-- Schema Setup
-- =========================================
CREATE SCHEMA IF NOT EXISTS sewing;
SET search_path TO sewing;

-- =========================================
-- 1. Clients
-- =========================================
CREATE TABLE clients (
  id SERIAL PRIMARY KEY,
  full_name VARCHAR(100) NOT NULL,
  phone VARCHAR(20) NOT NULL UNIQUE,
  address TEXT NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- =========================================
-- 2. Warehouses
-- =========================================
CREATE TABLE warehouses (
  id SERIAL PRIMARY KEY,
  name VARCHAR(100) NOT NULL,
  type VARCHAR(20) NOT NULL CHECK (type IN ('ready', 'raw')),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- =========================================
-- 3. Suppliers
-- =========================================
CREATE TABLE suppliers (
  id SERIAL PRIMARY KEY,
  full_name VARCHAR(100) NOT NULL,
  phone VARCHAR(20) NOT NULL UNIQUE,
  address TEXT NOT NULL,
  company_name VARCHAR(100),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- =========================================
-- 4. Models
-- =========================================
CREATE TABLE models (
  id SERIAL PRIMARY KEY,
  name VARCHAR(100) NOT NULL UNIQUE,
  start_date DATE NOT NULL,
  image_url TEXT,
  cut_price NUMERIC(10,2) NOT NULL CHECK (cut_price >= 0),
  sewing_price NUMERIC(10,2) NOT NULL CHECK (sewing_price >= 0),
  press_price NUMERIC(10,2) NOT NULL CHECK (press_price >= 0),
  assembly_price NUMERIC(10,2) NOT NULL CHECK (assembly_price >= 0),
  electricity NUMERIC(10,2) NOT NULL,
  rent NUMERIC(10,2) NOT NULL,
  maintenance NUMERIC(10,2) NOT NULL,
  water NUMERIC(10,2) NOT NULL,
  washing NUMERIC(10,2),
  embroidery NUMERIC(10,2),
  laser NUMERIC(10,2),
  printing NUMERIC(10,2),
  crochet NUMERIC(10,2),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  sizes TEXT,
  nbr_of_sizes INT NOT NULL DEFAULT 0
);

CREATE TABLE model_colors (
  id SERIAL PRIMARY KEY,
  model_id INT REFERENCES models(id) ON DELETE CASCADE,
  color VARCHAR(50) NOT NULL,
  UNIQUE (model_id, color)
);

-- =========================================
-- 5. Product Inventory
-- =========================================
CREATE TABLE product_inventory (
  id SERIAL PRIMARY KEY,
  warehouse_id INT REFERENCES warehouses(id),
  model_id INT REFERENCES models(id),
  sizes TEXT,
  quantity FLOAT NOT NULL CHECK (quantity >= 0),
  last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  nbr_of_sizes INT NOT NULL DEFAULT 0,
  color VARCHAR(50) NOT NULL DEFAULT '',
  size VARCHAR(20),
  CONSTRAINT unique_warehouse_model_color_size UNIQUE (warehouse_id, model_id, color, size)
);

-- =========================================
-- 6. Material Management
-- =========================================
CREATE TABLE material_types (
  id SERIAL PRIMARY KEY,
  name VARCHAR(100) UNIQUE NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE material_specs (
  id SERIAL PRIMARY KEY,
  type_id INT REFERENCES material_types(id) ON DELETE CASCADE,
  name VARCHAR(100) NOT NULL,
  UNIQUE(type_id, name)
);

CREATE TABLE materials (
  id SERIAL PRIMARY KEY,
  type_id INT REFERENCES material_types(id),
  code VARCHAR(100) UNIQUE NOT NULL,
  image_url TEXT,
  stock_quantity FLOAT NOT NULL CHECK (stock_quantity >= 0),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE material_spec_values (
  id SERIAL PRIMARY KEY,
  material_id INT REFERENCES materials(id) ON DELETE CASCADE,
  spec_id INT REFERENCES material_specs(id) ON DELETE CASCADE,
  value TEXT NOT NULL,
  UNIQUE(material_id, spec_id)
);

CREATE TABLE raw_inventory (
  id SERIAL PRIMARY KEY,
  warehouse_id INT REFERENCES warehouses(id),
  material_id INT REFERENCES materials(id),
  quantity FLOAT NOT NULL CHECK (quantity >= 0),
  last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (warehouse_id, material_id)
);

-- =========================================
-- 7. Model Composition and Production
-- =========================================
CREATE TABLE model_components (
  id SERIAL PRIMARY KEY,
  model_id INT REFERENCES models(id) ON DELETE CASCADE,
  material_id INT REFERENCES materials(id),
  quantity_needed FLOAT NOT NULL CHECK (quantity_needed >= 0),
  UNIQUE (model_id, material_id)
);

CREATE TABLE model_production (
  id SERIAL PRIMARY KEY,
  model_id INT REFERENCES models(id),
  color VARCHAR(50) NOT NULL,
  quantity INT NOT NULL CHECK (quantity >= 0),
  produced_at DATE DEFAULT CURRENT_DATE
);

CREATE TABLE production_batches (
  id SERIAL PRIMARY KEY,
  model_id INT REFERENCES models(id) ON DELETE CASCADE,
  production_date DATE DEFAULT CURRENT_DATE,
  color VARCHAR(50) NOT NULL,
  size VARCHAR(50) NOT NULL,
  quantity INT NOT NULL CHECK (quantity >= 0),
  status VARCHAR(20) NOT NULL DEFAULT 'in_progress' CHECK (status IN ('in_progress', 'completed', 'cancelled'))
);
ALTER TABLE production_batches
  ADD COLUMN manual_quantity INT NOT NULL DEFAULT 0,
  ADD COLUMN manual_cost NUMERIC(10,2) NOT NULL DEFAULT 0,
  ADD COLUMN automatic_quantity INT NOT NULL DEFAULT 0,
  ADD COLUMN automatic_cost NUMERIC(10,2) NOT NULL DEFAULT 0,
  ADD COLUMN average_cost NUMERIC(10,2) NOT NULL DEFAULT 0;

-- =========================================
-- 8. Purchases
-- =========================================
CREATE TABLE purchases (
  id SERIAL PRIMARY KEY,
  purchase_date DATE DEFAULT CURRENT_DATE,
  supplier_id INT REFERENCES suppliers(id) NOT NULL
);

CREATE TABLE purchase_items (
  id SERIAL PRIMARY KEY,
  purchase_id INT REFERENCES purchases(id) ON DELETE CASCADE,
  material_id INT REFERENCES materials(id),
  quantity FLOAT NOT NULL CHECK (quantity >= 0),
  unit_price NUMERIC(10,2) NOT NULL CHECK (unit_price >= 0)
);

-- =========================================
-- 9. Employees, Attendance, Loans
-- =========================================
CREATE TABLE employees (
  id SERIAL PRIMARY KEY,
  first_name VARCHAR(100) NOT NULL,
  last_name VARCHAR(100) NOT NULL,
  phone VARCHAR(20) NOT NULL UNIQUE,
  address TEXT NOT NULL,
  seller_type VARCHAR(10) NOT NULL CHECK (seller_type IN ('piece', 'month')),
  salary NUMERIC(10,2),
  photo_url TEXT,
  status VARCHAR(20) DEFAULT 'active' CHECK (status IN ('active', 'inactive', 'deleted')),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  role VARCHAR(50) NOT NULL DEFAULT 'خياطة',
  CONSTRAINT employees_role_type_check
    CHECK (
      (seller_type = 'month' AND role IN ('خياطة', 'فينيسيون')) OR
      (seller_type = 'piece' AND role IN ('كوي', 'خياطة', 'قص'))
    )
);

CREATE TABLE employee_attendance (
  id SERIAL PRIMARY KEY,
  employee_id INT REFERENCES employees(id),
  check_in TIMESTAMP,
  check_out TIMESTAMP,
  date DATE NOT NULL,
  UNIQUE(employee_id, date)
);

CREATE TABLE employee_loans (
  id SERIAL PRIMARY KEY,
  employee_id INT REFERENCES employees(id),
  amount NUMERIC(10,2) NOT NULL CHECK (amount >= 0),
  loan_date DATE DEFAULT CURRENT_DATE,
  duration_months INT NOT NULL DEFAULT 1
);

CREATE TABLE employee_loan_installments (
  id SERIAL PRIMARY KEY,
  loan_id INT NOT NULL REFERENCES employee_loans(id) ON DELETE CASCADE,
  installment_no INT NOT NULL,
  due_date DATE NOT NULL,
  amount NUMERIC(10,2) NOT NULL CHECK (amount >= 0),
  is_paid BOOLEAN NOT NULL DEFAULT FALSE,
  paid_date DATE NULL
);

-- =========================================
-- 10. Piece Records
-- =========================================
CREATE TABLE piece_records (
  id SERIAL PRIMARY KEY,
  employee_id INT REFERENCES employees(id),
  model_id INT REFERENCES models(id),
  quantity INT NOT NULL CHECK (quantity >= 0),
  piece_price NUMERIC(10,2) NOT NULL CHECK (piece_price >= 0),
  record_date DATE DEFAULT CURRENT_DATE
);

-- =========================================
-- 11. Factures and Sales
-- =========================================
CREATE TABLE factures (
  id SERIAL PRIMARY KEY,
  client_id INT REFERENCES clients(id),
  facture_name VARCHAR(100) NOT NULL,
  facture_date DATE DEFAULT CURRENT_DATE,
  total_amount NUMERIC(12,2) NOT NULL CHECK (total_amount >= 0),
  amount_paid_on_creation NUMERIC(12,2) DEFAULT 0 CHECK (amount_paid_on_creation >= 0 AND amount_paid_on_creation <= total_amount)
);

CREATE TABLE facture_items (
  id SERIAL PRIMARY KEY,
  facture_id INT REFERENCES factures(id) ON DELETE CASCADE,
  model_id INT REFERENCES models(id),
  color VARCHAR(50),
  quantity INT NOT NULL CHECK (quantity >= 0),
  unit_price NUMERIC(10,2) NOT NULL CHECK (unit_price >= 0)
);

CREATE TABLE facture_payments (
  id SERIAL PRIMARY KEY,
  facture_id INT REFERENCES factures(id) ON DELETE CASCADE,
  amount_paid NUMERIC(12,2) NOT NULL CHECK (amount_paid >= 0),
  payment_date DATE DEFAULT CURRENT_DATE
);

-- =========================================
-- 12. Seasons and Profit Reports
-- =========================================
CREATE TABLE seasons (
  id SERIAL PRIMARY KEY,
  name VARCHAR(100) NOT NULL,
  start_date DATE NOT NULL,
  end_date DATE NOT NULL
);

CREATE TABLE season_reports (
  id SERIAL PRIMARY KEY,
  season_id INT REFERENCES seasons(id),
  model_id INT REFERENCES models(id),
  quantity_sold INT NOT NULL,
  total_revenue NUMERIC(12,2) NOT NULL,
  total_cost NUMERIC(12,2) NOT NULL,
  profit NUMERIC(12,2) NOT NULL,
  calculated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(season_id, model_id)
);

-- =========================================
-- 13. Expenses
-- =========================================
CREATE TABLE expenses (
  id SERIAL PRIMARY KEY,
  expense_type VARCHAR(50) NOT NULL CHECK (
    expense_type IN ('electricity', 'rent', 'water', 'maintenance', 'transport', 'custom')
  ),
  description TEXT,
  amount NUMERIC(12,2) NOT NULL CHECK (amount >= 0),
  expense_date DATE NOT NULL DEFAULT CURRENT_DATE,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- End of schema
CREATE TABLE purchase_payments (
  id SERIAL PRIMARY KEY,
  purchase_id INT REFERENCES sewing.purchases(id) ON DELETE CASCADE,
  amount_paid NUMERIC(12,2) NOT NULL CHECK (amount_paid >= 0),
  payment_date DATE DEFAULT CURRENT_DATE,
  method VARCHAR(50),             -- e.g. 'bank', 'cash', 'cheque'
  notes TEXT
);
ALTER TABLE purchases
  ADD COLUMN amount_paid_on_creation NUMERIC(12,2)
    DEFAULT 0 CHECK (amount_paid_on_creation >= 0);

ALTER TABLE sewing.models ADD COLUMN global_price NUMERIC(10,2) DEFAULT 0;

CREATE TABLE sewing.employee_debts (
  id SERIAL PRIMARY KEY,
  employee_id INT REFERENCES sewing.employees(id) ON DELETE CASCADE,
  amount NUMERIC(10,2) NOT NULL CHECK (amount >= 0),
  debt_date DATE NOT NULL DEFAULT CURRENT_DATE,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- =========================================
-- 14. Returns Management (مرتجع بضاعه)
-- =========================================
CREATE TABLE sewing.returns (
  id SERIAL PRIMARY KEY,
  facture_id INT REFERENCES sewing.factures(id) ON DELETE CASCADE,
  model_id INT REFERENCES sewing.models(id),
  quantity INT NOT NULL CHECK (quantity > 0),
  return_date DATE DEFAULT CURRENT_DATE,
  is_ready_to_sell BOOLEAN NOT NULL DEFAULT FALSE,
  repair_materials JSONB, -- Array of {material_id, quantity, cost}
  repair_cost NUMERIC(10,2) DEFAULT 0 CHECK (repair_cost >= 0),
  notes TEXT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Index for performance
CREATE INDEX idx_returns_facture_id ON sewing.returns(facture_id);
CREATE INDEX idx_returns_model_id ON sewing.returns(model_id);
CREATE INDEX idx_returns_return_date ON sewing.returns(return_date);
ALTER TABLE sewing.product_inventory 
ALTER COLUMN color DROP NOT NULL,
ALTER COLUMN size DROP NOT NULL;