-- =========================================================
-- 0) Schema
-- =========================================================
CREATE SCHEMA IF NOT EXISTS design;

-- =========================================================
-- 1) Clients & Suppliers
-- =========================================================
CREATE TABLE design.clients (
  id SERIAL PRIMARY KEY,
  full_name VARCHAR(100) NOT NULL,
  phone VARCHAR(20) NOT NULL UNIQUE,
  address TEXT NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE design.suppliers (
  id SERIAL PRIMARY KEY,
  full_name VARCHAR(100) NOT NULL,
  phone VARCHAR(20) NOT NULL UNIQUE,
  address TEXT NOT NULL,
  company_name VARCHAR(100),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- =========================================================
-- 2) Warehouses
-- =========================================================
CREATE TABLE design.warehouses (
  id SERIAL PRIMARY KEY,
  name VARCHAR(100) NOT NULL,
  type VARCHAR(20) NOT NULL CHECK (type IN ('ready', 'raw')),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- =========================================================
-- 3) Raw Materials
-- =========================================================
CREATE TABLE design.material_types (
  id SERIAL PRIMARY KEY,
  name VARCHAR(100) UNIQUE NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE design.material_specs (
  id SERIAL PRIMARY KEY,
  type_id INT NOT NULL REFERENCES design.material_types(id) ON DELETE CASCADE,
  name VARCHAR(100) NOT NULL,
  UNIQUE(type_id, name)
);

CREATE TABLE design.materials (
  id SERIAL PRIMARY KEY,
  type_id INT NOT NULL REFERENCES design.material_types(id),
  code VARCHAR(100) UNIQUE NOT NULL,
  image_url TEXT,
  stock_quantity FLOAT NOT NULL CHECK (stock_quantity >= 0),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE design.material_spec_values (
  id SERIAL PRIMARY KEY,
  material_id INT NOT NULL REFERENCES design.materials(id) ON DELETE CASCADE,
  spec_id INT NOT NULL REFERENCES design.material_specs(id) ON DELETE CASCADE,
  value TEXT NOT NULL,
  UNIQUE(material_id, spec_id)
);

CREATE TABLE design.raw_inventory (
  id SERIAL PRIMARY KEY,
  warehouse_id INT NOT NULL REFERENCES design.warehouses(id),
  material_id INT NOT NULL REFERENCES design.materials(id),
  quantity FLOAT NOT NULL CHECK (quantity >= 0),
  last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (warehouse_id, material_id)
);

-- =========================================================
-- 4) Models (NO cost columns)
-- =========================================================
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'placed_status') THEN
    CREATE TYPE design.placed_status AS ENUM ('placed','unplaced');
  END IF;
END$$;

BEGIN;

-- حذف الجداول القديمة إن وُجدت
DROP TABLE IF EXISTS design.models CASCADE;
DROP TABLE IF EXISTS design.seasons CASCADE;
DROP TABLE IF EXISTS design.clients CASCADE; -- فقط إذا لم تكن موجودة أو كنت تستخدم جدولاً آخر

-- مثال لجدول العملاء في design (إن لم يكن عندك)
CREATE TABLE IF NOT EXISTS design.clients (
  id SERIAL PRIMARY KEY,
  full_name VARCHAR(150) NOT NULL,
  phone     VARCHAR(50),
  address   TEXT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- جدول المواسم في design
CREATE TABLE design.seasons (
  id SERIAL PRIMARY KEY,
  name        VARCHAR(120) NOT NULL,
  start_date  DATE NOT NULL,
  end_date    DATE NOT NULL,
  created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_design_seasons_range ON design.seasons (start_date, end_date);

-- جدول الموديلات في design
CREATE TABLE design.models (
  id           SERIAL PRIMARY KEY,
  client_id    INT NOT NULL REFERENCES design.clients(id) ON DELETE RESTRICT,
  season_id    INT REFERENCES design.seasons(id) ON DELETE SET NULL,   -- يملأ تلقائياً
  model_date   DATE NOT NULL,                                          -- تاريخ الموديل (يختاره المستخدم)
  model_name   VARCHAR(100) NOT NULL,
  marker_name  VARCHAR(100) NOT NULL,
  length       NUMERIC(10,2) NOT NULL CHECK (length >= 0),
  width        NUMERIC(10,2) NOT NULL CHECK (width  >= 0),
  util_percent NUMERIC(5,2)  NOT NULL CHECK (util_percent >= 0 AND util_percent <= 100),
  placed       VARCHAR(50)   NOT NULL,
  sizes_text   TEXT          NOT NULL DEFAULT '',   -- "355:2, 43:1"
  price        NUMERIC(12,2) NOT NULL CHECK (price >= 0),
  description  TEXT,
  image_url    TEXT,
  created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_design_models_client  ON design.models (client_id);
CREATE INDEX idx_design_models_season  ON design.models (season_id);
CREATE INDEX idx_design_models_date    ON design.models (model_date);
CREATE INDEX idx_design_models_created ON design.models (created_at DESC);

COMMIT;

CREATE TABLE design.model_sizes (
  id SERIAL PRIMARY KEY,
  model_id INT NOT NULL REFERENCES design.models(id) ON DELETE CASCADE,
  size_label VARCHAR(20) NOT NULL,
  quantity INT NOT NULL CHECK (quantity >= 0),
  UNIQUE(model_id, size_label)
);

CREATE TABLE design.model_colors (
  id SERIAL PRIMARY KEY,
  model_id INT NOT NULL REFERENCES design.models(id) ON DELETE CASCADE,
  color VARCHAR(50) NOT NULL,
  UNIQUE (model_id, color)
);

CREATE TABLE design.model_components (
  id SERIAL PRIMARY KEY,
  model_id INT NOT NULL REFERENCES design.models(id) ON DELETE CASCADE,
  material_id INT NOT NULL REFERENCES design.materials(id),
  quantity_needed FLOAT NOT NULL CHECK (quantity_needed >= 0),
  UNIQUE (model_id, material_id)
);

-- =========================================================
-- 5) Ready Product Inventory
-- =========================================================
CREATE TABLE design.product_inventory (
  id SERIAL PRIMARY KEY,
  warehouse_id INT NOT NULL REFERENCES design.warehouses(id),
  model_id INT NOT NULL REFERENCES design.models(id),
  color VARCHAR(50),
  size_label VARCHAR(20),
  quantity FLOAT NOT NULL CHECK (quantity >= 0),
  last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT unique_wh_model_color_size UNIQUE (warehouse_id, model_id, color, size_label)
);

-- =========================================================
-- 6) Production Batches (no costs)
-- =========================================================
CREATE TABLE design.production_batches (
  id SERIAL PRIMARY KEY,
  model_id INT NOT NULL REFERENCES design.models(id) ON DELETE CASCADE,
  production_date DATE DEFAULT CURRENT_DATE,
  color VARCHAR(50),
  size_label VARCHAR(50),
  quantity INT NOT NULL CHECK (quantity >= 0),
  status VARCHAR(20) NOT NULL DEFAULT 'in_progress'
    CHECK (status IN ('in_progress','completed','cancelled'))
);

-- =========================================================
-- 7) Purchases & Payments
-- =========================================================
CREATE TABLE design.purchases (
  id SERIAL PRIMARY KEY,
  purchase_date DATE DEFAULT CURRENT_DATE,
  supplier_id INT NOT NULL REFERENCES design.suppliers(id),
  amount_paid_on_creation NUMERIC(12,2) DEFAULT 0 CHECK (amount_paid_on_creation >= 0)
);

CREATE TABLE design.purchase_items (
  id SERIAL PRIMARY KEY,
  purchase_id INT NOT NULL REFERENCES design.purchases(id) ON DELETE CASCADE,
  material_id INT NOT NULL REFERENCES design.materials(id),
  quantity FLOAT NOT NULL CHECK (quantity >= 0),
  unit_price NUMERIC(10,2) NOT NULL CHECK (unit_price >= 0)
);

CREATE TABLE design.purchase_payments (
  id SERIAL PRIMARY KEY,
  purchase_id INT NOT NULL REFERENCES design.purchases(id) ON DELETE CASCADE,
  amount_paid NUMERIC(12,2) NOT NULL CHECK (amount_paid >= 0),
  payment_date DATE DEFAULT CURRENT_DATE,
  method VARCHAR(50),
  notes TEXT
);

-- =========================================================
-- 8) Sales / Factures
-- =========================================================
CREATE TABLE design.factures (
  id SERIAL PRIMARY KEY,
  client_id INT NOT NULL REFERENCES design.clients(id),
  facture_name VARCHAR(100) NOT NULL,
  facture_date DATE DEFAULT CURRENT_DATE,
  total_amount NUMERIC(12,2) NOT NULL CHECK (total_amount >= 0),
  amount_paid_on_creation NUMERIC(12,2) DEFAULT 0
    CHECK (amount_paid_on_creation >= 0 AND amount_paid_on_creation <= total_amount)
);

CREATE TABLE design.facture_items (
  id SERIAL PRIMARY KEY,
  facture_id INT NOT NULL REFERENCES design.factures(id) ON DELETE CASCADE,
  model_id INT NOT NULL REFERENCES design.models(id),
  color VARCHAR(50),
  quantity INT NOT NULL CHECK (quantity >= 0),
  unit_price NUMERIC(10,2) NOT NULL CHECK (unit_price >= 0)
);

CREATE TABLE design.facture_payments (
  id SERIAL PRIMARY KEY,
  facture_id INT NOT NULL REFERENCES design.factures(id) ON DELETE CASCADE,
  amount_paid NUMERIC(12,2) NOT NULL CHECK (amount_paid >= 0),
  payment_date DATE DEFAULT CURRENT_DATE
);

-- =========================================================
-- 9) Seasons & Reports
-- =========================================================
CREATE TABLE design.seasons (
  id SERIAL PRIMARY KEY,
  name VARCHAR(100) NOT NULL,
  start_date DATE NOT NULL,
  end_date DATE NOT NULL
);

CREATE TABLE design.season_reports (
  id SERIAL PRIMARY KEY,
  season_id INT NOT NULL REFERENCES design.seasons(id),
  model_id INT NOT NULL REFERENCES design.models(id),
  quantity_sold INT NOT NULL,
  total_revenue NUMERIC(12,2) NOT NULL,
  total_cost NUMERIC(12,2) NOT NULL,
  profit NUMERIC(12,2) NOT NULL,
  calculated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(season_id, model_id)
);

-- =========================================================
-- 10) Expenses
-- =========================================================
CREATE TABLE design.expenses (
  id SERIAL PRIMARY KEY,
  expense_type VARCHAR(50) NOT NULL CHECK (
    expense_type IN ('electricity', 'rent', 'water', 'maintenance', 'transport', 'custom')
  ),
  description TEXT,
  amount NUMERIC(12,2) NOT NULL CHECK (amount >= 0),
  expense_date DATE NOT NULL DEFAULT CURRENT_DATE,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- =========================================================
-- 11) Returns
-- =========================================================
CREATE TABLE design.returns (
  id SERIAL PRIMARY KEY,
  facture_id INT NOT NULL REFERENCES design.factures(id) ON DELETE CASCADE,
  model_id INT NOT NULL REFERENCES design.models(id),
  quantity INT NOT NULL CHECK (quantity > 0),
  return_date DATE DEFAULT CURRENT_DATE,
  is_ready_to_sell BOOLEAN NOT NULL DEFAULT FALSE,
  repair_materials JSONB,
  repair_cost NUMERIC(10,2) DEFAULT 0 CHECK (repair_cost >= 0),
  notes TEXT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_design_returns_facture_id  ON design.returns(facture_id);
CREATE INDEX idx_design_returns_model_id    ON design.returns(model_id);
CREATE INDEX idx_design_returns_return_date ON design.returns(return_date);



-- 1) add the new type (if you are using an enum)
-- ALTER TYPE expense_type_enum ADD VALUE 'raw_materials';  -- only if enum

-- 2) add nullable columns for raw-material usage
ALTER TABLE design.expenses
  ADD COLUMN material_type_id INT NULL,
  ADD COLUMN material_id      INT NULL,
  ADD COLUMN quantity         NUMERIC(12,3) NULL,
  ADD COLUMN unit_price       NUMERIC(12,3) NULL;

-- 3) optional FKs (adjust table names)
ALTER TABLE design.expenses
  ADD CONSTRAINT fk_exp_mat_type
    FOREIGN KEY (material_type_id) REFERENCES design.material_types(id) ON DELETE SET NULL,
  ADD CONSTRAINT fk_exp_material
    FOREIGN KEY (material_id) REFERENCES design.materials(id) ON DELETE SET NULL;

-- 4) safety check
ALTER TABLE design.expenses
  ADD CONSTRAINT chk_raw_materials_fields
  CHECK (
    (expense_type <> 'raw_materials')
    OR
    (expense_type = 'raw_materials' AND material_id IS NOT NULL AND quantity IS NOT NULL AND unit_price IS NOT NULL)
  );
-- 1) Drop the old CHECK
ALTER TABLE design.expenses
  DROP CONSTRAINT IF EXISTS expenses_expense_type_check;

-- 2) Re-add it with raw_materials and WITHOUT transport
ALTER TABLE design.expenses
  ADD CONSTRAINT expenses_expense_type_check
  CHECK (expense_type IN ('electricity','rent','water','maintenance','custom','raw_materials'));
