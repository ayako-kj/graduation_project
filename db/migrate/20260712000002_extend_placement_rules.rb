class ExtendPlacementRules < ActiveRecord::Migration[7.2]
  def up
    add_column :placement_rules, :rule_type, :string, default: "min_count", null: false
    add_column :placement_rules, :employment_type_id, :bigint
    add_column :placement_rules, :staff_type_ids, :text
    change_column_null :placement_rules, :staff_type_id, true
    add_foreign_key :placement_rules, :employment_types
  end

  def down
    remove_foreign_key :placement_rules, :employment_types
    change_column_null :placement_rules, :staff_type_id, false
    remove_column :placement_rules, :staff_type_ids
    remove_column :placement_rules, :employment_type_id
    remove_column :placement_rules, :rule_type
  end
end
