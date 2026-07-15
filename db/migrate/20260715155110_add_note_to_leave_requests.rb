class AddNoteToLeaveRequests < ActiveRecord::Migration[7.2]
  def change
    add_column :leave_requests, :note, :string
  end
end
