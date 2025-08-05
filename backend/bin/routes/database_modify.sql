-- 1) Drop the old FK from material_specs → material_types
ALTER TABLE sewing.material_specs
  DROP CONSTRAINT IF EXISTS material_specs_type_id_fkey;

-- 2) Re-create it with cascades
ALTER TABLE sewing.material_specs
  ADD CONSTRAINT material_specs_type_id_fkey
  FOREIGN KEY (type_id)
    REFERENCES sewing.material_types (id)
    ON UPDATE CASCADE
    ON DELETE CASCADE;

-- 3) Drop the old FK from material_spec_values → material_specs
ALTER TABLE sewing.material_spec_values
  DROP CONSTRAINT IF EXISTS material_spec_values_spec_id_fkey;

-- 4) Re-create it with cascades
ALTER TABLE sewing.material_spec_values
  ADD CONSTRAINT material_spec_values_spec_id_fkey
  FOREIGN KEY (spec_id)
    REFERENCES sewing.material_specs (id)
    ON UPDATE CASCADE
    ON DELETE CASCADE;



ALTER TABLE embroidery.models 
ADD COLUMN image_url TEXT DEFAULT '';
ALTER TABLE design.models
ADD COLUMN image_url TEXT DEFAULT '';-- once, in your migration:
CREATE UNIQUE INDEX uq_product_inventory_per_model
  ON sewing.product_inventory(warehouse_id, model_id);


ALTER TABLE embroidery.raw_inventory
  DROP CONSTRAINT raw_inventory_material_id_fkey;

ALTER TABLE embroidery.raw_inventory
  ADD CONSTRAINT raw_inventory_material_id_fkey
    FOREIGN KEY(material_id)
    REFERENCES embroidery.materials(id)
    ON DELETE CASCADE;