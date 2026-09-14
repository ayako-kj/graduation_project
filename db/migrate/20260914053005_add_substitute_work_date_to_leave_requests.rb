class AddSubstituteWorkDateToLeaveRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :leave_requests, :substitute_work_date, :date
  end
end
