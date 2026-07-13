class CreateShiftSnapshots < ActiveRecord::Migration[7.2]
  def change
    create_table :shift_snapshots do |t|
      t.references :library, null: false, foreign_key: true
      t.date :target_month, null: false
      t.text :snapshot_data, null: false
      t.datetime :confirmed_at, null: false
      t.timestamps
    end

    add_index :shift_snapshots, [:library_id, :target_month], unique: true
  end
end
