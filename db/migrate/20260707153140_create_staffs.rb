class CreateStaffs < ActiveRecord::Migration[7.2]
  def change
    create_table :staffs do |t|
      t.string :name
      t.references :staff_type, null: false, foreign_key: true
      t.references :employment_type, null: false, foreign_key: true
      t.integer :weekly_work_days

      t.timestamps
    end
  end
end
