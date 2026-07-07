class CreateShifts < ActiveRecord::Migration[7.2]
  def change
    create_table :shifts do |t|
      t.references :shift_group, null: false, foreign_key: true
      t.references :staff, null: false, foreign_key: true
      t.date :date
      t.boolean :is_working
      t.text :validation_errors

      t.timestamps
    end
  end
end
