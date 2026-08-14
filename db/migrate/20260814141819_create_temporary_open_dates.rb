class CreateTemporaryOpenDates < ActiveRecord::Migration[8.1]
  def change
    create_table :temporary_open_dates do |t|
      t.references :library, null: false, foreign_key: true
      t.date :date, null: false
      t.string :label

      t.timestamps
    end
    add_index :temporary_open_dates, [:library_id, :date], unique: true
  end
end
