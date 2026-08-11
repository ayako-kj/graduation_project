class ChangeInputDeadlinesToSingleDeadline < ActiveRecord::Migration[8.1]
  def change
    add_column :input_deadlines, :deadline_on, :date
    remove_column :input_deadlines, :leave_deadline_on, :date
    remove_column :input_deadlines, :schedule_deadline_on, :date
  end
end
