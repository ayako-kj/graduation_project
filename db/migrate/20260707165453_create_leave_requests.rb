class CreateLeaveRequests < ActiveRecord::Migration[7.2]
  def change
    create_table :leave_requests do |t|
      t.references :staff, null: false, foreign_key: true
      t.date :date
      t.string :reason

      t.timestamps
    end
  end
end
