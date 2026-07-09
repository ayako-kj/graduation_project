class CreateSpecialDateStaffs < ActiveRecord::Migration[7.2]
  def change
    create_table :special_date_staffs do |t|
      t.references :special_date, null: false, foreign_key: true
      t.references :staff, null: false, foreign_key: true

      t.timestamps
    end
  end
end
