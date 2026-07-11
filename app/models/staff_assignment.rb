class StaffAssignment < ApplicationRecord
  belongs_to :staff
  belongs_to :assignment
end
