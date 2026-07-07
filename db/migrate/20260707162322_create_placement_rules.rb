class CreatePlacementRules < ActiveRecord::Migration[7.2]
  def change
    create_table :placement_rules do |t|
      t.references :staff_type, null: false, foreign_key: true
      t.integer :min_count

      t.timestamps
    end
  end
end
