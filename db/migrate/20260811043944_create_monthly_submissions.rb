class CreateMonthlySubmissions < ActiveRecord::Migration[8.1]
  def change
    create_table :monthly_submissions do |t|
      t.references :staff, null: false, foreign_key: true
      t.date :target_month, null: false
      t.datetime :leave_submitted_at
      t.datetime :schedule_submitted_at

      t.timestamps
    end
    add_index :monthly_submissions, [:staff_id, :target_month], unique: true
  end
end
