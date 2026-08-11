class CreateInputDeadlines < ActiveRecord::Migration[8.1]
  def change
    create_table :input_deadlines do |t|
      t.references :library, null: false, foreign_key: true
      t.date :target_month, null: false
      t.date :leave_deadline_on
      t.date :schedule_deadline_on

      t.timestamps
    end
    add_index :input_deadlines, [:library_id, :target_month], unique: true
  end
end
